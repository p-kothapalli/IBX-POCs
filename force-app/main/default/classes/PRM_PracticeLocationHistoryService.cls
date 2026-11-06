/*
 * @ClassName    : PRM_PracticeLocationHistoryService
 * @TestClassName: PRM_PracticeLocationHistoryServiceTest
 * @CreatedOn    : 24-SEP-2026
 * @CreatedBy    : IBX
 * @Description  : Builds the change-history feed for one Practice Location
 *                 (HealthcareFacility). For every active PRM_PracticeLocationHistoryConfig__mdt
 *                 category it resolves the related records, reads their field history
 *                 (live table or FieldHistoryArchive), and turns it into business events via
 *                 PRM_PracticeLocationHistoryDeriver. One history query per object, not per
 *                 category, so HealthcareFacilityNetwork's record-type categories share a read.
 */
public with sharing class PRM_PracticeLocationHistoryService {
  @TestVisible
  private static final Integer DEFAULT_MAX_RECORDS = 2000;
  @TestVisible
  private static final Integer HISTORY_ROWS_PER_OBJECT = 5000;

  private final PRM_PracticeLocationHistorySelector selector;
  private final PRM_PracticeLocationHistoryDeriver deriver;

  public PRM_PracticeLocationHistoryService(
    PRM_PracticeLocationHistorySelector selector,
    PRM_PracticeLocationHistoryDeriver deriver
  ) {
    this.selector = selector;
    this.deriver = deriver;
  }

  public PRM_PracticeLocationHistoryModel.HistoryResponse getHistory(
    Id practiceLocationId,
    Boolean fromArchive
  ) {
    PRM_PracticeLocationHistoryModel.HistoryResponse response = new PRM_PracticeLocationHistoryModel.HistoryResponse();
    response.includesArchive = fromArchive;
    response.practiceLocationName = selector.selectPracticeLocationName(
      practiceLocationId
    );
    if (response.practiceLocationName == null) {
      return response;
    }

    Map<String, Map<Id, PRM_PracticeLocationHistoryModel.ChildRecord>> childrenByObject = loadChildren(
      practiceLocationId,
      response
    );
    List<PRM_PracticeLocationHistoryModel.HistoryEvent> events = new List<PRM_PracticeLocationHistoryModel.HistoryEvent>();
    for (String objectApiName : childrenByObject.keySet()) {
      events.addAll(
        loadEvents(
          objectApiName,
          childrenByObject.get(objectApiName),
          fromArchive,
          response
        )
      );
    }
    decorateActorsAndCaseManagers(events);
    events.sort();
    deriver.assignGroups(events);
    response.events = events;
    return response;
  }

  private Map<String, Map<Id, PRM_PracticeLocationHistoryModel.ChildRecord>> loadChildren(
    Id practiceLocationId,
    PRM_PracticeLocationHistoryModel.HistoryResponse response
  ) {
    Map<String, Map<Id, PRM_PracticeLocationHistoryModel.ChildRecord>> childrenByObject = new Map<String, Map<Id, PRM_PracticeLocationHistoryModel.ChildRecord>>();
    for (
      PRM_PracticeLocationHistoryModel.CategoryConfig config : selector.selectActiveCategories()
    ) {
      addOnce(response.categories, config.category);
      if (!selector.objectExists(config.objectApiName)) {
        continue;
      }
      Integer maxRecords = config.maxRecords == null
        ? DEFAULT_MAX_RECORDS
        : config.maxRecords;
      Map<String, Schema.SObjectField> fields = selector.describeFields(
        config.objectApiName
      );
      List<SObject> records = selector.selectChildRecords(
        config,
        practiceLocationId,
        childFieldPaths(config, fields),
        maxRecords + 1
      );
      if (records.size() > maxRecords) {
        addOnce(response.truncatedCategories, config.category);
      }
      if (!childrenByObject.containsKey(config.objectApiName)) {
        childrenByObject.put(
          config.objectApiName,
          new Map<Id, PRM_PracticeLocationHistoryModel.ChildRecord>()
        );
      }
      Map<Id, PRM_PracticeLocationHistoryModel.ChildRecord> bucket = childrenByObject.get(
        config.objectApiName
      );
      Integer usable = Math.min(records.size(), maxRecords);
      for (Integer i = 0; i < usable; i++) {
        if (!bucket.containsKey(records[i].Id)) {
          bucket.put(records[i].Id, toChildRecord(records[i], config, fields));
        }
      }
    }
    return childrenByObject;
  }

  private List<PRM_PracticeLocationHistoryModel.HistoryEvent> loadEvents(
    String objectApiName,
    Map<Id, PRM_PracticeLocationHistoryModel.ChildRecord> children,
    Boolean fromArchive,
    PRM_PracticeLocationHistoryModel.HistoryResponse response
  ) {
    List<PRM_PracticeLocationHistoryModel.HistoryEvent> events = new List<PRM_PracticeLocationHistoryModel.HistoryEvent>();
    if (children.isEmpty()) {
      return events;
    }
    List<PRM_PracticeLocationHistoryModel.RawHistoryRow> rawRows = fromArchive
      ? selector.selectArchivedHistory(
          objectApiName,
          children.keySet(),
          HISTORY_ROWS_PER_OBJECT
        )
      : selector.selectLiveHistory(
          objectApiName,
          children.keySet(),
          HISTORY_ROWS_PER_OBJECT
        );
    if (rawRows.size() >= HISTORY_ROWS_PER_OBJECT) {
      for (
        PRM_PracticeLocationHistoryModel.ChildRecord child : children.values()
      ) {
        addOnce(response.truncatedCategories, child.config.category);
      }
    }
    List<PRM_PracticeLocationHistoryModel.RawHistoryRow> rows = deriver.mergeRows(
      rawRows
    );
    Map<String, Schema.SObjectField> fields = selector.describeFields(
      objectApiName
    );
    Map<Id, List<PRM_PracticeLocationHistoryModel.RawHistoryRow>> caseManagerChanges = caseManagerChangesByRecord(
      rows
    );
    for (PRM_PracticeLocationHistoryModel.RawHistoryRow row : rows) {
      PRM_PracticeLocationHistoryModel.ChildRecord child = children.get(
        row.parentId
      );
      if (child == null) {
        continue;
      }
      PRM_PracticeLocationHistoryModel.HistoryEvent event = deriver.buildEvent(
        row,
        child,
        fieldLabel(fields, row.field)
      );
      event.caseManagerId = deriver.caseManagerAt(
        caseManagerChanges.get(row.parentId),
        row.createdDate,
        child.currentCaseManagerId
      );
      events.add(event);
    }
    return events;
  }

  private void decorateActorsAndCaseManagers(
    List<PRM_PracticeLocationHistoryModel.HistoryEvent> events
  ) {
    Set<Id> actorIds = new Set<Id>();
    Set<Id> caseManagerIds = new Set<Id>();
    for (PRM_PracticeLocationHistoryModel.HistoryEvent event : events) {
      if (event.actorId != null) {
        actorIds.add(event.actorId);
      }
      if (event.caseManagerId != null) {
        caseManagerIds.add(event.caseManagerId);
      }
    }
    Map<Id, User> actors = selector.selectUsers(actorIds);
    Set<String> integrationUserNames = selector.selectIntegrationUserNames();
    Map<Id, IndividualApplication> caseManagers = selector.selectCaseManagers(
      caseManagerIds
    );
    for (PRM_PracticeLocationHistoryModel.HistoryEvent event : events) {
      User actor = actors.get(event.actorId);
      event.actorName = actor == null ? null : actor.Name;
      event.isIntegration = deriver.isIntegrationUser(
        actor,
        integrationUserNames
      );
      IndividualApplication caseManager = caseManagers.get(event.caseManagerId);
      if (caseManager != null) {
        Map<String, Object> values = caseManager.getPopulatedFieldsAsMap();
        event.caseManagerName = (String) values.get('Name');
        event.fhnaticCaseNumber = (String) values.get(
          PRM_PracticeLocationHistorySelector.FHNATIC_CASE_NUMBER_FIELD
        );
      }
    }
  }

  private static Map<Id, List<PRM_PracticeLocationHistoryModel.RawHistoryRow>> caseManagerChangesByRecord(
    List<PRM_PracticeLocationHistoryModel.RawHistoryRow> rows
  ) {
    Map<Id, List<PRM_PracticeLocationHistoryModel.RawHistoryRow>> byRecord = new Map<Id, List<PRM_PracticeLocationHistoryModel.RawHistoryRow>>();
    for (PRM_PracticeLocationHistoryModel.RawHistoryRow row : rows) {
      if (row.field != PRM_PracticeLocationHistorySelector.CASE_MANAGER_FIELD) {
        continue;
      }
      if (!byRecord.containsKey(row.parentId)) {
        byRecord.put(
          row.parentId,
          new List<PRM_PracticeLocationHistoryModel.RawHistoryRow>()
        );
      }
      byRecord.get(row.parentId).add(row);
    }
    for (
      List<PRM_PracticeLocationHistoryModel.RawHistoryRow> changes : byRecord.values()
    ) {
      changes.sort();
    }
    return byRecord;
  }

  private static Set<String> childFieldPaths(
    PRM_PracticeLocationHistoryModel.CategoryConfig config,
    Map<String, Schema.SObjectField> fields
  ) {
    Set<String> paths = new Set<String>{ 'Id', config.subjectFieldPath };
    if (String.isNotBlank(config.contextFieldPath)) {
      paths.add(config.contextFieldPath);
    }
    String effectiveFromField = effectiveFromField(fields);
    if (effectiveFromField != null) {
      paths.add(effectiveFromField);
    }
    if (
      fields.containsKey(
        PRM_PracticeLocationHistorySelector.CASE_MANAGER_FIELD.toLowerCase()
      )
    ) {
      paths.add(PRM_PracticeLocationHistorySelector.CASE_MANAGER_FIELD);
    }
    return paths;
  }

  private static PRM_PracticeLocationHistoryModel.ChildRecord toChildRecord(
    SObject record,
    PRM_PracticeLocationHistoryModel.CategoryConfig config,
    Map<String, Schema.SObjectField> fields
  ) {
    PRM_PracticeLocationHistoryModel.ChildRecord child = new PRM_PracticeLocationHistoryModel.ChildRecord();
    child.recordId = record.Id;
    child.config = config;
    child.subject = readPath(record, config.subjectFieldPath);
    child.context = String.isBlank(config.contextFieldPath)
      ? null
      : readPath(record, config.contextFieldPath);
    String effectiveFromField = effectiveFromField(fields);
    if (effectiveFromField != null) {
      // Date must be tested first: in Apex a Date is also `instanceof Datetime`, and
      // Datetime.date() would shift it a day in time zones west of GMT.
      Object effectiveFrom = record.get(effectiveFromField);
      if (effectiveFrom instanceof Date) {
        child.effectiveFrom = (Date) effectiveFrom;
      } else if (effectiveFrom instanceof Datetime) {
        child.effectiveFrom = ((Datetime) effectiveFrom).date();
      }
    }
    if (
      fields.containsKey(
        PRM_PracticeLocationHistorySelector.CASE_MANAGER_FIELD.toLowerCase()
      )
    ) {
      child.currentCaseManagerId = (Id) record.get(
        PRM_PracticeLocationHistorySelector.CASE_MANAGER_FIELD
      );
    }
    return child;
  }

  @TestVisible
  private static String readPath(SObject record, String path) {
    List<String> parts = path.split('\\.');
    SObject current = record;
    for (Integer i = 0; i < parts.size() - 1; i++) {
      current = current.getSObject(parts[i]);
      if (current == null) {
        return null;
      }
    }
    Object value = current.get(parts[parts.size() - 1]);
    return value == null ? null : String.valueOf(value);
  }

  private static String effectiveFromField(
    Map<String, Schema.SObjectField> fields
  ) {
    if (fields.containsKey('effectivefrom')) {
      return 'EffectiveFrom';
    }
    if (fields.containsKey('prm_effectivefrom__c')) {
      return 'PRM_EffectiveFrom__c';
    }
    return null;
  }

  /*
   * History rows name standard lookups by relationship ("Practitioner"), custom fields
   * by API name, so fall back to "<name>Id" before giving up on a label.
   */
  private static String fieldLabel(
    Map<String, Schema.SObjectField> fields,
    String historyFieldName
  ) {
    if (String.isBlank(historyFieldName)) {
      return historyFieldName;
    }
    Schema.SObjectField token = fields.get(historyFieldName.toLowerCase());
    if (token == null) {
      token = fields.get((historyFieldName + 'Id').toLowerCase());
    }
    return token == null ? historyFieldName : token.getDescribe().getLabel();
  }

  private static void addOnce(List<String> values, String value) {
    if (String.isNotBlank(value) && !values.contains(value)) {
      values.add(value);
    }
  }
}
