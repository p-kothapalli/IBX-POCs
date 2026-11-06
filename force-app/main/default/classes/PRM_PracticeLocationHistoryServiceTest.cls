/*
 * @ClassName    : PRM_PracticeLocationHistoryServiceTest
 * @CreatedOn    : 24-SEP-2026
 * @CreatedBy    : IBX
 * @Description  : Tests PRM_PracticeLocationHistoryService and PRM_PracticeLocationHistoryController
 *                 end to end through a stub selector. A stub is required: the platform writes no
 *                 field history or FieldHistoryArchive rows in test context.
 */
@isTest
private class PRM_PracticeLocationHistoryServiceTest {
  private static final Datetime T0 = Datetime.newInstance(2026, 9, 1, 9, 0, 0);
  private static final Datetime T1 = Datetime.newInstance(
    2026,
    9,
    18,
    14,
    0,
    0
  );

  private static Id fakeId(Schema.SObjectType type, Integer n) {
    return Id.valueOf(
      type.getDescribe().getKeyPrefix() + String.valueOf(n).leftPad(12, '0')
    );
  }

  private static final Id PRACTICE_LOCATION_ID = fakeId(
    HealthcareFacility.SObjectType,
    1
  );
  private static final Id MULE_USER_ID = fakeId(User.SObjectType, 1);
  private static final Id SPECIALIST_ID = fakeId(User.SObjectType, 2);
  private static final Id CASE_MANAGER_A = fakeId(
    IndividualApplication.SObjectType,
    1
  );
  private static final Id CASE_MANAGER_B = fakeId(
    IndividualApplication.SObjectType,
    2
  );

  private class StubSelector extends PRM_PracticeLocationHistorySelector {
    List<PRM_PracticeLocationHistoryModel.CategoryConfig> configs = new List<PRM_PracticeLocationHistoryModel.CategoryConfig>();
    Map<String, List<SObject>> childrenByCategory = new Map<String, List<SObject>>();
    Map<String, List<PRM_PracticeLocationHistoryModel.RawHistoryRow>> liveByObject = new Map<String, List<PRM_PracticeLocationHistoryModel.RawHistoryRow>>();
    Map<String, List<PRM_PracticeLocationHistoryModel.RawHistoryRow>> archiveByObject = new Map<String, List<PRM_PracticeLocationHistoryModel.RawHistoryRow>>();
    String practiceLocationName = 'Main Street Clinic';
    Boolean failOnCategories = false;

    public override List<PRM_PracticeLocationHistoryModel.CategoryConfig> selectActiveCategories() {
      if (failOnCategories) {
        throw new IllegalArgumentException('Config unavailable');
      }
      return configs;
    }
    public override Set<String> selectIntegrationUserNames() {
      return new Set<String>{ 'mulesoft integration user' };
    }
    public override String selectPracticeLocationName(Id practiceLocationId) {
      return practiceLocationName;
    }
    public override List<SObject> selectChildRecords(
      PRM_PracticeLocationHistoryModel.CategoryConfig config,
      Id practiceLocationId,
      Set<String> fieldPaths,
      Integer rowLimit
    ) {
      List<SObject> rows = childrenByCategory.get(config.developerName);
      return rows == null ? new List<SObject>() : rows;
    }
    public override List<PRM_PracticeLocationHistoryModel.RawHistoryRow> selectLiveHistory(
      String objectApiName,
      Set<Id> parentIds,
      Integer rowLimit
    ) {
      return rowsFor(liveByObject, objectApiName);
    }
    public override List<PRM_PracticeLocationHistoryModel.RawHistoryRow> selectArchivedHistory(
      String objectApiName,
      Set<Id> parentIds,
      Integer rowLimit
    ) {
      return rowsFor(archiveByObject, objectApiName);
    }
    public override Map<Id, User> selectUsers(Set<Id> userIds) {
      return new Map<Id, User>{
        MULE_USER_ID => user(MULE_USER_ID, 'MuleSoft Integration User'),
        SPECIALIST_ID => user(SPECIALIST_ID, 'Pat Specialist')
      };
    }
    public override Map<Id, IndividualApplication> selectCaseManagers(
      Set<Id> caseManagerIds
    ) {
      Map<Id, IndividualApplication> caseManagers = new Map<Id, IndividualApplication>();
      for (Id cmId : caseManagerIds) {
        String suffix = cmId == CASE_MANAGER_A ? 'A' : 'B';
        caseManagers.put(
          cmId,
          (IndividualApplication) JSON.deserialize(
            '{"Id":"' +
              cmId +
              '","Name":"IA-' +
              suffix +
              '","PRM_FHNaticCaseNumber__c":"FHN-' +
              suffix +
              '"}',
            IndividualApplication.class
          )
        );
      }
      return caseManagers;
    }

    private List<PRM_PracticeLocationHistoryModel.RawHistoryRow> rowsFor(
      Map<String, List<PRM_PracticeLocationHistoryModel.RawHistoryRow>> source,
      String objectApiName
    ) {
      List<PRM_PracticeLocationHistoryModel.RawHistoryRow> rows = source.get(
        objectApiName
      );
      return rows == null
        ? new List<PRM_PracticeLocationHistoryModel.RawHistoryRow>()
        : rows;
    }
  }

  private static User user(Id userId, String name) {
    return (User) JSON.deserialize(
      '{"Id":"' + userId + '","Name":"' + name + '","UserType":"Standard"}',
      User.class
    );
  }

  private static PRM_PracticeLocationHistoryModel.CategoryConfig config(
    String developerName,
    String category,
    String subjectLabel,
    String objectApiName,
    String subjectPath,
    String contextPath
  ) {
    PRM_PracticeLocationHistoryModel.CategoryConfig c = new PRM_PracticeLocationHistoryModel.CategoryConfig();
    c.developerName = developerName;
    c.category = category;
    c.subjectLabel = subjectLabel;
    c.objectApiName = objectApiName;
    c.parentFieldPath = 'HealthcareFacilityId';
    c.subjectFieldPath = subjectPath;
    c.contextFieldPath = contextPath;
    return c;
  }

  private static SObject practitionerLink(
    Id recordId,
    String practitionerName
  ) {
    return (SObject) JSON.deserialize(
      '{"attributes":{"type":"HealthcarePractitionerFacility"},"Id":"' +
        recordId +
        '","PRM_PractitionerRole__c":"PCP","EffectiveFrom":"2026-09-01",' +
        '"Practitioner":{"attributes":{"type":"Contact"},"Name":"' +
        practitionerName +
        '"}}',
      HealthcarePractitionerFacility.class
    );
  }

  private static SObject locationNetwork(Id recordId) {
    return (SObject) JSON.deserialize(
      '{"attributes":{"type":"HealthcareFacilityNetwork"},"Id":"' +
        recordId +
        '","PRM_CaseManager__c":"' +
        CASE_MANAGER_B +
        '","PayerNetwork":{"attributes":{"type":"HealthcarePayerNetwork"},"Name":"Amerihealth PPO"}}',
      HealthcareFacilityNetwork.class
    );
  }

  private static PRM_PracticeLocationHistoryModel.RawHistoryRow raw(
    Id parentId,
    String field,
    Object oldValue,
    Object newValue,
    Datetime changedAt,
    Id actorId
  ) {
    PRM_PracticeLocationHistoryModel.RawHistoryRow r = new PRM_PracticeLocationHistoryModel.RawHistoryRow();
    r.historyId =
      'H-' +
      parentId +
      '-' +
      field +
      '-' +
      changedAt.getTime() +
      '-' +
      newValue;
    r.parentId = parentId;
    r.field = field;
    r.oldValue = oldValue;
    r.newValue = newValue;
    r.createdDate = changedAt;
    r.createdById = actorId;
    return r;
  }

  /*
   * One practitioner added by MuleSoft at T0, then removed by a specialist at T1 while the
   * Case Manager was switched A -> B in the same save; a location network scheduled for
   * removal in that same save.
   */
  private static StubSelector scenario() {
    Id hpfId = fakeId(HealthcarePractitionerFacility.SObjectType, 1);
    Id hfnId = fakeId(HealthcareFacilityNetwork.SObjectType, 1);
    StubSelector stub = new StubSelector();
    stub.configs.add(
      config(
        'Practitioner',
        'Practitioners',
        'Practitioner',
        'HealthcarePractitionerFacility',
        'Practitioner.Name',
        'PRM_PractitionerRole__c'
      )
    );
    stub.configs.add(
      config(
        'LocationNetwork',
        'Networks',
        'Network',
        'HealthcareFacilityNetwork',
        'PayerNetwork.Name',
        null
      )
    );
    stub.childrenByCategory.put(
      'Practitioner',
      new List<SObject>{ practitionerLink(hpfId, 'Jane Doe') }
    );
    stub.childrenByCategory.put(
      'LocationNetwork',
      new List<SObject>{ locationNetwork(hfnId) }
    );
    stub.liveByObject.put(
      'HealthcarePractitionerFacility',
      new List<PRM_PracticeLocationHistoryModel.RawHistoryRow>{
        raw(hpfId, 'created', null, null, T0, MULE_USER_ID),
        raw(hpfId, 'EffectiveTo', null, T1.date(), T1, SPECIALIST_ID),
        raw(
          hpfId,
          'PRM_CaseManager__c',
          String.valueOf(CASE_MANAGER_A),
          String.valueOf(CASE_MANAGER_B),
          T1,
          SPECIALIST_ID
        ),
        raw(hpfId, 'PRM_CaseManager__c', 'IA-A', 'IA-B', T1, SPECIALIST_ID)
      }
    );
    stub.liveByObject.put(
      'HealthcareFacilityNetwork',
      new List<PRM_PracticeLocationHistoryModel.RawHistoryRow>{
        raw(
          hfnId,
          'EffectiveTo',
          null,
          T1.date().addDays(30),
          T1,
          SPECIALIST_ID
        )
      }
    );
    return stub;
  }

  private static PRM_PracticeLocationHistoryModel.HistoryEvent findByType(
    List<PRM_PracticeLocationHistoryModel.HistoryEvent> events,
    String eventType
  ) {
    for (PRM_PracticeLocationHistoryModel.HistoryEvent e : events) {
      if (e.eventType == eventType) {
        return e;
      }
    }
    return null;
  }

  @isTest
  static void buildsBusinessEventsForPractitionersAndNetworks() {
    PRM_PracticeLocationHistoryController.selectorOverride = scenario();

    Test.startTest();
    PRM_PracticeLocationHistoryModel.HistoryResponse response = PRM_PracticeLocationHistoryController.getHistory(
      PRACTICE_LOCATION_ID
    );
    Test.stopTest();

    System.assertEquals('Main Street Clinic', response.practiceLocationName);
    System.assertEquals(false, response.includesArchive);
    System.assertEquals(
      new List<String>{ 'Practitioners', 'Networks' },
      response.categories
    );
    System.assertEquals(
      4,
      response.events.size(),
      'Lookup pair collapses to one event'
    );
    System.assert(
      response.events[0].eventDate >= response.events[3].eventDate,
      'Newest first'
    );

    PRM_PracticeLocationHistoryModel.HistoryEvent added = findByType(
      response.events,
      PRM_PracticeLocationHistoryDeriver.ADDED
    );
    System.assertEquals('Practitioner Jane Doe (PCP) added', added.sentence);
    System.assertEquals(true, added.isIntegration, 'MuleSoft is badged');
    System.assertEquals('MuleSoft Integration User', added.actorName);
    System.assertEquals(
      CASE_MANAGER_A,
      added.caseManagerId,
      'Before the switch the link was under Case Manager A'
    );
    System.assertEquals('IA-A', added.caseManagerName);
    System.assertEquals(
      'FHN-A',
      added.fhnaticCaseNumber,
      'FHNatic case number comes from the Case Manager'
    );
    System.assertEquals(
      Date.newInstance(2026, 9, 1),
      added.recordEffectiveFrom,
      'Record effective-from date is carried on every event'
    );

    PRM_PracticeLocationHistoryModel.HistoryEvent removed = findByType(
      response.events,
      PRM_PracticeLocationHistoryDeriver.REMOVED
    );
    System.assert(
      removed.sentence.startsWith(
        'Practitioner Jane Doe (PCP) removed, effective'
      ),
      removed.sentence
    );
    System.assertEquals(false, removed.isIntegration);
    System.assertEquals(CASE_MANAGER_B, removed.caseManagerId);
    System.assertEquals('FHN-B', removed.fhnaticCaseNumber);
    System.assertEquals(
      Date.newInstance(2026, 9, 1),
      removed.recordEffectiveFrom
    );

    PRM_PracticeLocationHistoryModel.HistoryEvent scheduled = findByType(
      response.events,
      PRM_PracticeLocationHistoryDeriver.SCHEDULED_REMOVAL
    );
    System.assertEquals('Networks', scheduled.category);
    System.assert(
      scheduled.sentence.startsWith(
        'Network Amerihealth PPO scheduled for removal'
      ),
      scheduled.sentence
    );
    System.assertEquals(
      removed.groupKey,
      scheduled.groupKey,
      'Same user, same Case Manager, same save = one change event'
    );
    System.assertNotEquals(added.groupKey, removed.groupKey);

    PRM_PracticeLocationHistoryModel.HistoryEvent caseManagerChange = findByType(
      response.events,
      PRM_PracticeLocationHistoryDeriver.UPDATED
    );
    System.assertEquals(
      'IA-A',
      caseManagerChange.oldValue,
      'Name row shown, not Id'
    );
    System.assertEquals('IA-B', caseManagerChange.newValue);
  }

  @isTest
  static void readsArchiveOnDemand() {
    StubSelector stub = scenario();
    stub.archiveByObject = stub.liveByObject;
    stub.liveByObject = new Map<String, List<PRM_PracticeLocationHistoryModel.RawHistoryRow>>();
    for (
      List<PRM_PracticeLocationHistoryModel.RawHistoryRow> rows : stub.archiveByObject.values()
    ) {
      for (PRM_PracticeLocationHistoryModel.RawHistoryRow r : rows) {
        r.isArchived = true;
      }
    }
    PRM_PracticeLocationHistoryController.selectorOverride = stub;

    Test.startTest();
    PRM_PracticeLocationHistoryModel.HistoryResponse archived = PRM_PracticeLocationHistoryController.getArchivedHistory(
      PRACTICE_LOCATION_ID
    );
    PRM_PracticeLocationHistoryModel.HistoryResponse live = PRM_PracticeLocationHistoryController.getHistory(
      PRACTICE_LOCATION_ID
    );
    Test.stopTest();

    System.assertEquals(true, archived.includesArchive);
    System.assertEquals(4, archived.events.size());
    System.assertEquals(true, archived.events[0].isArchived);
    System.assertEquals(
      0,
      live.events.size(),
      'Live read does not touch the archive'
    );
  }

  @isTest
  static void flagsCategoriesThatHitTheirCap() {
    StubSelector stub = scenario();
    stub.configs[0].maxRecords = 1;
    stub.childrenByCategory.get('Practitioner')
      .add(
        practitionerLink(
          fakeId(HealthcarePractitionerFacility.SObjectType, 2),
          'John Roe'
        )
      );
    PRM_PracticeLocationHistoryController.selectorOverride = stub;

    Test.startTest();
    PRM_PracticeLocationHistoryModel.HistoryResponse response = PRM_PracticeLocationHistoryController.getHistory(
      PRACTICE_LOCATION_ID
    );
    Test.stopTest();

    System.assertEquals(
      new List<String>{ 'Practitioners' },
      response.truncatedCategories
    );
  }

  @isTest
  static void handlesBulkPractitionerAdds() {
    StubSelector stub = scenario();
    List<SObject> links = new List<SObject>();
    List<PRM_PracticeLocationHistoryModel.RawHistoryRow> rows = new List<PRM_PracticeLocationHistoryModel.RawHistoryRow>();
    for (Integer i = 1; i <= 200; i++) {
      Id hpfId = fakeId(HealthcarePractitionerFacility.SObjectType, 1000 + i);
      links.add(practitionerLink(hpfId, 'Practitioner ' + i));
      rows.add(raw(hpfId, 'created', null, null, T0, MULE_USER_ID));
    }
    stub.childrenByCategory.put('Practitioner', links);
    stub.liveByObject.put('HealthcarePractitionerFacility', rows);
    stub.liveByObject.remove('HealthcareFacilityNetwork');
    PRM_PracticeLocationHistoryController.selectorOverride = stub;

    Test.startTest();
    PRM_PracticeLocationHistoryModel.HistoryResponse response = PRM_PracticeLocationHistoryController.getHistory(
      PRACTICE_LOCATION_ID
    );
    Test.stopTest();

    System.assertEquals(200, response.events.size());
    Set<String> groupKeys = new Set<String>();
    for (PRM_PracticeLocationHistoryModel.HistoryEvent e : response.events) {
      groupKeys.add(e.groupKey);
    }
    System.assertEquals(
      1,
      groupKeys.size(),
      'One integration load = one change event'
    );
    System.assert(Limits.getQueries() < 20, 'No per-record queries');
  }

  @isTest
  static void returnsEmptyWhenLocationNotVisible() {
    StubSelector stub = scenario();
    stub.practiceLocationName = null;
    PRM_PracticeLocationHistoryController.selectorOverride = stub;

    Test.startTest();
    PRM_PracticeLocationHistoryModel.HistoryResponse response = PRM_PracticeLocationHistoryController.getHistory(
      PRACTICE_LOCATION_ID
    );
    Test.stopTest();

    System.assertEquals(null, response.practiceLocationName);
    System.assertEquals(0, response.events.size());
  }

  @isTest
  static void ignoresNullAndNonPracticeLocationIds() {
    PRM_PracticeLocationHistoryController.selectorOverride = scenario();

    Test.startTest();
    PRM_PracticeLocationHistoryModel.HistoryResponse nullId = PRM_PracticeLocationHistoryController.getHistory(
      null
    );
    PRM_PracticeLocationHistoryModel.HistoryResponse accountId = PRM_PracticeLocationHistoryController.getHistory(
      fakeId(Account.SObjectType, 1)
    );
    Test.stopTest();

    System.assertEquals(0, nullId.events.size());
    System.assertEquals(null, accountId.practiceLocationName);
  }

  @isTest
  static void surfacesFailuresToTheLwc() {
    StubSelector stub = scenario();
    stub.failOnCategories = true;
    PRM_PracticeLocationHistoryController.selectorOverride = stub;
    Boolean threw = false;

    Test.startTest();
    try {
      PRM_PracticeLocationHistoryController.getHistory(PRACTICE_LOCATION_ID);
    } catch (AuraHandledException ex) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw);
  }

  @isTest
  static void sortsRowsEventsAndConfigsWithMissingValues() {
    PRM_PracticeLocationHistoryModel.RawHistoryRow later = raw(
      fakeId(HealthcarePractitionerFacility.SObjectType, 1),
      'IsActive',
      true,
      false,
      T1,
      SPECIALIST_ID
    );
    PRM_PracticeLocationHistoryModel.RawHistoryRow earlier = raw(
      fakeId(HealthcarePractitionerFacility.SObjectType, 1),
      'IsActive',
      false,
      true,
      T0,
      SPECIALIST_ID
    );
    PRM_PracticeLocationHistoryModel.RawHistoryRow undated = new PRM_PracticeLocationHistoryModel.RawHistoryRow();
    List<PRM_PracticeLocationHistoryModel.RawHistoryRow> rows = new List<PRM_PracticeLocationHistoryModel.RawHistoryRow>{
      later,
      undated,
      earlier
    };

    List<PRM_PracticeLocationHistoryModel.HistoryEvent> events = new List<PRM_PracticeLocationHistoryModel.HistoryEvent>();
    for (Datetime d : new List<Datetime>{ T0, null, T1, T1 }) {
      PRM_PracticeLocationHistoryModel.HistoryEvent e = new PRM_PracticeLocationHistoryModel.HistoryEvent();
      e.eventDate = d;
      events.add(e);
    }

    PRM_PracticeLocationHistoryModel.CategoryConfig second = new PRM_PracticeLocationHistoryModel.CategoryConfig();
    second.sortOrder = 20;
    PRM_PracticeLocationHistoryModel.CategoryConfig unordered = new PRM_PracticeLocationHistoryModel.CategoryConfig();
    PRM_PracticeLocationHistoryModel.CategoryConfig first = new PRM_PracticeLocationHistoryModel.CategoryConfig();
    first.sortOrder = 10;
    List<PRM_PracticeLocationHistoryModel.CategoryConfig> configs = new List<PRM_PracticeLocationHistoryModel.CategoryConfig>{
      second,
      unordered,
      first
    };

    Test.startTest();
    rows.sort();
    events.sort();
    configs.sort();
    Test.stopTest();

    System.assertEquals(undated, rows[0], 'Undated rows sort first (oldest)');
    System.assertEquals(earlier, rows[1]);
    System.assertEquals(later, rows[2]);
    System.assertEquals(T1, events[0].eventDate, 'Events newest first');
    System.assertEquals(T0, events[2].eventDate);
    System.assertEquals(null, events[3].eventDate, 'Undated events last');
    System.assertEquals(unordered, configs[0], 'Blank sort order counts as 0');
    System.assertEquals(first, configs[1]);
    System.assertEquals(second, configs[2]);
  }

  @isTest
  static void readsNestedFieldPaths() {
    SObject link = practitionerLink(
      fakeId(HealthcarePractitionerFacility.SObjectType, 1),
      'Jane Doe'
    );

    Test.startTest();
    String nested = PRM_PracticeLocationHistoryService.readPath(
      link,
      'Practitioner.Name'
    );
    String flat = PRM_PracticeLocationHistoryService.readPath(
      link,
      'PRM_PractitionerRole__c'
    );
    String missingParent = PRM_PracticeLocationHistoryService.readPath(
      link,
      'Account.Name'
    );
    Test.stopTest();

    System.assertEquals('Jane Doe', nested);
    System.assertEquals('PCP', flat);
    System.assertEquals(null, missingParent);
  }
}
