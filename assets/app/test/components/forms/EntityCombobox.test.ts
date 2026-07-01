import { afterEach, describe, expect, it, vi } from "vitest";
import { mount } from "@vue/test-utils";
import EntityCombobox from "../../../components/forms/fields/EntityCombobox.vue";

const passthrough = { template: "<div><slot /></div>" };

const OPTIONS = Array.from({ length: 130 }, (_, index) => ({
  id: index + 1,
  name: `Entity ${String(index + 1).padStart(3, "0")}`,
}));
const OPTIONS_WITH_ACCENTED_NAME = [...OPTIONS, { id: 131, name: "Café Entity" }];
const VERY_MANY_OPTIONS = Array.from({ length: 1200 }, (_, index) => ({
  id: index + 1,
  name: `Entity ${String(index + 1).padStart(4, "0")}`,
}));

function mountIt(props: Record<string, unknown> = {}) {
  return mount(EntityCombobox, {
    props: { options: OPTIONS, selectedId: null, ...props },
    global: {
      stubs: {
        Popover: passthrough,
        PopoverTrigger: passthrough,
        PopoverContent: passthrough,
      },
    },
  });
}

describe("EntityCombobox", () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it("limits initial rendering for large option lists", () => {
    const wrapper = mountIt();

    const items = wrapper.findAllComponents({ name: "CommandItem" });
    expect(items).toHaveLength(101);
    expect(items.map((item) => item.props("value"))).toEqual([
      "__none__",
      ...OPTIONS.slice(0, 100).map((option) => option.name),
    ]);
    expect(wrapper.text()).toContain("Showing 100 of 130 results");
  });

  it("keeps the initial page visible before the first remote response", async () => {
    const wrapper = mountIt({ searchEvent: "picker_search" });

    await wrapper.find("[data-slot='command-input']").setValue("shortcut-only");

    const itemValues = wrapper
      .findAllComponents({ name: "CommandItem" })
      .map((item) => item.props("value"));

    expect(itemValues).toEqual(["__none__", ...OPTIONS.slice(0, 100).map((option) => option.name)]);
  });

  it("searches the full option list before applying the render limit", async () => {
    const wrapper = mountIt();

    await wrapper.find("[data-slot='command-input']").setValue("Entity 130");

    const itemValues = wrapper
      .findAllComponents({ name: "CommandItem" })
      .map((item) => item.props("value"));

    expect(itemValues).toContain("Entity 130");
    expect(wrapper.text()).not.toContain("No results");
  });

  it("keeps accent-insensitive search when filtering before the render limit", async () => {
    const wrapper = mountIt({ options: OPTIONS_WITH_ACCENTED_NAME });

    await wrapper.find("[data-slot='command-input']").setValue("Cafe");

    const itemValues = wrapper
      .findAllComponents({ name: "CommandItem" })
      .map((item) => item.props("value"));

    expect(itemValues).toContain("Café Entity");
    expect(wrapper.text()).not.toContain("No results");
  });

  it("continues long searches asynchronously instead of blocking on the full list", async () => {
    vi.useFakeTimers();
    const wrapper = mountIt({ options: VERY_MANY_OPTIONS });

    await wrapper.find("[data-slot='command-input']").setValue("Entity 1200");

    const initialItemValues = wrapper
      .findAllComponents({ name: "CommandItem" })
      .map((item) => item.props("value"));

    expect(initialItemValues).toEqual(["__none__"]);
    expect(wrapper.text()).toContain("Searching...");

    await vi.runAllTimersAsync();
    await wrapper.vm.$nextTick();

    const itemValues = wrapper
      .findAllComponents({ name: "CommandItem" })
      .map((item) => item.props("value"));

    expect(itemValues).toContain("Entity 1200");
    expect(wrapper.text()).not.toContain("Searching...");
  });
});
