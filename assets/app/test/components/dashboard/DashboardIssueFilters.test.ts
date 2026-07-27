import { mount } from "@vue/test-utils";
import { defineComponent } from "vue";
import { describe, expect, it, vi } from "vitest";
import DashboardFilterPopover from "../../../components/dashboard/DashboardFilterPopover.vue";
import DashboardIssueFilters from "../../../components/dashboard/DashboardIssueFilters.vue";
import { CommandItem } from "../../../components/ui/command";

const passthrough = { template: "<div><slot /></div>" };
const popoverStub = defineComponent({
  name: "PopoverStub",
  props: {
    open: Boolean,
  },
  emits: ["update:open"],
  template: '<div data-testid="filter-popover"><slot /></div>',
});
const contentStub = {
  template: '<div data-testid="filter-popover-content"><slot /></div>',
};

const options = {
  totals: { severity: 6, code: 4, resource: 5 },
  severities: [
    { value: "error", count: 4 },
    { value: "warning", count: 2 },
    { value: "info", count: 0 },
  ],
  codes: [
    { value: "missing_entry", count: 3 },
    { value: "unreachable_node", count: 1 },
  ],
  resources: [
    { value: "11", label: "Main flow", count: 4 },
    { value: "12", label: "Credits flow with a deliberately long name", count: 1 },
  ],
};

function mountFilters(props: Record<string, unknown> = {}) {
  return mount(DashboardIssueFilters, {
    props: {
      filters: { severity: "all", code: "all", resource: "all" },
      options,
      allResourcesLabel: "All flows",
      codeLabel: (code: string) => `Label: ${code}`,
      ...props,
    },
    global: {
      stubs: {
        Popover: popoverStub,
        PopoverTrigger: passthrough,
        PopoverContent: contentStub,
      },
    },
  });
}

function commandItem(wrapper: ReturnType<typeof mountFilters>, id: string) {
  return wrapper.findAllComponents(CommandItem).find((item) => item.attributes("id") === id)!;
}

describe("DashboardIssueFilters", () => {
  it("uses compact popup triggers with complete accessible names", () => {
    const wrapper = mountFilters();
    const filterGroup = wrapper.get('[data-testid="dashboard-issue-filters"]');
    const severity = wrapper.get('[data-testid="dashboard-issue-severity-filter"]');
    const code = wrapper.get('[data-testid="dashboard-issue-code-filter"]');
    const resource = wrapper.get('[data-testid="dashboard-issue-resource-filter"]');

    expect(filterGroup.classes()).toEqual(
      expect.arrayContaining(["flex", "flex-wrap", "items-center", "gap-2"]),
    );
    expect(filterGroup.classes()).not.toContain("grid");

    expect(severity.attributes("aria-label")).toBe("Filter by severity: All severities (6)");
    expect(code.attributes("aria-label")).toBe("Filter by issue type: All issue types (4)");
    expect(resource.attributes("aria-label")).toBe("Filter by resource: All flows (5)");

    expect(severity.classes()).toContain("sm:max-w-52");
    expect(code.classes()).toContain("sm:max-w-72");
    expect(resource.classes()).toContain("sm:max-w-64");

    for (const trigger of [severity, code, resource]) {
      expect(trigger.classes()).not.toContain("w-full");
      expect(trigger.find(".truncate").exists()).toBe(true);
    }
  });

  it("shows faceted counts, including zero, in every popup", () => {
    const wrapper = mountFilters({
      filters: { severity: "warning", code: "missing_entry", resource: "11" },
    });

    expect(wrapper.get("#dashboard-issue-severity-filter-option-warning").text()).toContain(
      "Warnings",
    );
    expect(wrapper.get("#dashboard-issue-severity-filter-option-warning").text()).toContain("2");
    expect(wrapper.get("#dashboard-issue-severity-filter-option-info").text()).toContain("0");
    expect(wrapper.get("#dashboard-issue-code-filter-option-missing_entry").text()).toContain(
      "Label: missing_entry",
    );
    expect(wrapper.get("#dashboard-issue-code-filter-option-missing_entry").text()).toContain("3");
    expect(wrapper.get("#dashboard-issue-resource-filter-option-12").text()).toContain("1");
    expect(wrapper.get("#dashboard-issue-resource-filter-option-11").text()).not.toContain("11");

    expect(
      wrapper.get("#dashboard-issue-severity-filter-option-warning").get("svg").classes(),
    ).toContain("opacity-100");
    expect(
      wrapper.get("#dashboard-issue-severity-filter-option-error").get("svg").classes(),
    ).toContain("opacity-0");
    expect(wrapper.findAll("[data-slot='command-input']")).toHaveLength(2);
  });

  it("bounds large resource lists and searches them in chunks", async () => {
    vi.useFakeTimers();

    try {
      const resources = Array.from({ length: 1_200 }, (_, index) => {
        const number = index + 1;
        return {
          value: `id-${number}`,
          label: `Resource ${number}`,
          count: number,
        };
      });
      const wrapper = mountFilters({
        filters: { severity: "all", code: "all", resource: "id-1199" },
        options: {
          ...options,
          totals: { ...options.totals, resource: 1_200 },
          resources,
        },
      });
      const resourcePopover = wrapper.findAllComponents(DashboardFilterPopover).at(2)!;
      const initialItems = wrapper
        .findAllComponents(CommandItem)
        .filter((item) =>
          item.attributes("id")?.startsWith("dashboard-issue-resource-filter-option-"),
        );

      expect(initialItems).toHaveLength(101);
      expect(resourcePopover.find("#dashboard-issue-resource-filter-option-id-1199").exists()).toBe(
        true,
      );
      expect(resourcePopover.find("#dashboard-issue-resource-filter-option-id-1200").exists()).toBe(
        false,
      );
      expect(resourcePopover.text()).toContain("Showing 101 of 1201 results");

      await resourcePopover.get("[data-slot='command-input']").setValue("id-1200");
      await wrapper.vm.$nextTick();
      await vi.runAllTimersAsync();
      await wrapper.vm.$nextTick();

      expect(resourcePopover.find("#dashboard-issue-resource-filter-option-id-1199").exists()).toBe(
        false,
      );
      expect(resourcePopover.find("#dashboard-issue-resource-filter-option-id-1200").exists()).toBe(
        true,
      );

      await resourcePopover.get("[data-slot='command-input']").setValue("not-a-resource");
      await wrapper.vm.$nextTick();
      await vi.runAllTimersAsync();
      await wrapper.vm.$nextTick();

      expect(resourcePopover.text()).toContain("No results");
    } finally {
      vi.useRealTimers();
    }
  });

  it("keeps popup content bounded and option labels ellipsized", () => {
    const wrapper = mountFilters();

    for (const content of wrapper.findAll('[data-testid="filter-popover-content"]')) {
      expect(content.classes()).toContain("max-w-[calc(100vw-2rem)]");
      expect(content.classes()).toContain("overflow-hidden");
    }

    expect(
      wrapper
        .get("#dashboard-issue-resource-filter-option-12")
        .get("span.min-w-0.flex-1")
        .classes(),
    ).toContain("truncate");
  });

  it("binds current values and emits the unchanged filter event contract", () => {
    const wrapper = mountFilters({
      filters: { severity: "warning", code: "missing_entry", resource: "11" },
    });
    const popovers = wrapper.findAllComponents(DashboardFilterPopover);

    expect(popovers.map((popover) => popover.props("modelValue"))).toEqual([
      "warning",
      "missing_entry",
      "11",
    ]);

    commandItem(wrapper, "dashboard-issue-severity-filter-option-error").vm.$emit(
      "select",
      new Event("select"),
    );
    commandItem(wrapper, "dashboard-issue-code-filter-option-unreachable_node").vm.$emit(
      "select",
      new Event("select"),
    );
    commandItem(wrapper, "dashboard-issue-resource-filter-option-12").vm.$emit(
      "select",
      new Event("select"),
    );

    expect(wrapper.emitted("change")).toEqual([
      [{ filter: "severity", value: "error" }],
      [{ filter: "code", value: "unreachable_node" }],
      [{ filter: "resource", value: "12" }],
    ]);
  });

  it("does not emit an unchanged value", () => {
    const wrapper = mountFilters();

    commandItem(wrapper, "dashboard-issue-severity-filter-option-all").vm.$emit(
      "select",
      new Event("select"),
    );

    expect(wrapper.emitted("change")).toBeUndefined();
  });

  it("keeps an open popup interactive while marking background refreshes as busy", async () => {
    const wrapper = mountFilters();
    const codePopover = wrapper.findAllComponents(DashboardFilterPopover).at(1)!;
    const popover = codePopover.findComponent({ name: "PopoverStub" });

    popover.vm.$emit("update:open", true);
    await wrapper.vm.$nextTick();

    expect(wrapper.get("#dashboard-issue-code-filter").attributes("aria-expanded")).toBe("true");

    await wrapper.setProps({ busy: true });

    expect(wrapper.attributes("aria-busy")).toBe("true");
    expect(
      wrapper
        .findAllComponents(DashboardFilterPopover)
        .every((filterPopover) => filterPopover.props("disabled") === false),
    ).toBe(true);
    expect(wrapper.get("#dashboard-issue-code-filter").attributes("aria-expanded")).toBe("true");

    for (const id of [
      "dashboard-issue-severity-filter",
      "dashboard-issue-code-filter",
      "dashboard-issue-resource-filter",
    ]) {
      expect(wrapper.get(`#${id}`).attributes("disabled")).toBeUndefined();
    }
  });
});
