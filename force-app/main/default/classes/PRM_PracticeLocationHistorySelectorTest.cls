/*
 * @ClassName    : PRM_PracticeLocationHistorySelectorTest
 * @CreatedOn    : 24-SEP-2026
 * @CreatedBy    : IBX
 * @Description  : Runs PRM_PracticeLocationHistorySelector's dynamic queries against the real
 *                 schema and the deployed PRM_PracticeLocationHistoryConfig__mdt rows, so a bad
 *                 object/field path in configuration fails here rather than on the record page.
 */
@isTest
private class PRM_PracticeLocationHistorySelectorTest {
  private static Id fakeId(Schema.SObjectType type, Integer n) {
    return Id.valueOf(
      type.getDescribe().getKeyPrefix() + String.valueOf(n).leftPad(12, '0')
    );
  }

  @isTest
  static void everyActiveConfigRowProducesAValidQuery() {
    PRM_PracticeLocationHistorySelector selector = new PRM_PracticeLocationHistorySelector();
    Id practiceLocationId = fakeId(HealthcareFacility.SObjectType, 1);

    Test.startTest();
    List<PRM_PracticeLocationHistoryModel.CategoryConfig> configs = selector.selectActiveCategories();
    Integer queried = 0;
    for (PRM_PracticeLocationHistoryModel.CategoryConfig config : configs) {
      System.assert(
        selector.objectExists(config.objectApiName),
        'Unknown object in config ' + config.developerName
      );
      Set<String> paths = new Set<String>{ 'Id', config.subjectFieldPath };
      if (String.isNotBlank(config.contextFieldPath)) {
        paths.add(config.contextFieldPath);
      }
      List<SObject> rows = selector.selectChildRecords(
        config,
        practiceLocationId,
        paths,
        1
      );
      System.assertEquals(0, rows.size());
      queried++;
    }
    Test.stopTest();

    System.assert(!configs.isEmpty(), 'POC config rows are deployed');
    System.assertEquals(configs.size(), queried);
    for (Integer i = 1; i < configs.size(); i++) {
      System.assert(
        configs[i - 1].sortOrder <= configs[i].sortOrder,
        'Configs are sorted'
      );
    }
  }

  @isTest
  static void readsLiveArchiveUsersAndCaseManagers() {
    PRM_PracticeLocationHistorySelector selector = new PRM_PracticeLocationHistorySelector();
    Set<Id> parents = new Set<Id>{
      fakeId(HealthcarePractitionerFacility.SObjectType, 1)
    };
    Set<Id> customParents = new Set<Id>{
      fakeId(PRM_InfoCodeAssignment__c.SObjectType, 1)
    };

    Test.startTest();
    List<PRM_PracticeLocationHistoryModel.RawHistoryRow> live = selector.selectLiveHistory(
      'HealthcarePractitionerFacility',
      parents,
      10
    );
    List<PRM_PracticeLocationHistoryModel.RawHistoryRow> customLive = selector.selectLiveHistory(
      'PRM_InfoCodeAssignment__c',
      customParents,
      10
    );
    List<PRM_PracticeLocationHistoryModel.RawHistoryRow> archived = selector.selectArchivedHistory(
      'HealthcarePractitionerFacility',
      parents,
      10
    );
    List<PRM_PracticeLocationHistoryModel.RawHistoryRow> noParents = selector.selectArchivedHistory(
      'HealthcarePractitionerFacility',
      new Set<Id>(),
      10
    );
    List<PRM_PracticeLocationHistoryModel.RawHistoryRow> unknownObject = selector.selectLiveHistory(
      'NotARealObject__c',
      parents,
      10
    );
    Map<Id, User> users = selector.selectUsers(
      new Set<Id>{ UserInfo.getUserId() }
    );
    Map<Id, IndividualApplication> caseManagers = selector.selectCaseManagers(
      new Set<Id>{ fakeId(IndividualApplication.SObjectType, 1) }
    );
    Map<Id, IndividualApplication> noCaseManagers = selector.selectCaseManagers(
      new Set<Id>()
    );
    String locationName = selector.selectPracticeLocationName(
      fakeId(HealthcareFacility.SObjectType, 1)
    );
    Set<String> integrationNames = selector.selectIntegrationUserNames();
    Test.stopTest();

    System.assertEquals(0, live.size());
    System.assertEquals(0, customLive.size());
    System.assertEquals(0, archived.size());
    System.assertEquals(0, noParents.size());
    System.assertEquals(0, unknownObject.size());
    System.assertEquals(
      UserInfo.getName(),
      users.get(UserInfo.getUserId()).Name
    );
    System.assertEquals(0, caseManagers.size());
    System.assertEquals(0, noCaseManagers.size());
    System.assertEquals(null, locationName);
    System.assert(
      integrationNames.contains('mulesoft integration user'),
      'Integration users are lower-cased for matching'
    );
  }

  @isTest
  static void mapsLiveAndArchivedRows() {
    Id parentId = fakeId(HealthcarePractitionerFacility.SObjectType, 7);
    SObject liveRow = (SObject) JSON.deserialize(
      '{"attributes":{"type":"HealthcarePractitionerFacilityHistory"},' +
        '"HealthcarePractitionerFacilityId":"' +
        parentId +
        '","Field":"EffectiveTo","DataType":"Date",' +
        '"CreatedDate":"2026-09-18T14:00:00.000+0000","CreatedById":"' +
        UserInfo.getUserId() +
        '"}',
      HealthcarePractitionerFacilityHistory.class
    );
    Map<String, Object> archivedValues = new Map<String, Object>{
      'HistoryId' => '017000000000001',
      'ParentId' => parentId,
      'Field' => 'HealthcarePractitionerFacility.PRM_Pending__c',
      'OldValue' => 'true',
      'NewValue' => 'false',
      'CreatedDate' => Datetime.newInstanceGmt(2026, 1, 2, 10, 0, 0),
      'CreatedById' => UserInfo.getUserId()
    };

    Test.startTest();
    List<PRM_PracticeLocationHistoryModel.RawHistoryRow> live = PRM_PracticeLocationHistorySelector.toLiveRows(
      new List<SObject>{ liveRow },
      'HealthcarePractitionerFacilityId'
    );
    PRM_PracticeLocationHistoryModel.RawHistoryRow archived = PRM_PracticeLocationHistorySelector.toArchivedRow(
      archivedValues
    );
    List<PRM_PracticeLocationHistoryModel.RawHistoryRow> noArchivedRows = PRM_PracticeLocationHistorySelector.toArchivedRows(
      new List<SObject>()
    );
    Test.stopTest();

    System.assertEquals(parentId, live[0].parentId);
    System.assertEquals('EffectiveTo', live[0].field);
    System.assertEquals('Date', live[0].dataType);
    System.assertEquals(false, live[0].isArchived);
    System.assertEquals('017000000000001', archived.historyId);
    System.assertEquals(parentId, archived.parentId);
    System.assertEquals(
      'PRM_Pending__c',
      archived.field,
      'Archive object prefix is stripped to match live rows'
    );
    System.assertEquals('false', archived.newValue);
    System.assertEquals(true, archived.isArchived);
    System.assertEquals(0, noArchivedRows.size());
  }

  @isTest
  static void namesHistoryTablesAndRejectsUnsafePaths() {
    Boolean rejected = false;

    Test.startTest();
    String standardTable = PRM_PracticeLocationHistorySelector.historyObjectName(
      'HealthcareFacilityNetwork'
    );
    String customTable = PRM_PracticeLocationHistorySelector.historyObjectName(
      'PRM_InfoCodeAssignment__c'
    );
    String standardKey = PRM_PracticeLocationHistorySelector.historyParentField(
      'HealthcareFacilityNetwork'
    );
    String customKey = PRM_PracticeLocationHistorySelector.historyParentField(
      'PRM_InfoCodeAssignment__c'
    );
    try {
      PRM_PracticeLocationHistorySelector.assertIdentifier('Name FROM User --');
    } catch (IllegalArgumentException ex) {
      rejected = true;
    }
    Test.stopTest();

    System.assertEquals('HealthcareFacilityNetworkHistory', standardTable);
    System.assertEquals('PRM_InfoCodeAssignment__History', customTable);
    System.assertEquals('HealthcareFacilityNetworkId', standardKey);
    System.assertEquals('ParentId', customKey);
    System.assertEquals(true, rejected);
  }
}
