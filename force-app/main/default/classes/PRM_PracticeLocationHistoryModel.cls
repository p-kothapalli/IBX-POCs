/*
 * @ClassName    : PRM_PracticeLocationHistoryModel
 * @TestClassName: PRM_PracticeLocationHistoryServiceTest
 * @CreatedOn    : 24-SEP-2026
 * @CreatedBy    : IBX
 * @Description  : Data shapes shared by the Practice Location change-history feed
 *                 (prmPracticeLocationHistory LWC): category configuration, the child
 *                 records a category resolves to, normalised raw history rows (live
 *                 <Object>History and FieldHistoryArchive), and the business events
 *                 returned to the LWC.
 */
public with sharing class PRM_PracticeLocationHistoryModel {
  public class CategoryConfig implements Comparable {
    public String developerName;
    public String category;
    public String subjectLabel;
    public String objectApiName;
    public String parentFieldPath;
    public List<String> recordTypes = new List<String>();
    public String subjectFieldPath;
    public String contextFieldPath;
    public Integer sortOrder;
    public Integer maxRecords;

    public Boolean isPracticeLocationItself() {
      return parentFieldPath == 'Id';
    }

    public Integer compareTo(Object other) {
      Integer mine = sortOrder == null ? 0 : sortOrder;
      Integer theirs = ((CategoryConfig) other).sortOrder == null
        ? 0
        : ((CategoryConfig) other).sortOrder;
      return mine - theirs;
    }
  }

  public class ChildRecord {
    public Id recordId;
    public String subject;
    public String context;
    public Date effectiveFrom;
    public Id currentCaseManagerId;
    public CategoryConfig config;
  }

  /*
   * One field-history row, independent of whether it came from the live history table
   * or FieldHistoryArchive. After PRM_PracticeLocationHistoryDeriver.mergeRows, a lookup
   * change's Id row and name row are collapsed into one row carrying both.
   */
  public class RawHistoryRow implements Comparable {
    public String historyId;
    public Id parentId;
    public String field;
    public String dataType;
    public Object oldValue;
    public Object newValue;
    public Id oldRecordId;
    public Id newRecordId;
    public Datetime createdDate;
    public Id createdById;
    public Boolean isArchived = false;

    public Integer compareTo(Object other) {
      Datetime theirs = ((RawHistoryRow) other).createdDate;
      if (createdDate == theirs) {
        return 0;
      }
      if (createdDate == null) {
        return -1;
      }
      if (theirs == null) {
        return 1;
      }
      return createdDate < theirs ? -1 : 1;
    }
  }

  public class HistoryEvent implements Comparable {
    @AuraEnabled
    public String id;
    @AuraEnabled
    public String groupKey;
    @AuraEnabled
    public String category;
    @AuraEnabled
    public String eventType;
    @AuraEnabled
    public Boolean isAddOrRemove;
    @AuraEnabled
    public String sentence;
    @AuraEnabled
    public String subject;
    @AuraEnabled
    public String context;
    @AuraEnabled
    public String fieldLabel;
    @AuraEnabled
    public String oldValue;
    @AuraEnabled
    public String newValue;
    @AuraEnabled
    public Date effectiveDate;
    @AuraEnabled
    public Date recordEffectiveFrom;
    @AuraEnabled
    public String fhnaticCaseNumber;
    @AuraEnabled
    public Datetime eventDate;
    @AuraEnabled
    public Id actorId;
    @AuraEnabled
    public String actorName;
    @AuraEnabled
    public Boolean isIntegration;
    @AuraEnabled
    public Id caseManagerId;
    @AuraEnabled
    public String caseManagerName;
    @AuraEnabled
    public Id recordId;
    @AuraEnabled
    public Boolean isArchived;

    public Integer compareTo(Object other) {
      HistoryEvent that = (HistoryEvent) other;
      if (this.eventDate == that.eventDate) {
        return 0;
      }
      if (this.eventDate == null) {
        return 1;
      }
      if (that.eventDate == null) {
        return -1;
      }
      return this.eventDate > that.eventDate ? -1 : 1;
    }
  }

  public class HistoryResponse {
    @AuraEnabled
    public String practiceLocationName;
    @AuraEnabled
    public Boolean includesArchive = false;
    @AuraEnabled
    public List<String> categories = new List<String>();
    @AuraEnabled
    public List<String> truncatedCategories = new List<String>();
    @AuraEnabled
    public List<HistoryEvent> events = new List<HistoryEvent>();
  }
}
