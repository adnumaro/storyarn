import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import MultiSelectBlock from "../../../modules/sheets/components/entities/blocks/fields/MultiSelectBlock.vue";
import TBooleanCell from "../../../modules/sheets/components/entities/blocks/fields/table/tbodyCells/TBooleanCell.vue";
import TMultiSelectCell from "../../../modules/sheets/components/entities/blocks/fields/table/tbodyCells/TMultiSelectCell.vue";
import { createMockLive } from "../../setup";

const global = { config: { globalProperties: { $live: createMockLive() } as never } };
const EMPTY = "—";

describe("read-only empty sheet values", () => {
  it("shows an em dash, not its escape sequence, for an empty multi-select block", () => {
    const wrapper = mount(MultiSelectBlock, {
      props: { block: { id: 1, type: "multi_select", config: { label: "Tags", options: [] } } },
      global,
    });

    expect(wrapper.text()).toContain(EMPTY);
    expect(wrapper.text()).not.toContain("\\u2014");
  });

  it.each([
    ["boolean", TBooleanCell],
    ["multi_select", TMultiSelectCell],
  ])("shows an em dash for an empty %s table cell", (type, component) => {
    const wrapper = mount(component, {
      props: {
        column: { id: 1, name: "Flag", slug: "flag", type, config: { options: [] } },
        row: { id: 1, name: "Row", slug: "row", cells: {} },
      },
      global,
    });

    expect(wrapper.text()).toBe(EMPTY);
  });
});
