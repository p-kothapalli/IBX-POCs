/**
 * @description Practice Location change history.
 *
 * Record-page component for HealthcareFacility (Practice Location). Shows, in business
 * language, every change to the location and to the records beneath it: practitioners
 * added/removed, location networks and taxonomies added/removed, NPI, info codes,
 * provider features and associations. Categories come from
 * PRM_PracticeLocationHistoryConfig__mdt via PRM_PracticeLocationHistoryController.
 *
 * Three views over the same filtered events:
 *  - Timeline: one card per change (events one user saved together), newest first,
 *    leading with who made it and when.
 *  - By category: one section per category with add/remove/update counts.
 *  - Table: flat and sortable.
 * Live field history loads first; archived history (Field Audit Trail) loads on demand.
 */
import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getHistory from "@salesforce/apex/PRM_PracticeLocationHistoryController.getHistory";
import getArchivedHistory from "@salesforce/apex/PRM_PracticeLocationHistoryController.getArchivedHistory";

const VIEW_TIMELINE = "timeline";
const VIEW_CATEGORY = "category";
const VIEW_TABLE = "table";
const VIEWS = new Set([VIEW_TIMELINE, VIEW_CATEGORY, VIEW_TABLE]);
const ALL = "all";
const ACTOR_PEOPLE = "people";
const ACTOR_INTEGRATION = "integration";
const GROUP_PAGE_SIZE = 25;
const COLLAPSED_EVENT_COUNT = 3;
const CATEGORY_PREVIEW_COUNT = 10;
const MINUTE_MS = 60 * 1000;
const HOUR_MS = 60 * MINUTE_MS;
const DAY_MS = 24 * HOUR_MS;

const ADDED = "Added";
const REMOVAL_TYPES = new Set(["Removed", "Scheduled removal", "Deactivated"]);
const RESTORE_TYPES = new Set(["Reinstated", "Reactivated"]);
const END_DATE_TYPES = new Set([
  "Removed",
  "Scheduled removal",
  "End date changed"
]);

// Tone drives the pill colour and the card's left rail; the pill always carries text too.
const TYPE_TONES = {
  Added: "add",
  Removed: "remove",
  Deactivated: "remove",
  "Scheduled removal": "schedule",
  Reinstated: "restore",
  Reactivated: "restore",
  "Error cleared": "restore",
  "Pending cleared": "restore",
  "Marked as error": "warn",
  Pending: "warn"
};
const TONE_PRIORITY = [
  "remove",
  "schedule",
  "add",
  "restore",
  "warn",
  "update"
];

const CATEGORY_ICONS = {
  "Practice Location": "utility:location",
  Practitioners: "utility:user",
  Networks: "utility:world",
  "Practitioner Networks": "utility:world",
  Taxonomies: "utility:hierarchy",
  NPI: "utility:identity",
  "Info Codes": "utility:info_alt",
  "Provider Features": "utility:favorite",
  Associations: "utility:link"
};
const DEFAULT_CATEGORY_ICON = "utility:record";
const KPI_CATEGORIES = ["Practitioners", "Networks", "Taxonomies"];

const TABLE_COLUMNS = [
  {
    label: "Changed on",
    fieldName: "eventDate",
    type: "date",
    sortable: true,
    initialWidth: 170,
    typeAttributes: {
      year: "numeric",
      month: "short",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit"
    }
  },
  {
    label: "Changed by",
    fieldName: "actorLabel",
    sortable: true,
    initialWidth: 190
  },
  {
    label: "Category",
    fieldName: "category",
    sortable: true,
    initialWidth: 130
  },
  {
    label: "Change",
    fieldName: "eventType",
    sortable: true,
    initialWidth: 140
  },
  {
    label: "What happened",
    fieldName: "recordUrl",
    type: "url",
    wrapText: true,
    typeAttributes: { label: { fieldName: "sentence" }, target: "_blank" }
  },
  { label: "Old value", fieldName: "oldValue", wrapText: true },
  { label: "New value", fieldName: "newValue", wrapText: true },
  {
    label: "Effective from",
    fieldName: "recordEffectiveFrom",
    type: "date-local",
    sortable: true,
    initialWidth: 125
  },
  {
    label: "End date",
    fieldName: "endDate",
    type: "date-local",
    initialWidth: 115
  },
  {
    label: "Case Manager",
    fieldName: "caseManagerUrl",
    type: "url",
    initialWidth: 140,
    typeAttributes: {
      label: { fieldName: "caseManagerName" },
      target: "_blank"
    }
  },
  {
    label: "FHNatic Case #",
    fieldName: "fhnaticCaseNumber",
    sortable: true,
    initialWidth: 140
  }
];

export default class PrmPracticeLocationHistory extends LightningElement {
  @api recordId;
  @api defaultView = VIEW_TIMELINE;
  @api defaultDateRange = "90";
  @api pageHeight = "720px";

  events = [];
  categories = [];
  truncatedCategories = [];
  practiceLocationName;

  isLoading = true;
  errorMessage;
  archiveLoaded = false;
  archiveLoading = false;

  activeView = VIEW_TIMELINE;
  categoryFilter = ALL;
  eventTypeFilter = ALL;
  actorFilter = ALL;
  dateRange = "90";
  addsRemovesOnly = false;
  searchTerm = "";
  groupLimit = GROUP_PAGE_SIZE;
  expandedGroups = new Set();
  collapsedCategories = new Set();
  expandedCategories = new Set();
  sortedBy = "eventDate";
  sortDirection = "desc";

  columns = TABLE_COLUMNS;

  connectedCallback() {
    this.activeView = VIEWS.has(this.defaultView)
      ? this.defaultView
      : VIEW_TIMELINE;
    this.dateRange = this.defaultDateRange || "90";
    this.loadHistory();
  }

  // ---------- Data loading ----------

  async loadHistory() {
    if (!this.recordId) {
      this.isLoading = false;
      return;
    }
    this.isLoading = true;
    this.errorMessage = undefined;
    try {
      const response = await getHistory({ practiceLocationId: this.recordId });
      this.applyResponse(response, false);
    } catch (error) {
      this.errorMessage = this.extractErrorMessage(error);
      this.events = [];
    } finally {
      this.isLoading = false;
    }
  }

  async handleLoadArchive() {
    this.archiveLoading = true;
    try {
      const response = await getArchivedHistory({
        practiceLocationId: this.recordId
      });
      const added = this.applyResponse(response, true);
      this.archiveLoaded = true;
      if (added === 0) {
        this.toast(
          "No older changes",
          "The archive has no additional changes for this location.",
          "info"
        );
      }
    } catch (error) {
      this.toast(
        "Could not load archived history",
        this.extractErrorMessage(error),
        "error"
      );
    } finally {
      this.archiveLoading = false;
    }
  }

  /**
   * Merges a response into the current feed. Live rows win over archived copies of the
   * same history row (same id). Returns how many new events were added.
   */
  applyResponse(response, isArchive) {
    const data = response || {};
    if (!isArchive) {
      this.practiceLocationName = data.practiceLocationName;
      this.categories = data.categories || [];
    }
    this.truncatedCategories = [
      ...new Set([
        ...this.truncatedCategories,
        ...(data.truncatedCategories || [])
      ])
    ];
    const byId = new Map((isArchive ? this.events : []).map((e) => [e.id, e]));
    let added = 0;
    (data.events || []).forEach((raw) => {
      if (!byId.has(raw.id)) {
        byId.set(raw.id, this.toViewEvent(raw));
        added += 1;
      }
    });
    this.events = [...byId.values()].sort((a, b) => b.eventTime - a.eventTime);
    return added;
  }

  toViewEvent(raw) {
    const tone = TYPE_TONES[raw.eventType] || "update";
    const eventTime = raw.eventDate ? new Date(raw.eventDate).getTime() : 0;
    const actorName = raw.actorName || "Unknown user";
    return {
      ...raw,
      actorName,
      eventTime,
      tone,
      pillClass: `plh-pill plh-pill_${tone}`,
      relativeTime: this.relativeTime(eventTime),
      hasValues:
        !raw.isAddOrRemove && (raw.oldValue != null || raw.newValue != null),
      oldDisplay: raw.oldValue == null ? "—" : raw.oldValue,
      newDisplay: raw.newValue == null ? "—" : raw.newValue,
      endDate: END_DATE_TYPES.has(raw.eventType) ? raw.effectiveDate : null,
      recordUrl: raw.recordId ? `/${raw.recordId}` : null,
      caseManagerUrl: raw.caseManagerId ? `/${raw.caseManagerId}` : null,
      actorLabel: raw.isIntegration ? `${actorName} (Integration)` : actorName
    };
  }

  // ---------- Filtering ----------

  get filteredEvents() {
    return this.filterEvents(true);
  }

  /** @param {boolean} applyCategory false when counting events per category chip. */
  filterEvents(applyCategory) {
    const term = (this.searchTerm || "").trim().toLowerCase();
    const cutoff =
      this.dateRange === ALL
        ? null
        : Date.now() - Number(this.dateRange) * DAY_MS;
    return this.events.filter((e) => {
      if (cutoff && e.eventTime < cutoff) return false;
      if (
        applyCategory &&
        this.categoryFilter !== ALL &&
        e.category !== this.categoryFilter
      )
        return false;
      if (this.eventTypeFilter !== ALL && e.eventType !== this.eventTypeFilter)
        return false;
      if (this.addsRemovesOnly && !e.isAddOrRemove) return false;
      if (this.actorFilter === ACTOR_INTEGRATION && !e.isIntegration)
        return false;
      if (this.actorFilter === ACTOR_PEOPLE && e.isIntegration) return false;
      if (term) {
        const haystack = [
          e.sentence,
          e.subject,
          e.context,
          e.fieldLabel,
          e.oldValue,
          e.newValue,
          e.actorName,
          e.caseManagerName,
          e.fhnaticCaseNumber
        ]
          .filter((v) => v)
          .join(" ")
          .toLowerCase();
        if (!haystack.includes(term)) return false;
      }
      return true;
    });
  }

  // ---------- Header, KPIs and category chips ----------

  get lastChange() {
    const latest = this.events[0];
    return latest
      ? {
          eventDate: latest.eventDate,
          actorName: latest.actorName,
          relativeTime: latest.relativeTime
        }
      : null;
  }

  get kpiTiles() {
    const counts = this.countByCategory(this.filteredEvents);
    let fieldUpdates = 0;
    this.filteredEvents.forEach((e) => {
      if (!e.isAddOrRemove) fieldUpdates += 1;
    });
    const tiles = KPI_CATEGORIES.map((category) => {
      const c = counts.get(category) || { added: 0, removed: 0 };
      return {
        key: category,
        label: category,
        icon: CATEGORY_ICONS[category],
        added: c.added,
        removed: c.removed,
        isCounts: true,
        isActive: this.categoryFilter === category,
        tileClass:
          this.categoryFilter === category
            ? "plh-kpi plh-kpi_active"
            : "plh-kpi",
        ariaPressed: this.categoryFilter === category ? "true" : "false"
      };
    });
    tiles.push({
      key: "updates",
      label: "Field updates",
      icon: "utility:edit",
      total: fieldUpdates,
      isCounts: false,
      tileClass: "plh-kpi plh-kpi_static"
    });
    return tiles;
  }

  get categoryChips() {
    const pool = this.filterEvents(false);
    const totals = new Map();
    pool.forEach((e) =>
      totals.set(e.category, (totals.get(e.category) || 0) + 1)
    );
    const chip = (value, label, count, icon) => {
      const active = this.categoryFilter === value;
      return {
        value,
        label,
        count,
        icon,
        chipClass: active ? "plh-chip plh-chip_active" : "plh-chip",
        ariaPressed: active ? "true" : "false"
      };
    };
    return [
      chip(ALL, "All", pool.length, "utility:rows"),
      ...this.categories.map((c) =>
        chip(
          c,
          c,
          totals.get(c) || 0,
          CATEGORY_ICONS[c] || DEFAULT_CATEGORY_ICON
        )
      )
    ];
  }

  countByCategory(events) {
    const counts = new Map();
    events.forEach((e) => {
      const c = counts.get(e.category) || { added: 0, removed: 0, updates: 0 };
      if (e.eventType === ADDED) c.added += 1;
      else if (REMOVAL_TYPES.has(e.eventType)) c.removed += 1;
      else if (!e.isAddOrRemove) c.updates += 1;
      counts.set(e.category, c);
    });
    return counts;
  }

  // ---------- Timeline ----------

  get changeGroups() {
    const groups = [];
    const byKey = new Map();
    this.filteredEvents.forEach((e) => {
      const key = e.groupKey || e.id;
      let group = byKey.get(key);
      if (!group) {
        group = { key, events: [] };
        byKey.set(key, group);
        groups.push(group);
      }
      group.events.push(e);
    });
    return groups;
  }

  get timelineDays() {
    const days = [];
    const byDay = new Map();
    this.changeGroups.slice(0, this.groupLimit).forEach((group) => {
      const first = group.events[0];
      const dayLabel = this.formatDay(first.eventTime);
      let day = byDay.get(dayLabel);
      if (!day) {
        day = { dayLabel, groups: [], changeCount: 0 };
        byDay.set(dayLabel, day);
        days.push(day);
      }
      day.groups.push(this.toGroupView(group));
      day.changeCount += group.events.length;
    });
    return days.map((d) => ({
      ...d,
      countLabel: `${d.changeCount} ${d.changeCount === 1 ? "change" : "changes"}`
    }));
  }

  toGroupView(group) {
    const first = group.events[0];
    const expanded = this.expandedGroups.has(group.key);
    const total = group.events.length;
    const tones = new Set(group.events.map((e) => e.tone));
    const tone = TONE_PRIORITY.find((t) => tones.has(t)) || "update";
    const categories = [...new Set(group.events.map((e) => e.category))];
    const withCaseManager = group.events.find((e) => e.caseManagerName);
    const withFhnatic = group.events.find((e) => e.fhnaticCaseNumber);
    return {
      key: group.key,
      cardClass: `plh-card plh-card_${tone}`,
      eventDate: first.eventDate,
      relativeTime: first.relativeTime,
      actorName: first.actorName,
      actorInitials: this.initials(first.actorName),
      isIntegration: first.isIntegration,
      isArchived: first.isArchived,
      caseManagerName: withCaseManager ? withCaseManager.caseManagerName : null,
      caseManagerUrl: withCaseManager ? withCaseManager.caseManagerUrl : null,
      fhnaticCaseNumber: withFhnatic ? withFhnatic.fhnaticCaseNumber : null,
      categoryTags: categories.map((c) => ({
        name: c,
        icon: CATEGORY_ICONS[c] || DEFAULT_CATEGORY_ICON
      })),
      headline: total === 1 ? first.sentence : this.headline(group),
      visibleEvents: expanded
        ? group.events
        : group.events.slice(0, COLLAPSED_EVENT_COUNT),
      isExpandable: total > COLLAPSED_EVENT_COUNT,
      toggleLabel: expanded ? "Show fewer" : `Show all ${total} changes`,
      ariaExpanded: expanded ? "true" : "false"
    };
  }

  headline(group) {
    let added = 0;
    let removed = 0;
    let restored = 0;
    group.events.forEach((e) => {
      if (e.eventType === ADDED) added += 1;
      else if (REMOVAL_TYPES.has(e.eventType)) removed += 1;
      else if (RESTORE_TYPES.has(e.eventType)) restored += 1;
    });
    const parts = [`${group.events.length} changes`];
    if (added) parts.push(`${added} added`);
    if (removed) parts.push(`${removed} removed`);
    if (restored) parts.push(`${restored} reinstated`);
    return parts.join(" · ");
  }

  get hasMoreGroups() {
    return this.changeGroups.length > this.groupLimit;
  }

  get remainingGroupCount() {
    return this.changeGroups.length - this.groupLimit;
  }

  // ---------- By category ----------

  get categorySections() {
    const byCategory = new Map();
    this.filteredEvents.forEach((e) => {
      if (!byCategory.has(e.category)) byCategory.set(e.category, []);
      byCategory.get(e.category).push(e);
    });
    const counts = this.countByCategory(this.filteredEvents);
    const ordered = [
      ...this.categories.filter((c) => byCategory.has(c)),
      ...[...byCategory.keys()].filter((c) => !this.categories.includes(c))
    ];
    return ordered.map((category) => {
      const events = byCategory.get(category);
      const c = counts.get(category);
      const isOpen = !this.collapsedCategories.has(category);
      const showAll = this.expandedCategories.has(category);
      return {
        category,
        icon: CATEGORY_ICONS[category] || DEFAULT_CATEGORY_ICON,
        totalLabel: `${events.length} ${events.length === 1 ? "change" : "changes"}`,
        added: c.added,
        removed: c.removed,
        updates: c.updates,
        isOpen,
        ariaExpanded: isOpen ? "true" : "false",
        chevron: isOpen ? "utility:chevrondown" : "utility:chevronright",
        rows: showAll ? events : events.slice(0, CATEGORY_PREVIEW_COUNT),
        hasMore: events.length > CATEGORY_PREVIEW_COUNT,
        moreLabel: showAll ? "Show fewer" : `Show all ${events.length}`
      };
    });
  }

  // ---------- Table ----------

  get tableRows() {
    const direction = this.sortDirection === "asc" ? 1 : -1;
    const field = this.sortedBy === "eventDate" ? "eventTime" : this.sortedBy;
    return [...this.filteredEvents].sort((a, b) => {
      const av = a[field];
      const bv = b[field];
      if (av == null) return 1;
      if (bv == null) return -1;
      if (av < bv) return -1 * direction;
      if (av > bv) return 1 * direction;
      return 0;
    });
  }

  // ---------- View state ----------

  get isLoaded() {
    return !this.isLoading && !this.errorMessage;
  }

  get hasResults() {
    return this.isLoaded && this.filteredEvents.length > 0;
  }

  get hasNoResults() {
    return this.isLoaded && this.filteredEvents.length === 0;
  }

  get hasNoHistoryAtAll() {
    return this.events.length === 0;
  }

  get isTimelineView() {
    return this.activeView === VIEW_TIMELINE;
  }

  get isCategoryView() {
    return this.activeView === VIEW_CATEGORY;
  }

  get isTableView() {
    return this.activeView === VIEW_TABLE;
  }

  get hasTruncation() {
    return this.truncatedCategories.length > 0;
  }

  get truncationMessage() {
    return `Showing the most recent records only for: ${this.truncatedCategories.join(
      ", "
    )}.`;
  }

  get resultSummary() {
    const shown = this.filteredEvents.length;
    const total = this.events.length;
    const noun = total === 1 ? "change" : "changes";
    return shown === total
      ? `${total} ${noun}`
      : `${shown} of ${total} ${noun}`;
  }

  get scrollStyle() {
    const height = (this.pageHeight || "").trim();
    return height ? `max-height: ${height}; overflow-y: auto;` : "";
  }

  get showArchiveButton() {
    return this.isLoaded && !this.archiveLoaded;
  }

  get viewOptions() {
    return [
      { label: "Timeline", value: VIEW_TIMELINE },
      { label: "By category", value: VIEW_CATEGORY },
      { label: "Table", value: VIEW_TABLE }
    ];
  }

  get eventTypeOptions() {
    const types = [...new Set(this.events.map((e) => e.eventType))].sort();
    return [
      { label: "All changes", value: ALL },
      ...types.map((t) => ({ label: t, value: t }))
    ];
  }

  get actorOptions() {
    return [
      { label: "Everyone", value: ALL },
      { label: "People", value: ACTOR_PEOPLE },
      { label: "Integration", value: ACTOR_INTEGRATION }
    ];
  }

  get dateRangeOptions() {
    return [
      { label: "Last 30 days", value: "30" },
      { label: "Last 90 days", value: "90" },
      { label: "Last 12 months", value: "365" },
      { label: "All time", value: ALL }
    ];
  }

  // ---------- Handlers ----------

  handleViewChange(event) {
    this.activeView = event.detail.value;
  }

  handleCategoryChip(event) {
    this.categoryFilter = event.currentTarget.dataset.value;
    this.resetPaging();
  }

  handleKpiClick(event) {
    const category = event.currentTarget.dataset.value;
    this.categoryFilter = this.categoryFilter === category ? ALL : category;
    this.resetPaging();
  }

  handleEventTypeChange(event) {
    this.eventTypeFilter = event.detail.value;
    this.resetPaging();
  }

  handleActorChange(event) {
    this.actorFilter = event.detail.value;
    this.resetPaging();
  }

  handleDateRangeChange(event) {
    this.dateRange = event.detail.value;
    this.resetPaging();
  }

  handleAddsRemovesToggle(event) {
    this.addsRemovesOnly = event.target.checked;
    this.resetPaging();
  }

  handleSearch(event) {
    this.searchTerm = event.target.value;
    this.resetPaging();
  }

  handleShowAllTime() {
    this.dateRange = ALL;
    this.resetPaging();
  }

  handleToggleGroup(event) {
    this.expandedGroups = this.toggled(
      this.expandedGroups,
      event.currentTarget.dataset.key
    );
  }

  handleToggleSection(event) {
    this.collapsedCategories = this.toggled(
      this.collapsedCategories,
      event.currentTarget.dataset.value
    );
  }

  handleToggleSectionRows(event) {
    this.expandedCategories = this.toggled(
      this.expandedCategories,
      event.currentTarget.dataset.value
    );
  }

  handleShowMoreGroups() {
    this.groupLimit += GROUP_PAGE_SIZE;
  }

  handleSort(event) {
    this.sortedBy = event.detail.fieldName;
    this.sortDirection = event.detail.sortDirection;
  }

  handleRefresh() {
    this.archiveLoaded = false;
    this.truncatedCategories = [];
    this.expandedGroups = new Set();
    this.loadHistory();
  }

  resetPaging() {
    this.groupLimit = GROUP_PAGE_SIZE;
  }

  // ---------- Helpers ----------

  toggled(set, key) {
    const next = new Set(set);
    if (next.has(key)) next.delete(key);
    else next.add(key);
    return next;
  }

  initials(name) {
    const parts = (name || "").trim().split(/\s+/).filter(Boolean);
    if (!parts.length) return "?";
    const first = parts[0][0];
    const last = parts.length > 1 ? parts[parts.length - 1][0] : "";
    return `${first}${last}`.toUpperCase();
  }

  relativeTime(time) {
    if (!time) return "";
    const diff = Math.max(0, Date.now() - time);
    if (diff < HOUR_MS) {
      return `${Math.max(1, Math.round(diff / MINUTE_MS))} min ago`;
    }
    if (diff < DAY_MS) return `${Math.round(diff / HOUR_MS)} hr ago`;
    const days = Math.floor(diff / DAY_MS);
    if (days === 1) return "Yesterday";
    if (days < 30) return `${days} days ago`;
    const months = Math.round(days / 30);
    if (months < 12) return `${months} mo ago`;
    const years = Math.round(days / 365);
    return `${years} yr ago`;
  }

  formatDay(time) {
    if (!time) return "Unknown date";
    return new Date(time).toLocaleDateString(undefined, {
      weekday: "long",
      year: "numeric",
      month: "long",
      day: "numeric"
    });
  }

  extractErrorMessage(error) {
    if (!error) return "Unknown error";
    if (Array.isArray(error.body)) {
      return error.body.map((e) => e.message).join(", ");
    }
    if (error.body && error.body.message) return error.body.message;
    return error.message || "Unknown error";
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
