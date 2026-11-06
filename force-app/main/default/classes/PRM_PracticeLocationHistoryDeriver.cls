/*
 * @ClassName    : PRM_PracticeLocationHistoryDeriver
 * @TestClassName: PRM_PracticeLocationHistoryDeriverTest
 * @CreatedOn    : 24-SEP-2026
 * @CreatedBy    : IBX
 * @Description  : Pure (no SOQL/DML) rules that turn raw field-history rows into the
 *                 business events shown by prmPracticeLocationHistory:
 *                   - de-duplicate live vs archived rows on HistoryId (live wins)
 *                   - collapse a lookup change's Id row + name row into one row
 *                   - classify each row (Added / Removed / Scheduled removal / ...)
 *                   - resolve the Case Manager in effect at the time of the change
 *                   - group rows written together by one user into one change event
 *                   - flag integration users
 */
public with sharing class PRM_PracticeLocationHistoryDeriver {
  public static final String ADDED = 'Added';
  public static final String REMOVED = 'Removed';
  public static final String SCHEDULED_REMOVAL = 'Scheduled removal';
  public static final String REINSTATED = 'Reinstated';
  public static final String DEACTIVATED = 'Deactivated';
  public static final String REACTIVATED = 'Reactivated';
  public static final String END_DATE_CHANGED = 'End date changed';
  public static final String START_DATE_CHANGED = 'Start date changed';
  public static final String MARKED_AS_ERROR = 'Marked as error';
  public static final String ERROR_CLEARED = 'Error cleared';
  public static final String PENDING = 'Pending';
  public static final String PENDING_CLEARED = 'Pending cleared';
  public static final String PRIMARY_CHANGED = 'Primary changed';
  public static final String PANEL_STATUS_CHANGED = 'Panel status changed';
  public static final String UPDATED = 'Updated';

  @TestVisible
  private static final Integer GROUPING_WINDOW_SECONDS = 60;

  private static final String CREATED_FIELD = 'created';
  private static final Set<String> END_DATE_FIELDS = new Set<String>{
    'EffectiveTo',
    'PRM_EffectiveTo__c'
  };
  private static final Set<String> START_DATE_FIELDS = new Set<String>{
    'EffectiveFrom',
    'PRM_EffectiveFrom__c'
  };
  private static final Set<String> ACTIVE_FIELDS = new Set<String>{
    'IsActive',
    'PRM_Active__c'
  };
  private static final Set<String> PRIMARY_FIELDS = new Set<String>{
    'IsPrimaryFacility',
    'IsPrimaryTaxonomy',
    'PRM_Primary__c'
  };
  private static final Set<String> ADD_REMOVE_TYPES = new Set<String>{
    ADDED,
    REMOVED,
    SCHEDULED_REMOVAL,
    REINSTATED,
    DEACTIVATED,
    REACTIVATED
  };
  private static final Set<String> INTEGRATION_USER_TYPES = new Set<String>{
    'CloudIntegrationUser',
    'AutomatedProcess'
  };
  private static final Pattern ISO_DATE = Pattern.compile(
    '^\\d{4}-\\d{2}-\\d{2}( 00:00:00)?$'
  );
  // {0} = subject phrase, {1} = effective-date suffix, {2} = field label
  private static final Map<String, String> SENTENCE_TEMPLATES = new Map<String, String>{
    ADDED => '{0} added',
    REMOVED => '{0} removed{1}',
    SCHEDULED_REMOVAL => '{0} scheduled for removal{1}',
    REINSTATED => '{0} reinstated',
    DEACTIVATED => '{0} deactivated',
    REACTIVATED => '{0} reactivated',
    END_DATE_CHANGED => '{0}: end date changed{1}',
    START_DATE_CHANGED => '{0}: start date changed{1}',
    MARKED_AS_ERROR => '{0} marked as error',
    ERROR_CLEARED => '{0}: error flag cleared',
    PENDING => '{0} set to pending',
    PENDING_CLEARED => '{0}: pending cleared',
    PRIMARY_CHANGED => '{0}: {2} changed',
    PANEL_STATUS_CHANGED => '{0}: panel status changed',
    UPDATED => '{0}: {2} changed'
  };

  public List<PRM_PracticeLocationHistoryModel.RawHistoryRow> mergeRows(
    List<PRM_PracticeLocationHistoryModel.RawHistoryRow> rows
  ) {
    Map<String, List<PRM_PracticeLocationHistoryModel.RawHistoryRow>> rowsByChange = new Map<String, List<PRM_PracticeLocationHistoryModel.RawHistoryRow>>();
    for (
      PRM_PracticeLocationHistoryModel.RawHistoryRow row : dedupeByHistoryId(
        rows
      )
    ) {
      String key = changeKey(row);
      if (!rowsByChange.containsKey(key)) {
        rowsByChange.put(
          key,
          new List<PRM_PracticeLocationHistoryModel.RawHistoryRow>()
        );
      }
      rowsByChange.get(key).add(row);
    }
    List<PRM_PracticeLocationHistoryModel.RawHistoryRow> merged = new List<PRM_PracticeLocationHistoryModel.RawHistoryRow>();
    for (
      List<PRM_PracticeLocationHistoryModel.RawHistoryRow> change : rowsByChange.values()
    ) {
      merged.addAll(collapseLookupPair(change));
    }
    return merged;
  }

  public PRM_PracticeLocationHistoryModel.HistoryEvent buildEvent(
    PRM_PracticeLocationHistoryModel.RawHistoryRow row,
    PRM_PracticeLocationHistoryModel.ChildRecord child,
    String fieldLabel
  ) {
    PRM_PracticeLocationHistoryModel.HistoryEvent event = new PRM_PracticeLocationHistoryModel.HistoryEvent();
    event.id = row.historyId;
    event.recordId = row.parentId;
    event.category = child.config.category;
    event.subject = child.subject;
    event.context = child.context;
    event.eventDate = row.createdDate;
    event.actorId = row.createdById;
    event.isArchived = row.isArchived;
    event.fieldLabel = row.field == CREATED_FIELD ? null : fieldLabel;
    event.oldValue = displayValue(row.oldValue);
    event.newValue = displayValue(row.newValue);
    event.eventType = classify(row);
    event.isAddOrRemove = ADD_REMOVE_TYPES.contains(event.eventType);
    event.effectiveDate = effectiveDateFor(event.eventType, row, child);
    event.recordEffectiveFrom = child.effectiveFrom;
    event.sentence = composeSentence(event, child.config);
    return event;
  }

  /*
   * Value of the Case Manager lookup at the moment of a change: the latest Case Manager
   * change at or before it (within the grouping window, so a change made in the same
   * save counts), otherwise the value the first later change replaced, otherwise the
   * record's current value (never changed).
   */
  public Id caseManagerAt(
    List<PRM_PracticeLocationHistoryModel.RawHistoryRow> changesOldestFirst,
    Datetime changedAt,
    Id currentValue
  ) {
    if (
      changesOldestFirst == null ||
      changesOldestFirst.isEmpty() ||
      changedAt == null
    ) {
      return currentValue;
    }
    Datetime cutoff = changedAt.addSeconds(GROUPING_WINDOW_SECONDS);
    PRM_PracticeLocationHistoryModel.RawHistoryRow latestBefore;
    for (
      PRM_PracticeLocationHistoryModel.RawHistoryRow change : changesOldestFirst
    ) {
      if (change.createdDate > cutoff) {
        break;
      }
      latestBefore = change;
    }
    if (latestBefore != null) {
      return recordIdOf(latestBefore.newRecordId, latestBefore.newValue);
    }
    PRM_PracticeLocationHistoryModel.RawHistoryRow firstAfter = changesOldestFirst[0];
    return recordIdOf(firstAfter.oldRecordId, firstAfter.oldValue);
  }

  /*
   * Events must be sorted newest first. Consecutive events by the same user, under the
   * same Case Manager, within GROUPING_WINDOW_SECONDS of the group's first event share
   * a groupKey so the LWC can show them as one expandable change.
   */
  public void assignGroups(
    List<PRM_PracticeLocationHistoryModel.HistoryEvent> eventsNewestFirst
  ) {
    PRM_PracticeLocationHistoryModel.HistoryEvent anchor;
    for (
      PRM_PracticeLocationHistoryModel.HistoryEvent event : eventsNewestFirst
    ) {
      if (anchor != null && belongsToGroup(anchor, event)) {
        event.groupKey = anchor.groupKey;
      } else {
        event.groupKey = event.id;
        anchor = event;
      }
    }
  }

  public Boolean isIntegrationUser(
    User actor,
    Set<String> integrationUserNames
  ) {
    if (actor == null) {
      return false;
    }
    return INTEGRATION_USER_TYPES.contains(actor.UserType) ||
      (actor.Name != null &&
      integrationUserNames.contains(actor.Name.trim().toLowerCase()));
  }

  @TestVisible
  private String classify(PRM_PracticeLocationHistoryModel.RawHistoryRow row) {
    String field = row.field;
    if (field == CREATED_FIELD) {
      return ADDED;
    }
    if (END_DATE_FIELDS.contains(field)) {
      return classifyEndDate(
        toDate(row.oldValue),
        toDate(row.newValue),
        row.createdDate == null ? Date.today() : row.createdDate.date()
      );
    }
    if (START_DATE_FIELDS.contains(field)) {
      return START_DATE_CHANGED;
    }
    if (ACTIVE_FIELDS.contains(field)) {
      return isTrue(row.newValue) ? REACTIVATED : DEACTIVATED;
    }
    if (field == 'PRM_IsErrorRecord__c') {
      return isTrue(row.newValue) ? MARKED_AS_ERROR : ERROR_CLEARED;
    }
    if (field == 'PRM_Pending__c') {
      return isTrue(row.newValue) ? PENDING : PENDING_CLEARED;
    }
    if (PRIMARY_FIELDS.contains(field)) {
      return PRIMARY_CHANGED;
    }
    if (field == 'PanelStatus') {
      return PANEL_STATUS_CHANGED;
    }
    return UPDATED;
  }

  /*
   * Judged against the day the change was made, not today: an end date set to a past or
   * same-day date was an immediate removal; a later date was a scheduled one.
   */
  @TestVisible
  private static String classifyEndDate(
    Date oldEnd,
    Date newEnd,
    Date changedOn
  ) {
    if (oldEnd == null && newEnd != null) {
      return newEnd <= changedOn ? REMOVED : SCHEDULED_REMOVAL;
    }
    if (oldEnd != null && newEnd == null) {
      return REINSTATED;
    }
    if (oldEnd != null && newEnd != null) {
      if (oldEnd <= changedOn && newEnd > changedOn) {
        return REINSTATED;
      }
      if (oldEnd > changedOn && newEnd <= changedOn) {
        return REMOVED;
      }
    }
    return END_DATE_CHANGED;
  }

  private static Date effectiveDateFor(
    String eventType,
    PRM_PracticeLocationHistoryModel.RawHistoryRow row,
    PRM_PracticeLocationHistoryModel.ChildRecord child
  ) {
    if (eventType == ADDED) {
      return child.effectiveFrom;
    }
    if (
      eventType == REMOVED ||
      eventType == SCHEDULED_REMOVAL ||
      eventType == END_DATE_CHANGED ||
      eventType == START_DATE_CHANGED
    ) {
      return toDate(row.newValue);
    }
    return null;
  }

  private static String composeSentence(
    PRM_PracticeLocationHistoryModel.HistoryEvent event,
    PRM_PracticeLocationHistoryModel.CategoryConfig config
  ) {
    String subjectPhrase = config.subjectLabel;
    if (
      !config.isPracticeLocationItself() && String.isNotBlank(event.subject)
    ) {
      subjectPhrase += ' ' + event.subject;
    }
    if (String.isNotBlank(event.context)) {
      subjectPhrase += ' (' + event.context + ')';
    }
    if (event.eventType == ADDED && config.isPracticeLocationItself()) {
      return subjectPhrase + ' created';
    }
    String effectiveSuffix = event.effectiveDate == null
      ? ''
      : ', effective ' + event.effectiveDate.format();
    String fieldLabel = String.isBlank(event.fieldLabel)
      ? 'a field'
      : event.fieldLabel;
    return String.format(
      SENTENCE_TEMPLATES.get(event.eventType),
      new List<Object>{ subjectPhrase, effectiveSuffix, fieldLabel }
    );
  }

  private static Boolean belongsToGroup(
    PRM_PracticeLocationHistoryModel.HistoryEvent anchor,
    PRM_PracticeLocationHistoryModel.HistoryEvent event
  ) {
    if (anchor.eventDate == null || event.eventDate == null) {
      return false;
    }
    Long gapMillis = anchor.eventDate.getTime() - event.eventDate.getTime();
    return anchor.actorId == event.actorId &&
      anchor.caseManagerId == event.caseManagerId &&
      gapMillis <= GROUPING_WINDOW_SECONDS * 1000;
  }

  private static List<PRM_PracticeLocationHistoryModel.RawHistoryRow> dedupeByHistoryId(
    List<PRM_PracticeLocationHistoryModel.RawHistoryRow> rows
  ) {
    Map<String, PRM_PracticeLocationHistoryModel.RawHistoryRow> byHistoryId = new Map<String, PRM_PracticeLocationHistoryModel.RawHistoryRow>();
    for (PRM_PracticeLocationHistoryModel.RawHistoryRow row : rows) {
      PRM_PracticeLocationHistoryModel.RawHistoryRow existing = byHistoryId.get(
        row.historyId
      );
      if (existing == null || (existing.isArchived && !row.isArchived)) {
        byHistoryId.put(row.historyId, row);
      }
    }
    return byHistoryId.values();
  }

  private static String changeKey(
    PRM_PracticeLocationHistoryModel.RawHistoryRow row
  ) {
    return row.parentId +
      '|' +
      row.field +
      '|' +
      (row.createdDate == null
        ? ''
        : String.valueOf(row.createdDate.getTime())) +
      '|' +
      row.createdById;
  }

  /*
   * A lookup change writes two rows with the same parent/field/time/user: one holding
   * record Ids, one holding names. Keep the name row for display and carry the Ids on it.
   * Values are inspected rather than DataType because FieldHistoryArchive has no DataType.
   */
  private static List<PRM_PracticeLocationHistoryModel.RawHistoryRow> collapseLookupPair(
    List<PRM_PracticeLocationHistoryModel.RawHistoryRow> change
  ) {
    if (change.size() != 2) {
      return change;
    }
    PRM_PracticeLocationHistoryModel.RawHistoryRow idRow;
    PRM_PracticeLocationHistoryModel.RawHistoryRow nameRow;
    for (PRM_PracticeLocationHistoryModel.RawHistoryRow row : change) {
      if (holdsRecordIds(row)) {
        idRow = row;
      } else {
        nameRow = row;
      }
    }
    if (idRow == null || nameRow == null) {
      return change;
    }
    nameRow.oldRecordId = recordIdOf(null, idRow.oldValue);
    nameRow.newRecordId = recordIdOf(null, idRow.newValue);
    return new List<PRM_PracticeLocationHistoryModel.RawHistoryRow>{ nameRow };
  }

  private static Boolean holdsRecordIds(
    PRM_PracticeLocationHistoryModel.RawHistoryRow row
  ) {
    Boolean oldBlank = isBlank(row.oldValue);
    Boolean newBlank = isBlank(row.newValue);
    if (oldBlank && newBlank) {
      return false;
    }
    return (oldBlank || looksLikeRecordId(row.oldValue)) &&
      (newBlank || looksLikeRecordId(row.newValue));
  }

  @TestVisible
  private static Boolean looksLikeRecordId(Object value) {
    if (value instanceof Id) {
      return true;
    }
    if (!(value instanceof String)) {
      return false;
    }
    String text = (String) value;
    if (
      (text.length() != 15 && text.length() != 18) || !text.isAlphanumeric()
    ) {
      return false;
    }
    try {
      return Id.valueOf(text).getSObjectType() != null;
    } catch (Exception notAnId) {
      return false;
    }
  }

  private static Id recordIdOf(Id knownId, Object rawValue) {
    if (knownId != null) {
      return knownId;
    }
    return looksLikeRecordId(rawValue)
      ? Id.valueOf(String.valueOf(rawValue))
      : null;
  }

  @TestVisible
  private static String displayValue(Object value) {
    if (isBlank(value)) {
      return null;
    }
    if (value instanceof Boolean) {
      return (Boolean) value ? 'Yes' : 'No';
    }
    if (value instanceof Date) {
      return ((Date) value).format();
    }
    if (value instanceof Datetime) {
      return ((Datetime) value).format();
    }
    String text = String.valueOf(value);
    if (text.equalsIgnoreCase('true') || text.equalsIgnoreCase('false')) {
      return isTrue(text) ? 'Yes' : 'No';
    }
    if (ISO_DATE.matcher(text).matches()) {
      return Date.valueOf(text.left(10)).format();
    }
    return text;
  }

  @TestVisible
  private static Date toDate(Object value) {
    if (value instanceof Date) {
      return (Date) value;
    }
    if (value instanceof Datetime) {
      return ((Datetime) value).date();
    }
    if (value instanceof String && ISO_DATE.matcher((String) value).matches()) {
      return Date.valueOf(((String) value).left(10));
    }
    return null;
  }

  private static Boolean isTrue(Object value) {
    if (value instanceof Boolean) {
      return (Boolean) value;
    }
    return value != null && String.valueOf(value).equalsIgnoreCase('true');
  }

  private static Boolean isBlank(Object value) {
    return value == null || String.isBlank(String.valueOf(value));
  }
}
