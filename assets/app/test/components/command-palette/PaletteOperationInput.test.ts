import { afterEach, describe, expect, it } from "vitest";
import { mount, type VueWrapper } from "@vue/test-utils";
import { defineComponent, nextTick, type PropType } from "vue";
import PaletteOperationInput from "../../../components/command-palette/PaletteOperationInput.vue";
import { Command, CommandGroup, CommandItem, CommandList } from "../../../components/ui/command";
import type {
  OperationDefinition,
  OperationErrors,
  OperationValues,
} from "../../../shared/command-palette/operationCatalog";

const definition: OperationDefinition = {
  id: "variable_usages",
  domain: "navigation",
  latency: "instant",
  authorization: "view_project",
  resultType: "navigation_list",
  parameters: [
    {
      id: "scope",
      type: "scope",
      completionSource: "scope",
      required: true,
      labelKey: "palette.nav.projects",
    },
    {
      id: "variable",
      type: "variable",
      completionSource: "variable",
      required: true,
      labelKey: "palette.nav.entities",
    },
  ],
  phrase: [
    { kind: "text", textKey: "palette.nav.entities" },
    { kind: "parameter", parameterId: "scope" },
    { kind: "parameter", parameterId: "variable" },
  ],
  help: {
    labelKey: "palette.title",
    descriptionKey: "palette.description",
    exampleKey: "palette.placeholder",
    pattern: "sheets.**.?heal",
  },
};

const Harness = defineComponent({
  components: { Command, CommandGroup, CommandItem, CommandList, PaletteOperationInput },
  props: {
    definition: {
      type: Object as PropType<OperationDefinition>,
      required: true,
    },
    values: {
      type: Object as PropType<OperationValues>,
      default: () => ({}),
    },
    activeParameter: {
      type: String,
      default: null,
    },
    query: {
      type: String,
      default: "",
    },
    errors: {
      type: Object as PropType<OperationErrors>,
      default: () => ({}),
    },
    disabled: {
      type: Boolean,
      default: false,
    },
  },
  emits: ["activate", "clear", "cancel", "submit", "update:query"],
  template: `
    <Command>
      <PaletteOperationInput
        ref="composer"
        :definition="definition"
        :values="values"
        :active-parameter="activeParameter"
        :query="query"
        :errors="errors"
        :disabled="disabled"
        @activate="$emit('activate', $event)"
        @clear="$emit('clear', $event)"
        @cancel="$emit('cancel')"
        @submit="$emit('submit')"
        @update:query="$emit('update:query', $event)"
      />
      <CommandList>
        <CommandGroup>
          <CommandItem value="matching-result" search-text="matching completion">
            Matching result
          </CommandItem>
        </CommandGroup>
      </CommandList>
    </Command>
  `,
});

function mountComposer(
  overrides: {
    values?: OperationValues;
    activeParameter?: string | null;
    query?: string;
    errors?: OperationErrors;
    disabled?: boolean;
  } = {},
): VueWrapper {
  return mount(Harness, {
    attachTo: document.body,
    props: {
      definition,
      values: overrides.values ?? {},
      activeParameter: overrides.activeParameter ?? "scope",
      query: overrides.query ?? "",
      errors: overrides.errors ?? {},
      disabled: overrides.disabled ?? false,
    },
  });
}

function activeInput(wrapper: VueWrapper) {
  return wrapper.find<HTMLInputElement>("[data-slot='palette-operation-input'] input[type='text']");
}

function keydown(wrapper: VueWrapper, key: string, init: KeyboardEventInit = {}): KeyboardEvent {
  const event = new KeyboardEvent("keydown", {
    key,
    bubbles: true,
    cancelable: true,
    ...init,
  });
  activeInput(wrapper).element.dispatchEvent(event);
  return event;
}

afterEach(() => {
  document.body.innerHTML = "";
});

describe("PaletteOperationInput", () => {
  it("exposes focusActive and emits the next parameter as its auto-advance contract", async () => {
    const wrapper = mountComposer({
      values: {
        scope: { id: "project:1", value: 1, label: "Veilbreak" },
      },
    });
    const composer = wrapper.findComponent(PaletteOperationInput);

    await (
      composer.vm as unknown as {
        focusActive: () => Promise<void>;
      }
    ).focusActive();
    expect(document.activeElement).toBe(activeInput(wrapper).element);

    const event = keydown(wrapper, "Tab");
    await nextTick();

    expect(event.defaultPrevented).toBe(true);
    expect(wrapper.emitted("activate")).toEqual([["variable"]]);
  });

  it("clears only the active filled slot on Backspace", () => {
    const wrapper = mountComposer({
      values: {
        scope: { id: "project:1", value: 1, label: "Veilbreak" },
        variable: { id: "variable:2", value: "mc.health", label: "mc.health" },
      },
    });

    const event = keydown(wrapper, "Backspace");

    expect(event.defaultPrevented).toBe(true);
    expect(wrapper.emitted("clear")).toEqual([["scope"]]);
    expect(wrapper.emitted("cancel")).toBeUndefined();
  });

  it("uses horizontal arrows to move between atomic parameters when no query is being edited", async () => {
    const wrapper = mountComposer();

    const right = keydown(wrapper, "ArrowRight");
    expect(right.defaultPrevented).toBe(true);
    expect(wrapper.emitted("activate")).toEqual([["variable"]]);

    await wrapper.setProps({ activeParameter: "variable" });
    const left = keydown(wrapper, "ArrowLeft");
    expect(left.defaultPrevented).toBe(true);
    expect(wrapper.emitted("activate")?.at(-1)).toEqual(["scope"]);

    await wrapper.setProps({ query: "editing" });
    const nativeLeft = keydown(wrapper, "ArrowLeft");
    expect(nativeLeft.defaultPrevented).toBe(false);
    expect(wrapper.emitted("activate")).toHaveLength(2);
  });

  it("cancels on Backspace only at the first empty slot, while Escape always cancels", async () => {
    const wrapper = mountComposer({ activeParameter: "variable" });

    keydown(wrapper, "Backspace");
    expect(wrapper.emitted("activate")).toEqual([["scope"]]);
    expect(wrapper.emitted("cancel")).toBeUndefined();

    await wrapper.setProps({ activeParameter: "scope" });
    keydown(wrapper, "Backspace");
    expect(wrapper.emitted("cancel")).toHaveLength(1);

    await wrapper.setProps({ activeParameter: "variable" });
    keydown(wrapper, "Escape");
    expect(wrapper.emitted("cancel")).toHaveLength(2);
  });

  it("keeps an empty required parameter active without manufacturing an error", () => {
    const wrapper = mountComposer();

    const event = keydown(wrapper, "Enter");

    expect(event.defaultPrevented).toBe(true);
    expect(wrapper.emitted("activate")).toEqual([["scope"]]);
    expect(wrapper.emitted("submit")).toBeUndefined();
    expect(wrapper.find("[role='alert']").exists()).toBe(false);
  });

  it("associates a supplied validation error with the atomic slot", () => {
    const wrapper = mountComposer({
      values: {
        scope: { id: "project:gone", value: 99, label: "Deleted project" },
      },
      errors: { scope: "That project no longer exists." },
    });

    const input = activeInput(wrapper);
    const describedBy = input.attributes("aria-describedby");

    expect(input.attributes("aria-invalid")).toBe("true");
    expect(describedBy).toBeTruthy();
    expect(wrapper.get(`#${describedBy}`).attributes("role")).toBe("alert");
    expect(wrapper.get(`#${describedBy}`).text()).toBe("That project no longer exists.");
  });

  it("does not intercept template keys while an IME owns the input", () => {
    const wrapper = mountComposer();
    const input = activeInput(wrapper);
    input.element.dispatchEvent(new CompositionEvent("compositionstart", { bubbles: true }));

    for (const key of ["ArrowLeft", "ArrowRight", "Backspace", "Escape", "Enter", "Tab"]) {
      const event = keydown(wrapper, key);
      expect(event.defaultPrevented).toBe(false);
    }

    expect(wrapper.emitted("activate")).toBeUndefined();
    expect(wrapper.emitted("clear")).toBeUndefined();
    expect(wrapper.emitted("cancel")).toBeUndefined();
    expect(wrapper.emitted("submit")).toBeUndefined();
  });

  it("disables every parameter slot and ignores keyboard mutations while busy", () => {
    const wrapper = mountComposer({
      disabled: true,
      values: {
        scope: { id: "project:1", value: 1, label: "Veilbreak" },
      },
    });

    expect(activeInput(wrapper).attributes("disabled")).toBeDefined();
    expect(
      wrapper.get<HTMLButtonElement>("[data-palette-parameter='variable']").attributes("disabled"),
    ).toBeDefined();

    for (const key of ["Backspace", "Escape", "Enter", "Tab"]) {
      const event = keydown(wrapper, key);
      expect(event.defaultPrevented).toBe(false);
    }

    expect(wrapper.emitted("activate")).toBeUndefined();
    expect(wrapper.emitted("clear")).toBeUndefined();
    expect(wrapper.emitted("cancel")).toBeUndefined();
    expect(wrapper.emitted("submit")).toBeUndefined();
    expect(wrapper.emitted("update:query")).toBeUndefined();
  });

  it("synchronizes its query with Command filtering and emits query updates", async () => {
    const wrapper = mountComposer();
    const input = activeInput(wrapper);

    await input.setValue("matching");
    expect(wrapper.findAll("[data-slot='command-item']")).toHaveLength(1);
    expect(wrapper.emitted("update:query")).toEqual([["matching"]]);

    await input.setValue("absent");
    expect(wrapper.findAll("[data-slot='command-item']")).toHaveLength(0);
    expect(wrapper.emitted("update:query")?.at(-1)).toEqual(["absent"]);
  });
});
