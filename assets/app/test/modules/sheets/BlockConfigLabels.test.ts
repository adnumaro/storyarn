import { mount } from "@vue/test-utils";
import type { Component } from "vue";
import { describe, expect, it } from "vitest";
import MultiSelectBlock from "../../../modules/sheets/components/entities/blocks/fields/MultiSelectBlock.vue";
import NumberBlock from "../../../modules/sheets/components/entities/blocks/fields/NumberBlock.vue";
import SelectBlock from "../../../modules/sheets/components/entities/blocks/fields/SelectBlock.vue";
import TextBlock from "../../../modules/sheets/components/entities/blocks/fields/TextBlock.vue";
import type { Block } from "../../../modules/sheets/types";
import { createMockLive } from "../../setup";

// The config form lives in a teleported Popover; render it inline to read it.
const passthrough = { template: "<div><slot /></div>" };

function mountBlock(component: Component, block: Block) {
  return mount(component, {
    props: { block, canEdit: true },
    global: {
      config: { globalProperties: { $live: createMockLive() } as never },
      stubs: { Popover: passthrough, PopoverTrigger: passthrough, PopoverContent: passthrough },
    },
  });
}

const cases: [string, Component, Block][] = [
  ["text", TextBlock, { id: 1, type: "text", config: { label: "Name" } }],
  ["number", NumberBlock, { id: 2, type: "number", config: { label: "Age" } }],
  ["select", SelectBlock, { id: 3, type: "select", config: { label: "Class", options: [] } }],
  [
    "multi_select",
    MultiSelectBlock,
    { id: 4, type: "multi_select", config: { label: "Tags", options: [] } },
  ],
];

describe("sheet block config labels", () => {
  it.each(cases)("%s block links every config label to its control", (_type, component, block) => {
    const wrapper = mountBlock(component, block);
    const labels = wrapper.findAll("label[for]");

    expect(labels.length).toBeGreaterThan(0);
    for (const label of labels) {
      const id = label.attributes("for");
      expect(wrapper.find(`[id="${id}"]`).exists(), `no control with id ${id}`).toBe(true);
    }
  });

  it("keeps the same ids across re-renders", async () => {
    const wrapper = mountBlock(NumberBlock, { id: 2, type: "number", config: { label: "Age" } });
    const before = wrapper.findAll("label[for]").map((label) => label.attributes("for"));

    await wrapper.setProps({ block: { id: 2, type: "number", config: { label: "Years" } } });

    const after = wrapper.findAll("label[for]").map((label) => label.attributes("for"));
    expect(after).toEqual(before);
  });
});
