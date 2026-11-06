/*
 * @ClassName    : PRM_PracticeLocationHistoryDeriverTest
 * @CreatedOn    : 24-SEP-2026
 * @CreatedBy    : IBX
 * @Description  : Unit tests for PRM_PracticeLocationHistoryDeriver — classification rules,
 *                 sentences, lookup-pair collapse, live/archive de-duplication, Case Manager
 *                 resolution, grouping and integration-user detection. No DML needed.
 */
@isTest
private class PRM_PracticeLocationHistoryDeriverTest {
  private static final Datetime CHANGED_AT = Datetime.newInstance(
    2026,
    9,
    18,
    10,
    0,
    0
  );

  private static Id fakeId(Schema.SObjectType type, Integer n) {
    return Id.valueOf(
      type.getDescribe().getKeyPrefix() + String.valueOf(n).leftPad(12, '0')
    );
  }

  private static PRM_PracticeLocationHistoryModel.RawHistoryRow row(
    String field,
    Object oldValue,
    Object newValue
  ) {
    PRM_PracticeLocationHistoryModel.RawHistoryRow raw = new PRM_PracticeLocationHistoryModel.RawHistoryRow();
    raw.historyId = 'H' + Crypto.getRandomInteger();
    raw.parentId = fakeId(HealthcarePractitionerFacility.SObjectType, 1);
    raw.field = field;
    raw.oldValue = oldValue;
    raw.newValue = newValue;
    raw.createdDate = CHANGED_AT;
    raw.createdById = UserInfo.getUserId();
    return raw;
  }

  private static PRM_PracticeLocationHistoryModel.ChildRecord practitionerChild() {
    PRM_PracticeLocationHistoryModel.CategoryConfig config = new PRM_PracticeLocationHistoryModel.CategoryConfig();
    config.category = 'Practitioners';
    config.subjectLabel = 'Practitioner';
    config.parentFieldPath = 'HealthcareFacilityId';
    PRM_PracticeLocationHistoryModel.ChildRecord child = new PRM_PracticeLocationHistoryModel.ChildRecord();
    child.config = config;
    child.subject = 'Jane Doe';
    child.context = 'PCP';
    child.effectiveFrom = Date.newInstance(2026, 1, 1);
    return child;
  }

  private static PRM_PracticeLocationHistoryModel.ChildRecord practiceLocationChild() {
    PRM_PracticeLocationHistoryModel.CategoryConfig config = new PRM_PracticeLocationHistoryModel.CategoryConfig();
    config.category = 'Practice Location';
    config.subjectLabel = 'Practice location';
    config.parentFieldPath = 'Id';
    PRM_PracticeLocationHistoryModel.ChildRecord child = new PRM_PracticeLocationHistoryModel.ChildRecord();
    child.config = config;
    child.subject = 'Main Street Clinic';
    return child;
  }

  private static String classify(
    String field,
    Object oldValue,
    Object newValue
  ) {
    return new PRM_PracticeLocationHistoryDeriver()
      .classify(row(field, oldValue, newValue));
  }

  @isTest
  static void classifiesAddsRemovesAndReinstatesFromEndDate() {
    Date changedOn = CHANGED_AT.date();
    Test.startTest();
    String added = classify('created', null, null);
    String removedToday = classify('EffectiveTo', null, changedOn);
    String removedRetro = classify('EffectiveTo', null, changedOn.addDays(-5));
    String scheduled = classify('EffectiveTo', null, changedOn.addDays(10));
    String reinstatedCleared = classify(
      'EffectiveTo',
      changedOn.addDays(-1),
      null
    );
    String reinstatedExtended = classify(
      'PRM_EffectiveTo__c',
      changedOn.addDays(-1),
      changedOn.addDays(30)
    );
    String removedEarlier = classify(
      'EffectiveTo',
      changedOn.addDays(30),
      changedOn.addDays(-1)
    );
    String moved = classify(
      'EffectiveTo',
      changedOn.addDays(10),
      changedOn.addDays(20)
    );
    Test.stopTest();

    System.assertEquals(PRM_PracticeLocationHistoryDeriver.ADDED, added);
    System.assertEquals(
      PRM_PracticeLocationHistoryDeriver.REMOVED,
      removedToday
    );
    System.assertEquals(
      PRM_PracticeLocationHistoryDeriver.REMOVED,
      removedRetro
    );
    System.assertEquals(
      PRM_PracticeLocationHistoryDeriver.SCHEDULED_REMOVAL,
      scheduled
    );
    System.assertEquals(
      PRM_PracticeLocationHistoryDeriver.REINSTATED,
      reinstatedCleared
    );
    System.assertEquals(
      PRM_PracticeLocationHistoryDeriver.REINSTATED,
      reinstatedExtended
    );
    System.assertEquals(
      PRM_PracticeLocationHistoryDeriver.REMOVED,
      removedEarlier
    );
    System.assertEquals(
      PRM_PracticeLocationHistoryDeriver.END_DATE_CHANGED,
      moved
    );
  }

  @isTest
  static void classifiesFlagAndFieldChanges() {
    Test.startTest();
    Map<String, String> actual = new Map<String, String>{
      'deactivated' => classify('IsActive', true, false),
      'reactivated' => classify('PRM_Active__c', 'false', 'true'),
      'error' => classify('PRM_IsErrorRecord__c', 'false', 'true'),
      'errorCleared' => classify('PRM_IsErrorRecord__c', true, false),
      'pending' => classify('PRM_Pending__c', false, true),
      'pendingCleared' => classify('PRM_Pending__c', true, false),
      'primary' => classify('IsPrimaryFacility', false, true),
      'panel' => classify('PanelStatus', 'Open', 'Closed'),
      'start' => classify('EffectiveFrom', Date.today(), Date.today() + 1),
      'other' => classify('PRM_OfficeEmail__c', 'a@x.com', 'b@x.com')
    };
    Test.stopTest();

    System.assertEquals(
      PRM_PracticeLocationHistoryDeriver.DEACTIVATED,
      actual.get('deactivated')
    );
    System.assertEquals(
      PRM_PracticeLocationHistoryDeriver.REACTIVATED,
      actual.get('reactivated')
    );
    System.assertEquals(
      PRM_PracticeLocationHistoryDeriver.MARKED_AS_ERROR,
      actual.get('error')
    );
    System.assertEquals(
      PRM_PracticeLocationHistoryDeriver.ERROR_CLEARED,
      actual.get('errorCleared')
    );
    System.assertEquals(
      PRM_PracticeLocationHistoryDeriver.PENDING,
      actual.get('pending')
    );
    System.assertEquals(
      PRM_PracticeLocationHistoryDeriver.PENDING_CLEARED,
      actual.get('pendingCleared')
    );
    System.assertEquals(
      PRM_PracticeLocationHistoryDeriver.PRIMARY_CHANGED,
      actual.get('primary')
    );
    System.assertEquals(
      PRM_PracticeLocationHistoryDeriver.PANEL_STATUS_CHANGED,
      actual.get('panel')
    );
    System.assertEquals(
      PRM_PracticeLocationHistoryDeriver.START_DATE_CHANGED,
      actual.get('start')
    );
    System.assertEquals(
      PRM_PracticeLocationHistoryDeriver.UPDATED,
      actual.get('other')
    );
  }

  @isTest
  static void buildsBusinessSentences() {
    PRM_PracticeLocationHistoryDeriver deriver = new PRM_PracticeLocationHistoryDeriver();
    Date endDate = CHANGED_AT.date().addDays(-1);

    Test.startTest();
    PRM_PracticeLocationHistoryModel.HistoryEvent added = deriver.buildEvent(
      row('created', null, null),
      practitionerChild(),
      'Created'
    );
    PRM_PracticeLocationHistoryModel.HistoryEvent removed = deriver.buildEvent(
      row('EffectiveTo', null, endDate),
      practitionerChild(),
      'Effective To'
    );
    PRM_PracticeLocationHistoryModel.HistoryEvent created = deriver.buildEvent(
      row('created', null, null),
      practiceLocationChild(),
      null
    );
    PRM_PracticeLocationHistoryModel.HistoryEvent updated = deriver.buildEvent(
      row('PRM_OfficeEmail__c', 'a@x.com', 'b@x.com'),
      practiceLocationChild(),
      'Office Email'
    );
    Test.stopTest();

    System.assertEquals('Practitioner Jane Doe (PCP) added', added.sentence);
    System.assertEquals(Date.newInstance(2026, 1, 1), added.effectiveDate);
    System.assertEquals(true, added.isAddOrRemove);
    System.assertEquals(
      null,
      added.fieldLabel,
      'Created rows have no field label'
    );
    System.assertEquals(
      'Practitioner Jane Doe (PCP) removed, effective ' + endDate.format(),
      removed.sentence
    );
    System.assertEquals(endDate, removed.effectiveDate);
    System.assertEquals(
      Date.newInstance(2026, 1, 1),
      removed.recordEffectiveFrom,
      'Record effective-from is shown on every change, not only on adds'
    );
    System.assertEquals('Practice location created', created.sentence);
    System.assertEquals(
      'Practice location: Office Email changed',
      updated.sentence
    );
    System.assertEquals('a@x.com', updated.oldValue);
    System.assertEquals('b@x.com', updated.newValue);
    System.assertEquals(false, updated.isAddOrRemove);
  }

  @isTest
  static void formatsValuesFromLiveAndArchive() {
    Date d = Date.newInstance(2026, 9, 18);
    Datetime dt = Datetime.newInstance(2026, 9, 18, 8, 30, 0);
    Test.startTest();
    String liveBoolean = PRM_PracticeLocationHistoryDeriver.displayValue(true);
    String archivedBoolean = PRM_PracticeLocationHistoryDeriver.displayValue(
      'false'
    );
    String liveDate = PRM_PracticeLocationHistoryDeriver.displayValue(d);
    String archivedDate = PRM_PracticeLocationHistoryDeriver.displayValue(
      '2026-09-18'
    );
    String archivedMidnight = PRM_PracticeLocationHistoryDeriver.displayValue(
      '2026-09-18 00:00:00'
    );
    String liveDatetime = PRM_PracticeLocationHistoryDeriver.displayValue(dt);
    String text = PRM_PracticeLocationHistoryDeriver.displayValue('Specialist');
    String blank = PRM_PracticeLocationHistoryDeriver.displayValue('');
    Date fromDatetime = PRM_PracticeLocationHistoryDeriver.toDate(dt);
    Date fromText = PRM_PracticeLocationHistoryDeriver.toDate('not a date');
    Test.stopTest();

    System.assertEquals('Yes', liveBoolean);
    System.assertEquals('No', archivedBoolean);
    System.assertEquals(d.format(), liveDate);
    System.assertEquals(d.format(), archivedDate);
    System.assertEquals(d.format(), archivedMidnight);
    System.assertEquals(dt.format(), liveDatetime);
    System.assertEquals('Specialist', text);
    System.assertEquals(null, blank);
    System.assertEquals(d, fromDatetime);
    System.assertEquals(null, fromText);
  }

  @isTest
  static void mergeRowsKeepsLiveOverArchiveAndCollapsesLookupPairs() {
    Id newCaseManager = fakeId(IndividualApplication.SObjectType, 2);
    PRM_PracticeLocationHistoryModel.RawHistoryRow live = row(
      'PRM_Pending__c',
      true,
      false
    );
    PRM_PracticeLocationHistoryModel.RawHistoryRow archived = row(
      'PRM_Pending__c',
      'true',
      'false'
    );
    archived.historyId = live.historyId;
    archived.isArchived = true;

    PRM_PracticeLocationHistoryModel.RawHistoryRow idRow = row(
      'PRM_CaseManager__c',
      null,
      String.valueOf(newCaseManager)
    );
    PRM_PracticeLocationHistoryModel.RawHistoryRow nameRow = row(
      'PRM_CaseManager__c',
      null,
      'IA-0000000002'
    );

    Test.startTest();
    List<PRM_PracticeLocationHistoryModel.RawHistoryRow> merged = new PRM_PracticeLocationHistoryDeriver()
      .mergeRows(
        new List<PRM_PracticeLocationHistoryModel.RawHistoryRow>{
          archived,
          live,
          idRow,
          nameRow
        }
      );
    Test.stopTest();

    System.assertEquals(
      2,
      merged.size(),
      'One pending row + one collapsed lookup'
    );
    for (PRM_PracticeLocationHistoryModel.RawHistoryRow r : merged) {
      if (r.field == 'PRM_Pending__c') {
        System.assertEquals(false, r.isArchived, 'Live row wins over archive');
      } else {
        System.assertEquals('IA-0000000002', r.newValue, 'Name row kept');
        System.assertEquals(newCaseManager, r.newRecordId, 'Id carried over');
      }
    }
  }

  @isTest
  static void resolvesCaseManagerInEffectAtTimeOfChange() {
    Id cmA = fakeId(IndividualApplication.SObjectType, 10);
    Id cmB = fakeId(IndividualApplication.SObjectType, 11);
    Id current = fakeId(IndividualApplication.SObjectType, 12);
    PRM_PracticeLocationHistoryModel.RawHistoryRow change = row(
      'PRM_CaseManager__c',
      'IA-A',
      'IA-B'
    );
    change.oldRecordId = cmA;
    change.newRecordId = cmB;
    List<PRM_PracticeLocationHistoryModel.RawHistoryRow> changes = new List<PRM_PracticeLocationHistoryModel.RawHistoryRow>{
      change
    };
    PRM_PracticeLocationHistoryDeriver deriver = new PRM_PracticeLocationHistoryDeriver();

    Test.startTest();
    Id before = deriver.caseManagerAt(changes, CHANGED_AT.addDays(-3), current);
    Id sameSave = deriver.caseManagerAt(
      changes,
      CHANGED_AT.addSeconds(-5),
      current
    );
    Id after = deriver.caseManagerAt(changes, CHANGED_AT.addDays(3), current);
    Id neverChanged = deriver.caseManagerAt(null, CHANGED_AT, current);
    Test.stopTest();

    System.assertEquals(cmA, before, 'Earlier change sees the replaced value');
    System.assertEquals(
      cmB,
      sameSave,
      'A change in the same save sees the new value'
    );
    System.assertEquals(cmB, after);
    System.assertEquals(current, neverChanged);
  }

  @isTest
  static void groupsChangesBySameUserWithinWindow() {
    Id otherUser = fakeId(User.SObjectType, 99);
    List<PRM_PracticeLocationHistoryModel.HistoryEvent> events = new List<PRM_PracticeLocationHistoryModel.HistoryEvent>();
    List<Integer> secondsAgo = new List<Integer>{ 0, 5, 30, 40, 300 };
    for (Integer i = 0; i < secondsAgo.size(); i++) {
      PRM_PracticeLocationHistoryModel.HistoryEvent e = new PRM_PracticeLocationHistoryModel.HistoryEvent();
      e.id = 'E' + i;
      e.eventDate = CHANGED_AT.addSeconds(-secondsAgo[i]);
      e.actorId = i == 3 ? otherUser : UserInfo.getUserId();
      events.add(e);
    }

    Test.startTest();
    new PRM_PracticeLocationHistoryDeriver().assignGroups(events);
    Test.stopTest();

    System.assertEquals('E0', events[0].groupKey);
    System.assertEquals('E0', events[1].groupKey);
    System.assertEquals('E0', events[2].groupKey);
    System.assertEquals(
      'E3',
      events[3].groupKey,
      'Different user starts a new group'
    );
    System.assertEquals(
      'E4',
      events[4].groupKey,
      'Outside the window starts a new group'
    );
  }

  @isTest
  static void detectsIntegrationUsers() {
    Set<String> configured = new Set<String>{ 'mulesoft integration user' };
    User mule = (User) JSON.deserialize(
      '{"Name":"MuleSoft Integration User","UserType":"Standard"}',
      User.class
    );
    User platform = (User) JSON.deserialize(
      '{"Name":"Platform Integration User","UserType":"CloudIntegrationUser"}',
      User.class
    );
    User person = (User) JSON.deserialize(
      '{"Name":"Pat Specialist","UserType":"Standard"}',
      User.class
    );
    PRM_PracticeLocationHistoryDeriver deriver = new PRM_PracticeLocationHistoryDeriver();

    Test.startTest();
    Boolean muleFlag = deriver.isIntegrationUser(mule, configured);
    Boolean platformFlag = deriver.isIntegrationUser(platform, configured);
    Boolean personFlag = deriver.isIntegrationUser(person, configured);
    Boolean unknownFlag = deriver.isIntegrationUser(null, configured);
    Test.stopTest();

    System.assertEquals(true, muleFlag, 'Configured by name');
    System.assertEquals(true, platformFlag, 'Integration by user type');
    System.assertEquals(false, personFlag);
    System.assertEquals(false, unknownFlag);
  }

  @isTest
  static void recognisesRecordIds() {
    Test.startTest();
    Boolean realId = PRM_PracticeLocationHistoryDeriver.looksLikeRecordId(
      String.valueOf(UserInfo.getUserId())
    );
    Boolean typedId = PRM_PracticeLocationHistoryDeriver.looksLikeRecordId(
      UserInfo.getUserId()
    );
    Boolean shortText = PRM_PracticeLocationHistoryDeriver.looksLikeRecordId(
      'PCP'
    );
    Boolean notText = PRM_PracticeLocationHistoryDeriver.looksLikeRecordId(42);
    Test.stopTest();

    System.assertEquals(true, realId);
    System.assertEquals(true, typedId);
    System.assertEquals(false, shortText);
    System.assertEquals(false, notText);
  }
}
