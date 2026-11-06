import { createElement } from "lwc";
import PrmPracticeLocationHistory from "c/prmPracticeLocationHistory";
import getHistory from "@salesforce/apex/PRM_PracticeLocationHistoryController.getHistory";
import getArchivedHistory from "@salesforce/apex/PRM_PracticeLocationHistoryController.getArchivedHistory";

jest.mock(
  "@salesforce/apex/PRM_PracticeLocationHistoryController.getHistory",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PRM_PracticeLocationHistoryController.getArchivedHistory",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const HOUR = 60 * 60 * 1000;
const iso = (hoursAgo) => new Date(Date.now() - hoursAgo * HOUR).toISOString();

function evt(overrides) {
  return {
    id: overrides.id,
    groupKey: overrides.groupKey || overrides.id,
    category: "Practitioners",
    eventType: "Added",
    isAddOrRemove: true,
    sentence: "Practitioner Jane Doe (PCP) added",
    subject: "Jane Doe",
    eventDate: iso(2),
    recordEffectiveFrom: "2026-09-01",
    actorId: "005000000000001",
    actorName: "Pat Specialist",
    isIntegration: false,
    caseManagerId: "0iT000000000001",
    caseManagerName: "IA-0001",
    fhnaticCaseNumber: "FHN-7788",
    recordId: "0cq000000000001",
    isArchived: false,
    ...overrides
  };
}

const LIVE_RESPONSE = {
  practiceLocationName: "Main Street Clinic",
  includesArchive: false,
  categories: ["Practice Location", "Practitioners", "Networks", "Taxonomies"],
  truncatedCategories: [],
  events: [
    evt({ id: "h1", groupKey: "g1" }),
    evt({
      id: "h2",
      groupKey: "g1",
      category: "Networks",
      eventType: "Removed",
      sentence: "Network Amerihealth PPO removed, effective 9/18/2026",
      subject: "Amerihealth PPO",
      effectiveDate: "2026-09-18",
      recordEffectiveFrom: "2025-01-01",
      eventDate: iso(2.001)
    }),
    evt({
      id: "h3",
      eventType: "Updated",
      isAddOrRemove: false,
      sentence: "Practice location: Office Email changed",
      category: "Practice Location",
      oldValue: "a@x.com",
      newValue: "b@x.com",
      recordEffectiveFrom: null,
      eventDate: iso(30),
      actorName: "MuleSoft Integration User",
      isIntegration: true,
      caseManagerId: null,
      caseManagerName: null,
      fhnaticCaseNumber: null
    })
  ]
};

async function flushPromises() {
  for (let i = 0; i < 5; i += 1) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
}

async function mount(response = LIVE_RESPONSE) {
  getHistory.mockResolvedValue(response);
  const prmPracticeLocationHistory = createElement(
    "c-prm-practice-location-history",
    { is: PrmPracticeLocationHistory }
  );
  prmPracticeLocationHistory.recordId = "0kl000000000001";
  document.body.appendChild(prmPracticeLocationHistory);
  await flushPromises();
  return prmPracticeLocationHistory;
}

const findAll = (component, selector, predicate = () => true) =>
  [...component.shadowRoot.querySelectorAll(selector)].filter(predicate);
const find = (component, selector, predicate) =>
  findAll(component, selector, predicate)[0];
const text = (el) => (el ? el.textContent.replace(/\s+/g, " ").trim() : null);
const button = (component, label) =>
  find(component, "lightning-button", (b) => b.label === label) ||
  find(component, "button", (b) => text(b) === label);
const sentences = (component) =>
  findAll(component, ".plh-sentence").map((a) => text(a));

async function switchView(component, value) {
  find(
    component,
    "lightning-radio-group",
    (g) => g.name === "viewToggle"
  ).dispatchEvent(new CustomEvent("change", { detail: { value } }));
  await flushPromises();
}

describe("c-prm-practice-location-history", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("loads live history and renders a branded header with the last change", async () => {
    const prmPracticeLocationHistory = await mount();

    expect(getHistory).toHaveBeenCalledWith({
      practiceLocationId: "0kl000000000001"
    });
    expect(text(find(prmPracticeLocationHistory, ".plh-title"))).toBe(
      "Change History"
    );
    expect(text(find(prmPracticeLocationHistory, ".plh-subtitle"))).toBe(
      "Main Street Clinic"
    );
    expect(text(find(prmPracticeLocationHistory, ".plh-last-value"))).toContain(
      "Pat Specialist"
    );
    expect(sentences(prmPracticeLocationHistory)).toEqual([
      "Practitioner Jane Doe (PCP) added",
      "Network Amerihealth PPO removed, effective 9/18/2026",
      "Practice location: Office Email changed"
    ]);
  });

  it("leads each change card with who made it and when", async () => {
    const prmPracticeLocationHistory = await mount();
    const [first, second] = findAll(prmPracticeLocationHistory, ".plh-card");

    expect(text(first.querySelector(".plh-who-name"))).toContain(
      "Pat Specialist"
    );
    expect(text(first.querySelector(".plh-avatar"))).toBe("PS");
    expect(
      first.querySelector(".plh-who-when lightning-formatted-date-time").value
    ).toBe(LIVE_RESPONSE.events[0].eventDate);
    expect(text(first.querySelector(".plh-relative"))).toBe("2 hr ago");

    expect(text(second.querySelector(".plh-who-name"))).toContain(
      "MuleSoft Integration User"
    );
    expect(text(second.querySelector(".plh-tag_integration"))).toBe(
      "Integration"
    );
    expect(text(second.querySelector(".plh-relative"))).toBe("Yesterday");
  });

  it("shows the record effective-from date, end date, Case Manager and FHNatic case number", async () => {
    const prmPracticeLocationHistory = await mount();
    const [first] = findAll(prmPracticeLocationHistory, ".plh-card");

    const refs = [...first.querySelectorAll(".plh-ref")].map((r) => ({
      label: text(r.querySelector(".plh-ref-label")),
      value: text(r.querySelector(".plh-ref-value"))
    }));
    expect(refs).toEqual([
      { label: "Case Manager", value: "IA-0001" },
      { label: "FHNatic Case #", value: "FHN-7788" }
    ]);
    expect(first.querySelector("a.plh-ref").getAttribute("href")).toBe(
      "/0iT000000000001"
    );

    const dates = [...first.querySelectorAll(".plh-date")].map((d) => ({
      label: text(d.querySelector("dt")),
      value: d.querySelector("lightning-formatted-date-time").value
    }));
    expect(dates).toEqual([
      { label: "Effective from", value: "2026-09-01" },
      { label: "Effective from", value: "2025-01-01" },
      { label: "End date", value: "2026-09-18" }
    ]);
  });

  it("collapses events from one save into one card with a summary headline", async () => {
    const prmPracticeLocationHistory = await mount();

    expect(
      findAll(prmPracticeLocationHistory, ".plh-headline").map((p) => text(p))
    ).toEqual([
      "2 changes · 1 added · 1 removed",
      "Practice location: Office Email changed"
    ]);
    const [first] = findAll(prmPracticeLocationHistory, ".plh-card");
    expect([...first.querySelectorAll(".plh-cat")].map((c) => text(c))).toEqual(
      ["Practitioners", "Networks"]
    );
    expect(
      [...first.querySelectorAll(".plh-pill")].map((p) => text(p))
    ).toEqual(["Added", "Removed"]);
  });

  it("summarises adds and removes per category and filters when a tile is clicked", async () => {
    const prmPracticeLocationHistory = await mount();
    const tiles = findAll(prmPracticeLocationHistory, ".plh-kpi").map((t) => ({
      label: text(t.querySelector(".plh-kpi-label")),
      added: text(t.querySelector(".plh-kpi-added")),
      removed: text(t.querySelector(".plh-kpi-removed")),
      total: text(t.querySelector(".plh-kpi-total"))
    }));
    expect(tiles[0]).toMatchObject({
      label: "Practitioners",
      added: "+1 added",
      removed: "−0 removed"
    });
    expect(tiles[1]).toMatchObject({
      label: "Networks",
      removed: "−1 removed"
    });
    expect(tiles[3]).toMatchObject({ label: "Field updates", total: "1" });

    find(
      prmPracticeLocationHistory,
      "button.plh-kpi",
      (b) => b.dataset.value === "Networks"
    ).click();
    await flushPromises();
    expect(sentences(prmPracticeLocationHistory)).toEqual([
      "Network Amerihealth PPO removed, effective 9/18/2026"
    ]);
  });

  it("filters by category chip and shows counts on each chip", async () => {
    const prmPracticeLocationHistory = await mount();
    const chips = findAll(prmPracticeLocationHistory, ".plh-chip").map((c) => ({
      label: text(c.querySelector(".plh-chip-label")),
      count: text(c.querySelector(".plh-chip-count"))
    }));
    expect(chips).toEqual([
      { label: "All", count: "3" },
      { label: "Practice Location", count: "1" },
      { label: "Practitioners", count: "1" },
      { label: "Networks", count: "1" },
      { label: "Taxonomies", count: "0" }
    ]);

    find(
      prmPracticeLocationHistory,
      ".plh-chip",
      (c) => c.dataset.value === "Practice Location"
    ).click();
    await flushPromises();
    expect(sentences(prmPracticeLocationHistory)).toEqual([
      "Practice location: Office Email changed"
    ]);
    expect(
      find(
        prmPracticeLocationHistory,
        ".plh-chip",
        (c) => c.dataset.value === "Practice Location"
      ).getAttribute("aria-pressed")
    ).toBe("true");
  });

  it("groups changes into sections in the By category view", async () => {
    const prmPracticeLocationHistory = await mount();
    await switchView(prmPracticeLocationHistory, "category");

    const sections = findAll(prmPracticeLocationHistory, ".plh-section").map(
      (s) => ({
        title: text(s.querySelector(".plh-section-title")),
        total: text(s.querySelector(".plh-section-total")),
        stats: [...s.querySelectorAll(".plh-stat")].map((x) => text(x)),
        rows: s.querySelectorAll(".plh-row").length
      })
    );
    expect(sections).toEqual([
      {
        title: "Practice Location",
        total: "1 change",
        stats: ["+0 added", "−0 removed", "1 updates"],
        rows: 1
      },
      {
        title: "Practitioners",
        total: "1 change",
        stats: ["+1 added", "−0 removed", "0 updates"],
        rows: 1
      },
      {
        title: "Networks",
        total: "1 change",
        stats: ["+0 added", "−1 removed", "0 updates"],
        rows: 1
      }
    ]);

    const practitionerRow = findAll(prmPracticeLocationHistory, ".plh-row")[1];
    expect(text(practitionerRow.querySelector(".plh-row-by"))).toBe(
      "by Pat Specialist"
    );
    expect(text(practitionerRow.querySelector(".plh-fhnatic"))).toBe(
      "FHN-7788"
    );

    find(prmPracticeLocationHistory, ".plh-section-head").click();
    await flushPromises();
    const [collapsed] = findAll(prmPracticeLocationHistory, ".plh-section");
    expect(collapsed.querySelectorAll(".plh-row")).toHaveLength(0);
    expect(
      collapsed.querySelector(".plh-section-head").getAttribute("aria-expanded")
    ).toBe("false");
  });

  it("badges integration users and filters them out on request", async () => {
    const prmPracticeLocationHistory = await mount();

    find(
      prmPracticeLocationHistory,
      "lightning-radio-group",
      (g) => g.name === "actorFilter"
    ).dispatchEvent(new CustomEvent("change", { detail: { value: "people" } }));
    await flushPromises();

    expect(sentences(prmPracticeLocationHistory)).toEqual([
      "Practitioner Jane Doe (PCP) added",
      "Network Amerihealth PPO removed, effective 9/18/2026"
    ]);
  });

  it("shows only adds and removes when the toggle is on", async () => {
    const prmPracticeLocationHistory = await mount();
    const toggle = find(
      prmPracticeLocationHistory,
      "lightning-input",
      (i) => i.type === "toggle"
    );
    toggle.checked = true;
    toggle.dispatchEvent(new CustomEvent("change"));
    await flushPromises();

    expect(sentences(prmPracticeLocationHistory)).toHaveLength(2);
  });

  it("filters by search text, including the FHNatic case number", async () => {
    const prmPracticeLocationHistory = await mount();
    const search = find(
      prmPracticeLocationHistory,
      "lightning-input",
      (i) => i.type === "search"
    );
    search.value = "fhn-7788";
    search.dispatchEvent(new CustomEvent("change"));
    await flushPromises();

    expect(sentences(prmPracticeLocationHistory)).toHaveLength(2);
    expect(sentences(prmPracticeLocationHistory)).not.toContain(
      "Practice location: Office Email changed"
    );
  });

  it("filters by change type", async () => {
    const prmPracticeLocationHistory = await mount();
    const changeType = find(
      prmPracticeLocationHistory,
      "lightning-combobox",
      (c) => c.label === "Change"
    );
    expect(changeType.options.map((o) => o.value)).toEqual([
      "all",
      "Added",
      "Removed",
      "Updated"
    ]);

    changeType.dispatchEvent(
      new CustomEvent("change", { detail: { value: "Removed" } })
    );
    await flushPromises();
    expect(sentences(prmPracticeLocationHistory)).toEqual([
      "Network Amerihealth PPO removed, effective 9/18/2026"
    ]);
  });

  it("hides changes outside the date range and offers all time", async () => {
    const old = evt({
      id: "h9",
      sentence: "Practitioner Old Timer added",
      eventDate: iso(24 * 200)
    });
    const prmPracticeLocationHistory = await mount({
      ...LIVE_RESPONSE,
      events: [old]
    });

    expect(sentences(prmPracticeLocationHistory)).toEqual([]);
    button(prmPracticeLocationHistory, "Show all time").click();
    await flushPromises();
    expect(sentences(prmPracticeLocationHistory)).toEqual([
      "Practitioner Old Timer added"
    ]);
    expect(text(find(prmPracticeLocationHistory, ".plh-relative"))).toBe(
      "7 mo ago"
    );
  });

  it("loads the archive on demand and merges without duplicates", async () => {
    getArchivedHistory.mockResolvedValue({
      includesArchive: true,
      categories: [],
      truncatedCategories: ["Practitioners"],
      events: [
        evt({ id: "h1", isArchived: true }),
        evt({
          id: "a1",
          sentence: "Practitioner Archived Person added",
          eventDate: iso(48),
          isArchived: true,
          actorId: "005000000000009"
        })
      ]
    });
    const prmPracticeLocationHistory = await mount();

    button(prmPracticeLocationHistory, "Load older changes (archive)").click();
    await flushPromises();

    expect(getArchivedHistory).toHaveBeenCalledWith({
      practiceLocationId: "0kl000000000001"
    });
    const shown = sentences(prmPracticeLocationHistory);
    expect(shown).toContain("Practitioner Archived Person added");
    expect(
      shown.filter((s) => s === "Practitioner Jane Doe (PCP) added")
    ).toHaveLength(1);
    expect(
      text(
        prmPracticeLocationHistory.shadowRoot.querySelector('[role="status"]')
      )
    ).toContain("Practitioners");
    expect(
      button(prmPracticeLocationHistory, "Load older changes (archive)")
    ).toBeUndefined();
  });

  it("expands a large change to show every event", async () => {
    const many = Array.from({ length: 5 }, (_, i) =>
      evt({
        id: `m${i}`,
        groupKey: "big",
        sentence: `Practitioner P${i} added`,
        eventDate: iso(2 + i / 1000)
      })
    );
    const prmPracticeLocationHistory = await mount({
      ...LIVE_RESPONSE,
      events: many
    });
    expect(sentences(prmPracticeLocationHistory)).toHaveLength(3);

    button(prmPracticeLocationHistory, "Show all 5 changes").click();
    await flushPromises();
    expect(sentences(prmPracticeLocationHistory)).toHaveLength(5);
  });

  it("switches to the table view with who, when, effective from and FHNatic columns", async () => {
    const prmPracticeLocationHistory = await mount();
    await switchView(prmPracticeLocationHistory, "table");

    const table = prmPracticeLocationHistory.shadowRoot.querySelector(
      "lightning-datatable"
    );
    expect(table.columns.map((c) => c.label)).toEqual(
      expect.arrayContaining([
        "Changed on",
        "Changed by",
        "Effective from",
        "FHNatic Case #"
      ])
    );
    expect(table.data.map((r) => r.id)).toEqual(["h1", "h2", "h3"]);
    expect(table.data[0].fhnaticCaseNumber).toBe("FHN-7788");
    expect(table.data[1].endDate).toBe("2026-09-18");
    expect(table.data[2].actorLabel).toBe(
      "MuleSoft Integration User (Integration)"
    );
  });

  it("shows an empty state that points to the archive", async () => {
    const prmPracticeLocationHistory = await mount({
      ...LIVE_RESPONSE,
      events: []
    });
    expect(text(find(prmPracticeLocationHistory, ".plh-empty-title"))).toBe(
      "No tracked changes in recent history."
    );
  });

  it("shows the server error message", async () => {
    getHistory.mockRejectedValue({ body: { message: "Insufficient access" } });
    const prmPracticeLocationHistory = createElement(
      "c-prm-practice-location-history",
      { is: PrmPracticeLocationHistory }
    );
    prmPracticeLocationHistory.recordId = "0kl000000000001";
    document.body.appendChild(prmPracticeLocationHistory);
    await flushPromises();

    expect(
      text(
        prmPracticeLocationHistory.shadowRoot.querySelector('[role="alert"]')
      )
    ).toContain("Insufficient access");
  });
});
