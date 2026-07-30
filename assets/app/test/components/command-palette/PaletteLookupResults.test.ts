import { afterEach, describe, expect, it } from "vitest";
import { mount } from "@vue/test-utils";
import { defineComponent, nextTick, type PropType } from "vue";
import PaletteLookupResults from "../../../components/command-palette/PaletteLookupResults.vue";
import { Command, CommandInput, CommandItem, CommandList } from "../../../components/ui/command";
import type { PaletteLookupResult } from "../../../shared/command-palette/lookupResults";

const results: PaletteLookupResult[] = [
  {
    id: "definition:42",
    label: "mc.jaime.health",
    detail: "Definition",
    context: "Character · Veilbreak",
    icon: "sheet",
    action: {
      kind: "navigate",
      url: "/workspaces/acme/projects/veilbreak/sheets/4",
    },
  },
  {
    id: "usage:81",
    label: "Opening sequence",
    detail: "Reads",
    context: "Flow · Veilbreak",
    icon: "flow",
    action: {
      kind: "navigate",
      url: "/workspaces/acme/projects/veilbreak/flows/7?node=81",
    },
  },
];

const Harness = defineComponent({
  components: { Command, CommandInput, CommandList, PaletteLookupResults },
  props: {
    items: {
      type: Array as PropType<PaletteLookupResult[]>,
      required: true,
    },
    disabled: {
      type: Boolean,
      default: false,
    },
    loading: {
      type: Boolean,
      default: false,
    },
    truncated: {
      type: Boolean,
      default: false,
    },
    truncatedLabel: {
      type: String,
      default: undefined,
    },
  },
  emits: ["select"],
  template: `
    <Command>
      <CommandInput />
      <CommandList>
        <PaletteLookupResults
          ref="lookupResults"
          :items="items"
          :disabled="disabled"
          :loading="loading"
          :truncated="truncated"
          :truncated-label="truncatedLabel"
          heading="References"
          @select="$emit('select', $event)"
        />
      </CommandList>
    </Command>
  `,
});

function mountResults(disabled = false) {
  return mount(Harness, {
    attachTo: document.body,
    props: { items: results, disabled },
  });
}

afterEach(() => {
  document.body.innerHTML = "";
});

describe("PaletteLookupResults", () => {
  it("renders stable navigable rows with complete accessible names", () => {
    const wrapper = mountResults();
    const definition = wrapper.get("[data-lookup-result-id='definition:42']");

    expect(definition.attributes("aria-label")).toBe(
      "mc.jaime.health, Definition, Character · Veilbreak",
    );
    expect(definition.text()).toContain("mc.jaime.health");
    expect(definition.text()).toContain("Definition");
    expect(definition.text()).toContain("Character · Veilbreak");
    expect(wrapper.find("[data-slot='command-group-heading']").text()).toBe("References");
  });

  it("emits the selected result without navigating or producing analytics itself", async () => {
    const wrapper = mountResults();
    const item = wrapper
      .findAllComponents(CommandItem)
      .find((candidate) => candidate.props("value") === "lookup-result-usage:81");

    expect(item).toBeDefined();
    item!.vm.$emit("select", new Event("select"));
    await nextTick();

    expect(wrapper.emitted("select")).toEqual([[results[1]]]);
  });

  it("participates in Command filtering through visible and contextual text", async () => {
    const wrapper = mountResults();
    const input = wrapper.get("[data-slot='command-input']");

    await input.setValue("Character");
    expect(wrapper.findAll("[data-lookup-result-id]")).toHaveLength(1);
    expect(wrapper.find("[data-lookup-result-id='definition:42']").exists()).toBe(true);

    await input.setValue("Reads");
    expect(wrapper.findAll("[data-lookup-result-id]")).toHaveLength(1);
    expect(wrapper.find("[data-lookup-result-id='usage:81']").exists()).toBe(true);
  });

  it("exposes highlight capture and restoration by stable result id", async () => {
    const wrapper = mountResults();
    const component = wrapper.findComponent(PaletteLookupResults);
    const api = component.vm as unknown as {
      highlightedResultId: () => string | null;
      highlightFirstResult: () => Promise<void>;
      restoreHighlightedResult: (resultId: string | null) => Promise<void>;
    };

    await api.highlightFirstResult();
    expect(api.highlightedResultId()).toBe("definition:42");

    await api.restoreHighlightedResult("usage:81");
    expect(api.highlightedResultId()).toBe("usage:81");
    expect(
      wrapper.get("[data-lookup-result-id='usage:81']").attributes("data-highlighted"),
    ).toBeDefined();
  });

  it("reactively disables every result and blocks selection while the caller is busy", async () => {
    const wrapper = mountResults();

    await wrapper.setProps({ disabled: true });

    for (const item of wrapper.findAll("[data-lookup-result-id]")) {
      expect(item.attributes("data-disabled")).toBeDefined();
    }

    wrapper.findAllComponents(CommandItem)[0]?.vm.$emit("select", new Event("select"));
    await nextTick();

    expect(wrapper.emitted("select")).toBeUndefined();
  });

  it("exposes bounded-result state without inventing untranslated copy", async () => {
    const wrapper = mountResults();

    await wrapper.setProps({
      truncated: true,
      truncatedLabel: "Showing the first 50 results",
      loading: true,
    });
    const component = wrapper.findComponent(PaletteLookupResults);

    expect(component.attributes("data-lookup-results-truncated")).toBe("true");
    expect(component.attributes("aria-busy")).toBe("true");
    expect(component.get("[role='status']").text()).toBe("Showing the first 50 results");
  });
});
