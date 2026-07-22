import { mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vitest";
import SheetHealthStatus from "../../../../modules/sheets/components/chrome/header/SheetHealthStatus.vue";
import type { SheetHealth } from "../../../../modules/sheets/types";

const passthrough = { template: "<div><slot /></div>" };

function mountStatus(health: SheetHealth) {
  return mount(SheetHealthStatus, {
    props: { health },
    attachTo: document.body,
    global: {
      stubs: {
        Popover: {
          props: ["open"],
          emits: ["update:open"],
          template: "<div><slot /></div>",
        },
        PopoverAnchor: passthrough,
        PopoverContent: passthrough,
        PopoverTrigger: {
          template: '<button type="button"><slot /></button>',
        },
        ToolbarTooltip: passthrough,
      },
    },
  });
}

afterEach(() => {
  document.body.innerHTML = "";
  vi.restoreAllMocks();
});

describe("SheetHealthStatus", () => {
  it("counts every reason and labels each visible severity", () => {
    const wrapper = mountStatus({
      errorItems: [
        {
          blockId: 11,
          rowId: null,
          columnId: null,
          label: "Biography",
          reasons: [{ code: "missing_variable_name" }, { code: "stale_inline_reference" }],
        },
      ],
      warningItems: [
        {
          blockId: 12,
          rowId: null,
          columnId: null,
          label: "Class",
          reasons: [{ code: "empty_select_options" }],
        },
      ],
      infoItems: [
        {
          blockId: 13,
          rowId: null,
          columnId: null,
          label: "Level",
          reasons: [{ code: "no_internal_variable_usages" }],
        },
      ],
    });

    expect(wrapper.get('[data-testid="sheet-health-error-count"]').text()).toBe("2");
    expect(wrapper.get('[data-testid="sheet-health-warning-count"]').text()).toBe("1");
    expect(wrapper.get('[data-testid="sheet-health-info-count"]').text()).toBe("1");
    expect(wrapper.get('[data-testid="sheet-health-errors"]').text()).toContain("Errors");
    expect(wrapper.get('[data-testid="sheet-health-warnings"]').text()).toContain("Warnings");
    expect(wrapper.get('[data-testid="sheet-health-info"]').text()).toContain("Info");
  });

  it("navigates to a table cell and disables sheet-level findings", async () => {
    const block = document.createElement("div");
    block.id = "sheet-block-42";
    const row = document.createElement("div");
    row.dataset.sheetRowId = "7";
    const cell = document.createElement("div");
    cell.dataset.sheetColumnId = "9";
    row.appendChild(cell);
    block.appendChild(row);
    document.body.appendChild(block);

    const scrollIntoView = vi.spyOn(cell, "scrollIntoView");
    const wrapper = mountStatus({
      errorItems: [
        {
          blockId: null,
          rowId: null,
          columnId: null,
          label: "Hero",
          reasons: [{ code: "missing_sheet_shortcut" }],
        },
      ],
      warningItems: [
        {
          blockId: 42,
          rowId: 7,
          columnId: 9,
          label: "Stats · Hero · Level",
          reasons: [{ code: "required_table_cell_empty" }],
        },
      ],
      infoItems: [],
    });

    expect(wrapper.get('[data-health-severity="error"]').attributes()).toHaveProperty("disabled");
    await wrapper.get('[data-health-block-id="42"]').trigger("click");

    expect(scrollIntoView).toHaveBeenCalledWith({ behavior: "smooth", block: "center" });
    expect(cell.classList.contains("ring-2")).toBe(true);
  });

  it("shows the clean state when there are no findings", () => {
    const wrapper = mountStatus({ errorItems: [], warningItems: [], infoItems: [] });
    expect(wrapper.find('[data-testid="sheet-health-clean"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="sheet-health-trigger"]').exists()).toBe(false);
  });
});
