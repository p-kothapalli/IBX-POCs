/*
 * @ClassName    : PRM_PracticeLocationHistorySelector
 * @TestClassName: PRM_PracticeLocationHistorySelectorTest
 * @CreatedOn    : 24-SEP-2026
 * @CreatedBy    : IBX
 * @Description  : All reads for the Practice Location change-history feed. Object and
 *                 field names come from PRM_PracticeLocationHistoryConfig__mdt, so queries
 *                 are dynamic; every identifier is validated against a strict pattern and
 *                 every query runs in USER_MODE. Virtual so tests can stub it — the platform
 *                 writes no field history and no FieldHistoryArchive rows in test context.
 */
public virtual with sharing class PRM_PracticeLocationHistorySelector {
  public static final String CASE_MANAGER_FIELD = 'PRM_CaseManager__c';
  public static final String FHNATIC_CASE_NUMBER_FIELD = 'PRM_FHNaticCaseNumber__c';

  private static final Pattern FIELD_PATH_PATTERN = Pattern.compile(
    '^[A-Za-z0-9_]+(\\.[A-Za-z0-9_]+)*$'
  );
  private static Map<String, Schema.SObjectType> globalDescribeCache;

  public virtual List<PRM_PracticeLocationHistoryModel.CategoryConfig> selectActiveCategories() {
    List<PRM_PracticeLocationHistoryModel.CategoryConfig> configs = new List<PRM_PracticeLocationHistoryModel.CategoryConfig>();
    for (
      PRM_PracticeLocationHistoryConfig__mdt row : PRM_PracticeLocationHistoryConfig__mdt.getAll()
        .values()
    ) {
      if (row.PRM_IsActive__c) {
        configs.add(toCategoryConfig(row));
      }
    }
    configs.sort();
    return configs;
  }

  public virtual Set<String> selectIntegrationUserNames() {
    Set<String> names = new Set<String>();
    for (
      PRM_HistoryIntegrationUser__mdt row : PRM_HistoryIntegrationUser__mdt.getAll()
        .values()
    ) {
      if (String.isNotBlank(row.PRM_UserName__c)) {
        names.add(row.PRM_UserName__c.trim().toLowerCase());
      }
    }
    return names;
  }

  public virtual String selectPracticeLocationName(Id practiceLocationId) {
    List<HealthcareFacility> rows = [
      SELECT Name
      FROM HealthcareFacility
      WHERE Id = :practiceLocationId
      WITH USER_MODE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0].Name;
  }

  public virtual List<SObject> selectChildRecords(
    PRM_PracticeLocationHistoryModel.CategoryConfig config,
    Id practiceLocationId,
    Set<String> fieldPaths,
    Integer rowLimit
  ) {
    assertIdentifier(config.objectApiName);
    assertIdentifier(config.parentFieldPath);
    for (String path : fieldPaths) {
      assertIdentifier(path);
    }
    Map<String, Object> binds = new Map<String, Object>{
      'practiceLocationId' => practiceLocationId,
      'rowLimit' => rowLimit
    };
    String soql =
      'SELECT ' +
      String.join(new List<String>(fieldPaths), ', ') +
      ' FROM ' +
      config.objectApiName +
      ' WHERE ' +
      config.parentFieldPath +
      ' = :practiceLocationId';
    if (!config.recordTypes.isEmpty()) {
      soql += ' AND RecordType.DeveloperName IN :recordTypes';
      binds.put('recordTypes', config.recordTypes);
    }
    soql += ' ORDER BY CreatedDate DESC LIMIT :rowLimit';
    return Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
  }

  public virtual List<PRM_PracticeLocationHistoryModel.RawHistoryRow> selectLiveHistory(
    String objectApiName,
    Set<Id> parentIds,
    Integer rowLimit
  ) {
    String historyObject = historyObjectName(objectApiName);
    if (parentIds.isEmpty() || !objectExists(historyObject)) {
      return new List<PRM_PracticeLocationHistoryModel.RawHistoryRow>();
    }
    String parentField = historyParentField(objectApiName);
    String soql =
      'SELECT Id, ' +
      parentField +
      ', Field, DataType, OldValue, NewValue, CreatedDate, CreatedById FROM ' +
      historyObject +
      ' WHERE ' +
      parentField +
      ' IN :parentIds ORDER BY CreatedDate DESC LIMIT :rowLimit';
    List<SObject> rows = Database.queryWithBinds(
      soql,
      new Map<String, Object>{
        'parentIds' => parentIds,
        'rowLimit' => rowLimit
      },
      AccessLevel.USER_MODE
    );
    return toLiveRows(rows, parentField);
  }

  /*
   * FieldHistoryArchive is a big object: filters must follow its index
   * (FieldHistoryType, ParentId, CreatedDate) and ORDER BY is not allowed, so the
   * caller sorts. Verified in IBX QA that USER_MODE + IN on ParentId is accepted.
   */
  public virtual List<PRM_PracticeLocationHistoryModel.RawHistoryRow> selectArchivedHistory(
    String objectApiName,
    Set<Id> parentIds,
    Integer rowLimit
  ) {
    if (parentIds.isEmpty()) {
      return new List<PRM_PracticeLocationHistoryModel.RawHistoryRow>();
    }
    List<SObject> rows = Database.queryWithBinds(
      'SELECT HistoryId, ParentId, Field, OldValue, NewValue, CreatedDate, CreatedById ' +
        'FROM FieldHistoryArchive ' +
        'WHERE FieldHistoryType = :historyType AND ParentId IN :parentIds ' +
        'LIMIT :rowLimit',
      new Map<String, Object>{
        'historyType' => objectApiName,
        'parentIds' => parentIds,
        'rowLimit' => rowLimit
      },
      AccessLevel.USER_MODE
    );
    return toArchivedRows(rows);
  }

  public virtual Map<Id, User> selectUsers(Set<Id> userIds) {
    if (userIds.isEmpty()) {
      return new Map<Id, User>();
    }
    return new Map<Id, User>(
      [SELECT Id, Name, UserType FROM User WHERE Id IN :userIds WITH USER_MODE]
    );
  }

  /*
   * The FHNatic case number is only selected when the running user can read it:
   * USER_MODE would otherwise fail the whole query for users without that FLS.
   */
  public virtual Map<Id, IndividualApplication> selectCaseManagers(
    Set<Id> caseManagerIds
  ) {
    if (caseManagerIds.isEmpty()) {
      return new Map<Id, IndividualApplication>();
    }
    String fields = 'Id, Name';
    if (
      Schema.SObjectType.IndividualApplication.fields.PRM_FHNaticCaseNumber__c.isAccessible()
    ) {
      fields += ', ' + FHNATIC_CASE_NUMBER_FIELD;
    }
    return new Map<Id, IndividualApplication>(
      (List<IndividualApplication>) Database.queryWithBinds(
        'SELECT ' +
          fields +
          ' FROM IndividualApplication WHERE Id IN :caseManagerIds',
        new Map<String, Object>{ 'caseManagerIds' => caseManagerIds },
        AccessLevel.USER_MODE
      )
    );
  }

  public Boolean objectExists(String objectApiName) {
    if (globalDescribeCache == null) {
      globalDescribeCache = Schema.getGlobalDescribe();
    }
    return String.isNotBlank(objectApiName) &&
      globalDescribeCache.containsKey(objectApiName.toLowerCase());
  }

  public Map<String, Schema.SObjectField> describeFields(String objectApiName) {
    if (!objectExists(objectApiName)) {
      return new Map<String, Schema.SObjectField>();
    }
    return globalDescribeCache.get(objectApiName.toLowerCase())
      .getDescribe()
      .fields.getMap();
  }

  @TestVisible
  private static String historyObjectName(String objectApiName) {
    return objectApiName.endsWith('__c')
      ? objectApiName.removeEnd('__c') + '__History'
      : objectApiName + 'History';
  }

  @TestVisible
  private static String historyParentField(String objectApiName) {
    return objectApiName.endsWith('__c') ? 'ParentId' : objectApiName + 'Id';
  }

  @TestVisible
  private static List<PRM_PracticeLocationHistoryModel.RawHistoryRow> toLiveRows(
    List<SObject> rows,
    String parentField
  ) {
    List<PRM_PracticeLocationHistoryModel.RawHistoryRow> out = new List<PRM_PracticeLocationHistoryModel.RawHistoryRow>();
    for (SObject row : rows) {
      PRM_PracticeLocationHistoryModel.RawHistoryRow raw = new PRM_PracticeLocationHistoryModel.RawHistoryRow();
      raw.historyId = (String) row.get('Id');
      raw.parentId = (Id) row.get(parentField);
      raw.field = (String) row.get('Field');
      raw.dataType = (String) row.get('DataType');
      raw.oldValue = row.get('OldValue');
      raw.newValue = row.get('NewValue');
      raw.createdDate = (Datetime) row.get('CreatedDate');
      raw.createdById = (Id) row.get('CreatedById');
      out.add(raw);
    }
    return out;
  }

  @TestVisible
  private static List<PRM_PracticeLocationHistoryModel.RawHistoryRow> toArchivedRows(
    List<SObject> rows
  ) {
    List<PRM_PracticeLocationHistoryModel.RawHistoryRow> out = new List<PRM_PracticeLocationHistoryModel.RawHistoryRow>();
    for (SObject row : rows) {
      out.add(toArchivedRow(row.getPopulatedFieldsAsMap()));
    }
    return out;
  }

  // Takes a field map because FieldHistoryArchive rows cannot be built in tests
  // (JSON.deserialize into a big object raises an internal platform error).
  // The archive qualifies custom fields with the object ("Obj.PRM_Pending__c") where
  // the live table does not, so the prefix is stripped to match live rows.
  @TestVisible
  private static PRM_PracticeLocationHistoryModel.RawHistoryRow toArchivedRow(
    Map<String, Object> values
  ) {
    PRM_PracticeLocationHistoryModel.RawHistoryRow raw = new PRM_PracticeLocationHistoryModel.RawHistoryRow();
    String field = (String) values.get('Field');
    raw.historyId = (String) values.get('HistoryId');
    raw.parentId = (Id) values.get('ParentId');
    raw.field = field != null && field.contains('.')
      ? field.substringAfterLast('.')
      : field;
    raw.oldValue = values.get('OldValue');
    raw.newValue = values.get('NewValue');
    raw.createdDate = (Datetime) values.get('CreatedDate');
    raw.createdById = (Id) values.get('CreatedById');
    raw.isArchived = true;
    return raw;
  }

  @TestVisible
  private static void assertIdentifier(String value) {
    if (String.isBlank(value) || !FIELD_PATH_PATTERN.matcher(value).matches()) {
      throw new IllegalArgumentException(
        'Invalid object or field path in PRM_PracticeLocationHistoryConfig__mdt: ' +
        value
      );
    }
  }

  private static PRM_PracticeLocationHistoryModel.CategoryConfig toCategoryConfig(
    PRM_PracticeLocationHistoryConfig__mdt row
  ) {
    PRM_PracticeLocationHistoryModel.CategoryConfig config = new PRM_PracticeLocationHistoryModel.CategoryConfig();
    config.developerName = row.DeveloperName;
    config.category = row.PRM_Category__c;
    config.subjectLabel = row.PRM_SubjectLabel__c;
    config.objectApiName = row.PRM_ObjectApiName__c;
    config.parentFieldPath = row.PRM_ParentFieldPath__c;
    config.subjectFieldPath = row.PRM_SubjectFieldPath__c;
    config.contextFieldPath = row.PRM_ContextFieldPath__c;
    config.sortOrder = row.PRM_SortOrder__c == null
      ? 0
      : row.PRM_SortOrder__c.intValue();
    config.maxRecords = row.PRM_MaxRecords__c == null
      ? null
      : row.PRM_MaxRecords__c.intValue();
    if (String.isNotBlank(row.PRM_RecordTypes__c)) {
      for (String rt : row.PRM_RecordTypes__c.split(',')) {
        if (String.isNotBlank(rt)) {
          config.recordTypes.add(rt.trim());
        }
      }
    }
    return config;
  }
}
