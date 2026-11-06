/*
 * @ClassName    : PRM_PracticeLocationHistoryController
 * @TestClassName: PRM_PracticeLocationHistoryServiceTest
 * @CreatedOn    : 24-SEP-2026
 * @CreatedBy    : IBX
 * @Description  : LWC controller for prmPracticeLocationHistory on the Practice Location
 *                 (HealthcareFacility) record page. getHistory reads live field history;
 *                 getArchivedHistory reads Field Audit Trail (FieldHistoryArchive) and is
 *                 called on demand. Deliberately not cacheable: PRM_ExceptionLogger inserts
 *                 a log record, and DML is not allowed in cacheable methods.
 */
public with sharing class PRM_PracticeLocationHistoryController {
  @TestVisible
  private static PRM_PracticeLocationHistorySelector selectorOverride;

  @AuraEnabled
  public static PRM_PracticeLocationHistoryModel.HistoryResponse getHistory(
    Id practiceLocationId
  ) {
    return load(practiceLocationId, false);
  }

  @AuraEnabled
  public static PRM_PracticeLocationHistoryModel.HistoryResponse getArchivedHistory(
    Id practiceLocationId
  ) {
    return load(practiceLocationId, true);
  }

  private static PRM_PracticeLocationHistoryModel.HistoryResponse load(
    Id practiceLocationId,
    Boolean fromArchive
  ) {
    if (
      practiceLocationId == null ||
      practiceLocationId.getSObjectType() != HealthcareFacility.SObjectType
    ) {
      return new PRM_PracticeLocationHistoryModel.HistoryResponse();
    }
    try {
      PRM_PracticeLocationHistorySelector selector = selectorOverride == null
        ? new PRM_PracticeLocationHistorySelector()
        : selectorOverride;
      return new PRM_PracticeLocationHistoryService(
          selector,
          new PRM_PracticeLocationHistoryDeriver()
        )
        .getHistory(practiceLocationId, fromArchive);
    } catch (Exception ex) {
      PRM_ExceptionLogger.logException(
        'PRM_PracticeLocationHistoryController',
        'SYNC',
        'Error',
        ex.getStackTraceString(),
        ex.getMessage(),
        ex.getTypeName(),
        ex.getLineNumber(),
        'practiceLocationId: ' +
          practiceLocationId +
          ', archive: ' +
          fromArchive,
        '',
        '',
        '',
        ''
      );
      throw new AuraHandledException(ex.getMessage());
    }
  }
}
