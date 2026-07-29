import { enableAutoUnmount, flushPromises, mount } from "@vue/test-utils";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { defineComponent, nextTick, type App } from "vue";
import CommandPalette from "../../../components/command-palette/CommandPalette.vue";
import { Command, CommandItem } from "../../../components/ui/command";
import { liveNavigate } from "../../../shared/navigation/liveNavigate";

vi.mock("../../../shared/navigation/liveNavigate", () => ({
  liveNavigate: vi.fn(),
}));
import {
  paletteGroups,
  registerPaletteCommands,
  resetPaletteRegistry,
  type PaletteCommand,
} from "../../../shared/command-palette/registry";
import type { AILaunchCommand } from "../../../shared/command-palette/aiCommands";
import type {
  OperationCompletionMode,
  OperationCompletionSource,
  OperationDefinition,
  OperationParameterType,
  OperationResultType,
} from "../../../shared/command-palette/operationCatalog";
import type { LiveInterface } from "../../../shared/composables/useLive";
import { createMockLive, setTestLocale } from "../../setup";

// Passthrough that keeps the REAL <Command> so CommandInput/CommandItem/
// PaletteEmpty get their context, while skipping the reka Dialog portal.
const CommandDialogStub = defineComponent({
  name: "CommandDialog",
  components: { Command },
  props: {
    open: { type: Boolean, default: false },
    title: { type: String, default: "" },
    description: { type: String, default: "" },
    disableFilter: { type: Boolean, default: false },
  },
  emits: ["update:open", "escapeKeyDown"],
  template: `<div v-if="open" data-testid="palette-dialog" @keydown.esc="$emit('escapeKeyDown', $event)"><Command :disable-filter="disableFilter"><slot /></Command></div>`,
});

function livePlugin(live: LiveInterface) {
  return {
    install(app: App) {
      app.config.globalProperties.$live = live;
    },
  };
}

function mountPalette(operationCatalog: OperationDefinition[] = [], projectContext = false) {
  const live = createMockLive();
  vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
    if (!callback) return;

    if (event === "palette_nav") {
      callback({ token: payload?.token as number, groups: [] });
    }

    if (event === "palette_create_targets") {
      callback({
        token: payload?.token as number,
        projects: [{ id: 11, label: "Veilbreak", context: "Acme" }],
      });
    }

    if (event === "palette_operation_options") {
      callback({ token: payload?.token as number, items: [] });
    }
  });
  const wrapper = mount(CommandPalette, {
    attachTo: document.body,
    props: { operationCatalog, projectContext },
    global: {
      plugins: [livePlugin(live)],
      provide: { _live_vue: live },
      stubs: { CommandDialog: CommandDialogStub },
    },
  });

  return { live, wrapper };
}

const gotoOperation: OperationDefinition = {
  id: "goto",
  domain: "navigation",
  parameters: [
    {
      id: "destination",
      type: "destination",
      completionSource: "navigation",
      completionMode: "server",
      required: true,
      labelKey: "palette.operations.goto.parameters.destination",
    },
  ],
  latency: "interactive",
  authorization: "view",
  requiresProject: false,
  resultType: "navigation",
  phrase: [
    { kind: "text", textKey: "palette.operations.goto.phrase.prefix" },
    { kind: "parameter", parameterId: "destination" },
  ],
  help: {
    labelKey: "palette.operations.goto.label",
    descriptionKey: "palette.operations.goto.description",
    exampleKey: "palette.operations.goto.example",
    pattern: null,
  },
};

const createOperation: OperationDefinition = {
  id: "create",
  domain: "actions",
  parameters: [
    {
      id: "entity_type",
      type: "entity_type",
      completionSource: "entity_types",
      completionMode: "client",
      required: true,
      labelKey: "palette.operations.create.parameters.entity_type",
    },
    {
      id: "project",
      type: "project",
      completionSource: "editable_projects",
      completionMode: "client",
      required: true,
      labelKey: "palette.operations.create.parameters.project",
    },
  ],
  latency: "instant",
  authorization: "edit_content",
  requiresProject: false,
  resultType: "mutation",
  phrase: [
    { kind: "text", textKey: "palette.operations.create.phrase.prefix" },
    { kind: "parameter", parameterId: "entity_type" },
    { kind: "text", textKey: "palette.operations.create.phrase.between" },
    { kind: "parameter", parameterId: "project" },
  ],
  help: {
    labelKey: "palette.operations.create.label",
    descriptionKey: "palette.operations.create.description",
    exampleKey: "palette.operations.create.example",
    pattern: null,
  },
};

function singleParameterOperation(
  id: "delete" | "run_command" | "open_view",
  parameterId: OperationParameterType,
  completionSource: OperationCompletionSource,
  completionMode: OperationCompletionMode,
  resultType: OperationResultType,
): OperationDefinition {
  return {
    id,
    domain: "actions",
    parameters: [
      {
        id: parameterId,
        type: parameterId,
        completionSource,
        completionMode,
        required: true,
        labelKey: `palette.operations.${id}.parameters.${parameterId}`,
      },
    ],
    latency: id === "delete" ? "interactive" : "instant",
    authorization: id === "delete" ? "edit_content" : "contextual",
    requiresProject: false,
    resultType,
    phrase: [
      { kind: "text", textKey: `palette.operations.${id}.phrase.prefix` },
      { kind: "parameter", parameterId },
    ],
    help: {
      labelKey: `palette.operations.${id}.label`,
      descriptionKey: `palette.operations.${id}.description`,
      exampleKey: `palette.operations.${id}.example`,
      pattern: null,
    },
  };
}

const deleteOperation = singleParameterOperation(
  "delete",
  "entity",
  "deletable_entities",
  "server",
  "mutation",
);
const runCommandOperation = singleParameterOperation(
  "run_command",
  "command",
  "commands",
  "client",
  "command",
);
const openViewOperation = singleParameterOperation(
  "open_view",
  "destination",
  "views",
  "client",
  "navigation",
);

function referenceOperation(
  id: "variable_definition" | "variable_usages" | "entity_usages" | "flow_callers",
  parameterId: "variable" | "entity" | "flow",
  completionSource: "sheet_variables" | "reference_entities" | "flows",
): OperationDefinition {
  return {
    id,
    domain: "references",
    parameters: [
      {
        id: parameterId,
        type: parameterId,
        completionSource,
        completionMode: "server",
        required: true,
        labelKey: `palette.operations.${id}.parameters.${parameterId}`,
      },
    ],
    latency: "instant",
    authorization: "view",
    requiresProject: true,
    resultType: "lookup",
    phrase: [
      { kind: "text", textKey: `palette.operations.${id}.phrase.prefix` },
      { kind: "parameter", parameterId },
    ],
    help: {
      labelKey: `palette.operations.${id}.label`,
      descriptionKey: `palette.operations.${id}.description`,
      exampleKey: `palette.operations.${id}.example`,
      pattern: id === "variable_definition" ? "mc.jaime.health" : null,
    },
  };
}

const variableDefinitionOperation = referenceOperation(
  "variable_definition",
  "variable",
  "sheet_variables",
);
const variableUsagesOperation = referenceOperation(
  "variable_usages",
  "variable",
  "sheet_variables",
);

function pressPaletteShortcut(init: KeyboardEventInit = { ctrlKey: true }) {
  document.dispatchEvent(new KeyboardEvent("keydown", { key: "k", bubbles: true, ...init }));
}

function command(id: string, run: () => void | Promise<void> = () => undefined): PaletteCommand {
  return {
    id,
    labelKey: `label.${id}`,
    groupKey: "palette.groups.navigation",
    run,
  };
}

function aiLaunchCommand(overrides: Partial<AILaunchCommand> = {}): PaletteCommand {
  return {
    kind: "ai",
    mode: "launch",
    id: "ai.contract.launch",
    taskId: "contract.echo",
    label: "Configure AI task",
    groupKey: "palette.groups.actions",
    context: { surface: "flows", selection: null },
    availability: { state: "ready" },
    destination: { type: "none" },
    cost: { kind: "deferred_to_preflight" },
    launch: vi.fn().mockResolvedValue({ status: "launched" }),
    ...overrides,
  };
}

describe("CommandPalette", () => {
  enableAutoUnmount(afterEach);

  beforeEach(() => {
    setTestLocale("en");
    resetPaletteRegistry();
    localStorage.clear();
    vi.mocked(liveNavigate).mockClear();
  });

  afterEach(() => {
    vi.useRealTimers();
    document.body.innerHTML = "";
  });

  it("opens with Ctrl+K and tracks palette_opened with the primary surface", async () => {
    registerPaletteCommands("flows", [command("flows.a")]);
    const { live, wrapper } = mountPalette();

    pressPaletteShortcut({ ctrlKey: true });
    await nextTick();

    expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(true);
    expect(live.pushEvent).toHaveBeenCalledWith("palette_opened", { surface: "flows" }, undefined);
  });

  it("opens with Meta+K (macOS binding)", async () => {
    const { wrapper } = mountPalette();

    pressPaletteShortcut({ metaKey: true });
    await nextTick();

    expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(true);
  });

  it("toggles closed when the shortcut fires while open", async () => {
    const { wrapper } = mountPalette();

    pressPaletteShortcut();
    await nextTick();
    pressPaletteShortcut();
    await nextTick();

    expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(false);
  });

  it("the shortcut closes while the palette input owns focus", async () => {
    const { wrapper } = mountPalette();

    pressPaletteShortcut();
    await nextTick();
    const input = wrapper.find<HTMLInputElement>("[data-slot='command-input']");
    input.element.focus();
    input.element.dispatchEvent(
      new KeyboardEvent("keydown", { key: "k", ctrlKey: true, bubbles: true }),
    );
    await nextTick();

    expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(false);
  });

  it("does not stack on top of another open dialog", async () => {
    const { wrapper } = mountPalette();
    const existingDialog = document.createElement("div");
    existingDialog.dataset.slot = "dialog-content";
    existingDialog.dataset.state = "open";
    document.body.appendChild(existingDialog);

    pressPaletteShortcut();
    await nextTick();

    expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(false);
  });

  it("does not open while an input is focused", async () => {
    const { wrapper } = mountPalette();
    const input = document.createElement("input");
    document.body.appendChild(input);
    input.focus();

    input.dispatchEvent(new KeyboardEvent("keydown", { key: "k", ctrlKey: true, bubbles: true }));
    await nextTick();

    expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(false);
  });

  it("renders only commands from live registrations, grouped with headings", async () => {
    registerPaletteCommands("flows", [command("flows.a")]);
    const unregisterSheets = registerPaletteCommands("sheets", [command("sheets.b")]);
    unregisterSheets();

    const { wrapper } = mountPalette();
    pressPaletteShortcut();
    await nextTick();

    const values = wrapper.findAllComponents(CommandItem).map((item) => item.props("value"));
    expect(values).toContain("flows.a");
    expect(values).not.toContain("sheets.b");
    expect(wrapper.find("[data-slot='command-group-heading']").text()).toBe("Navigation");
  });

  it("renders generated help on open and filters operations by their descriptions", async () => {
    const { wrapper } = mountPalette([gotoOperation, createOperation]);
    pressPaletteShortcut();
    await nextTick();

    expect(wrapper.text()).toContain("What Storyarn can do");
    expect(wrapper.find("[data-operation-id='goto']").text()).toContain(
      "Open a workspace, project, sheet, flow or scene by name.",
    );
    expect(wrapper.find("[data-operation-id='goto']").text()).toContain("Go to Chapter 2");

    await wrapper.find("[data-slot='command-input']").setValue("workspace");
    await nextTick();

    expect(wrapper.find("[data-operation-id='goto']").exists()).toBe(true);
    expect(wrapper.find("[data-operation-id='create']").exists()).toBe(false);

    await wrapper.find("[data-slot='command-input']").setValue("help");
    await nextTick();

    expect(wrapper.find("[data-operation-id='goto']").exists()).toBe(true);
    expect(wrapper.find("[data-operation-id='create']").exists()).toBe(true);
  });

  it("keeps the canonical catalog visible and explains why contextual operations are unavailable", async () => {
    const { live, wrapper } = mountPalette([
      gotoOperation,
      createOperation,
      deleteOperation,
      runCommandOperation,
      openViewOperation,
    ]);
    vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
      if (!callback) return;

      if (event === "palette_nav") {
        callback({ token: payload?.token as number, groups: [] });
      } else if (event === "palette_create_targets") {
        callback({ token: payload?.token as number, projects: [] });
      }
    });

    pressPaletteShortcut();
    await nextTick();

    const expectedAvailability: Record<string, { available: string; reason?: string }> = {
      goto: { available: "true" },
      create: {
        available: "false",
        reason: "Requires edit access to at least one project.",
      },
      delete: {
        available: "false",
        reason: "Requires edit access to at least one project.",
      },
      run_command: {
        available: "false",
        reason: "No commands are available in this view.",
      },
      open_view: {
        available: "false",
        reason: "No views are available in this context.",
      },
    };

    for (const [operationId, expected] of Object.entries(expectedAvailability)) {
      const item = wrapper.get(`[data-operation-id="${operationId}"]`);
      expect(item.attributes("data-operation-available")).toBe(expected.available);
      if (expected.reason) expect(item.text()).toContain(expected.reason);
    }

    selectItem(wrapper, "operation-create");
    await nextTick();
    expect(wrapper.find("[data-slot='palette-operation-input']").exists()).toBe(false);
  });

  it("replaces the checking reason when an operation remains unavailable", async () => {
    const { live, wrapper } = mountPalette([createOperation]);
    let resolveCreateTargets!: () => void;

    vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
      if (!callback) return;

      if (event === "palette_nav") {
        callback({ token: payload?.token as number, groups: [] });
      } else if (event === "palette_create_targets") {
        const token = payload?.token as number;
        resolveCreateTargets = () => callback({ token, projects: [] });
      }
    });

    pressPaletteShortcut();
    await nextTick();

    const operation = () => wrapper.get("[data-operation-id='create']");
    expect(operation().text()).toContain("Checking availability…");
    expect(operation().attributes("title")).toBe("Checking availability…");

    resolveCreateTargets();
    await nextTick();

    expect(operation().text()).toContain("Requires edit access to at least one project.");
    expect(operation().text()).not.toContain("Checking availability…");
    expect(operation().attributes("title")).toBe("Requires edit access to at least one project.");
  });

  it("reactively invalidates cached contextual availability when local commands change", async () => {
    const { wrapper } = mountPalette([runCommandOperation]);
    pressPaletteShortcut();
    await nextTick();

    const operation = () => wrapper.get("[data-operation-id='run_command']");
    expect(operation().attributes("data-operation-available")).toBe("false");

    const unregister = registerPaletteCommands("flows", [command("flows.fit")]);
    await nextTick();
    expect(paletteGroups.value.flatMap((group) => group.commands).map(({ id }) => id)).toContain(
      "flows.fit",
    );
    await nextTick();
    expect(operation().attributes("data-operation-available")).toBe("true");

    unregister();
    await nextTick();
    expect(operation().attributes("data-operation-available")).toBe("false");
  });

  it("explains an empty delete picker after availability has been confirmed", async () => {
    const { live, wrapper } = mountPalette([deleteOperation]);
    vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
      if (!callback) return;

      if (event === "palette_nav") {
        callback({ token: payload?.token as number, groups: [] });
      } else if (event === "palette_create_targets") {
        callback({
          token: payload?.token as number,
          projects: [{ id: 11, label: "Veilbreak", context: "Acme" }],
        });
      } else if (event === "palette_operation_options") {
        callback({ token: payload?.token as number, items: [] });
      }
    });

    pressPaletteShortcut();
    await nextTick();
    selectItem(wrapper, "operation-delete");
    await nextTick();

    expect(wrapper.text()).toContain("No sheets, flows or scenes are available to delete");
    expect(wrapper.text()).not.toContain("No matching options");
  });

  it("uses locale-owned help keywords instead of leaking keywords from another locale", async () => {
    const { wrapper } = mountPalette([gotoOperation]);
    pressPaletteShortcut();
    await nextTick();

    await wrapper.find("[data-slot='command-input']").setValue("ayuda");
    await nextTick();

    expect(wrapper.text()).not.toContain("What Storyarn can do");
  });

  it("builds goto through an atomic slot and navigates only after explicit submit", async () => {
    const { live, wrapper } = mountPalette([gotoOperation]);
    vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
      if (!callback) return;

      if (event === "palette_nav") {
        callback({ token: payload?.token as number, groups: [] });
      } else if (event === "palette_create_targets") {
        callback({ token: payload?.token as number, projects: [] });
      } else if (event === "palette_operation_options") {
        callback({
          token: payload?.token as number,
          items: [
            {
              id: "nav.project.41",
              value: "/workspaces/acme/projects/veilbreak",
              label: "Veilbreak",
              context: "Acme",
            },
          ],
        });
      }
    });

    pressPaletteShortcut();
    await nextTick();
    selectItem(wrapper, "operation-goto");
    await flushPromises();

    expect(wrapper.find("[data-slot='palette-operation-input']").text()).toContain("Go to");
    expect(wrapper.find("[data-slot='command-item'][data-highlighted]").text()).toContain(
      "Veilbreak",
    );
    expect(live.pushEvent).toHaveBeenCalledWith(
      "palette_operation_options",
      expect.objectContaining({
        operation_id: "goto",
        parameter_id: "destination",
        query: "",
      }),
      expect.any(Function),
    );

    selectItem(wrapper, "operation-option-nav.project.41");
    await nextTick();
    expect(liveNavigate).not.toHaveBeenCalled();

    await wrapper
      .find("[data-slot='palette-operation-input'] input")
      .trigger("keydown", { key: "Enter" });
    await nextTick();

    expect(liveNavigate).toHaveBeenCalledWith("/workspaces/acme/projects/veilbreak");
    expect(localStorage.getItem("storyarn.command-palette.recent-operations.v1")).toBe('["goto"]');
    expect(
      vi
        .mocked(live.pushEvent)
        .mock.calls.filter(([event]) =>
          [
            "palette_operation_selected",
            "palette_operation_completed",
            "palette_operation_abandoned",
          ].includes(event),
        ),
    ).toEqual([
      ["palette_operation_selected", { operation_id: "goto", surface: "global" }, undefined],
      ["palette_operation_completed", { operation_id: "goto", surface: "global" }, undefined],
    ]);
  });

  it("keeps reference operations visible but unavailable outside a project", async () => {
    const { wrapper } = mountPalette([variableDefinitionOperation]);

    pressPaletteShortcut();
    await nextTick();

    const operation = wrapper.get("[data-operation-id='variable_definition']");
    expect(operation.attributes("data-operation-available")).toBe("false");
    expect(operation.text()).toContain("Open a project to use reference lookups.");

    selectItem(wrapper, "operation-variable_definition");
    await nextTick();
    expect(wrapper.find("[data-slot='palette-operation-input']").exists()).toBe(false);
  });

  it("derives project requirements from the reference-operation contract", async () => {
    const futureReferenceOperation: OperationDefinition = {
      ...variableDefinitionOperation,
      id: "future_reference_lookup",
    };
    const { wrapper } = mountPalette([futureReferenceOperation]);

    pressPaletteShortcut();
    await nextTick();

    const operation = wrapper.get("[data-operation-id='future_reference_lookup']");
    const availability = operation.attributes("data-operation-available");
    selectItem(wrapper, "operation-future_reference_lookup");
    await nextTick();
    const openedTemplate = wrapper.find("[data-slot='palette-operation-input']").exists();
    pressPaletteShortcut();
    await nextTick();

    expect(availability).toBe("false");
    expect(openedTemplate).toBe(false);
  });

  it("runs a guided reference lookup with an opaque target and opens an authorized result", async () => {
    const { live, wrapper } = mountPalette([variableUsagesOperation], true);

    vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
      if (!callback) return;

      if (event === "palette_nav") {
        callback({ token: payload?.token as number, groups: [] });
      } else if (event === "palette_create_targets") {
        callback({ token: payload?.token as number, projects: [] });
      } else if (event === "palette_operation_options") {
        callback({
          token: payload?.token as number,
          items: [
            {
              id: "variable:mc.jaime.health",
              value: { block_id: 9, qualified_ref: "mc.jaime.health" },
              label: "mc.jaime.health",
              context: "Characters · Jaime",
            },
          ],
        });
      } else if (event === "palette_reference_lookup") {
        callback({
          token: payload?.token as number,
          items: [
            {
              id: "flow-node:31",
              kind: "read",
              type: "flow",
              label: "Check Jaime health",
              context: "Opening",
              url: "/workspaces/acme/projects/veilbreak/flows/opening?highlight=node:31",
            },
          ],
          truncated: false,
        });
      }
    });

    pressPaletteShortcut();
    await nextTick();
    selectItem(wrapper, "operation-variable_usages");
    await nextTick();
    selectItem(wrapper, "operation-option-variable:mc.jaime.health");
    await nextTick();
    selectItem(wrapper, "operation.execute");
    await flushPromises();

    expect(live.pushEvent).toHaveBeenCalledWith(
      "palette_reference_lookup",
      {
        operation_id: "variable_usages",
        target: { block_id: 9, qualified_ref: "mc.jaime.health" },
        token: expect.any(Number),
      },
      expect.any(Function),
    );
    expect(wrapper.find("[data-lookup-result-id='flow-node:31']").text()).toContain(
      "Check Jaime health",
    );
    expect(wrapper.find("[data-slot='command-input']").exists()).toBe(false);

    await wrapper.get('[data-testid="palette-lookup-header"] button').trigger("click");
    await nextTick();
    selectItem(wrapper, "operation.execute");
    await flushPromises();

    const lifecycleEvents = vi
      .mocked(live.pushEvent)
      .mock.calls.filter(([event]) =>
        ["palette_operation_selected", "palette_operation_completed"].includes(event),
      )
      .map(([event]) => event);
    expect(lifecycleEvents).toEqual([
      "palette_operation_selected",
      "palette_operation_completed",
      "palette_operation_selected",
      "palette_operation_completed",
    ]);

    selectItem(wrapper, "lookup-result-flow-node:31");
    await nextTick();

    expect(liveNavigate).toHaveBeenCalledWith(
      "/workspaces/acme/projects/veilbreak/flows/opening?highlight=node:31",
    );
    expect(live.pushEvent).toHaveBeenCalledWith(
      "palette_command_executed",
      { command_id: "reference.open", surface: "global" },
      undefined,
    );
    expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(false);

    const analyticsPayloads = vi
      .mocked(live.pushEvent)
      .mock.calls.filter(([event]) =>
        [
          "palette_operation_selected",
          "palette_operation_completed",
          "palette_command_executed",
        ].includes(event),
      )
      .map(([, payload]) => JSON.stringify(payload));
    expect(analyticsPayloads.every((payload) => !payload.includes("flow-node:31"))).toBe(true);
    expect(analyticsPayloads.every((payload) => !payload.includes("mc.jaime.health"))).toBe(true);
  });

  it("ignores a guided reference reply after returning to its operation", async () => {
    const { live, wrapper } = mountPalette([variableDefinitionOperation], true);
    let resolveLookup: (() => void) | undefined;

    vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
      if (!callback) return;

      if (event === "palette_nav") {
        callback({ token: payload?.token as number, groups: [] });
      } else if (event === "palette_create_targets") {
        callback({ token: payload?.token as number, projects: [] });
      } else if (event === "palette_operation_options") {
        callback({
          token: payload?.token as number,
          items: [
            {
              id: "variable:mc.jaime.health",
              value: { block_id: 9, qualified_ref: "mc.jaime.health" },
              label: "mc.jaime.health",
            },
          ],
        });
      } else if (event === "palette_reference_lookup") {
        const token = payload?.token as number;
        resolveLookup = () =>
          callback({
            token,
            items: [
              {
                id: "sheet-block:9",
                kind: "definition",
                type: "sheet",
                label: "Health",
                url: "/sheets/characters?highlight=block:9",
              },
            ],
          });
      }
    });

    pressPaletteShortcut();
    await nextTick();
    selectItem(wrapper, "operation-variable_definition");
    await nextTick();
    selectItem(wrapper, "operation-option-variable:mc.jaime.health");
    await nextTick();
    selectItem(wrapper, "operation.execute");
    await nextTick();

    await wrapper.get('[data-testid="palette-lookup-header"] button').trigger("click");
    await nextTick();
    resolveLookup!();
    await nextTick();

    expect(wrapper.find("[data-slot='palette-operation-input']").exists()).toBe(true);
    expect(wrapper.find("[data-lookup-result-id='sheet-block:9']").exists()).toBe(false);
  });

  it("keeps a dotted shortcut navigation result alongside the reference-pattern door", async () => {
    vi.useFakeTimers();
    const { live, wrapper } = mountPalette([gotoOperation, variableDefinitionOperation], true);

    vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
      if (!callback) return;

      if (event === "palette_nav") {
        callback({
          token: payload?.token as number,
          groups:
            payload?.query === "mc.jaime"
              ? [
                  {
                    key: "sheets",
                    items: [
                      {
                        id: "nav.sheet.7",
                        type: "sheet",
                        label: "Jaime",
                        shortcut: "mc.jaime",
                        url: "/sheets/7",
                      },
                    ],
                  },
                ]
              : [],
        });
      } else if (event === "palette_create_targets") {
        callback({ token: payload?.token as number, projects: [] });
      } else if (event === "palette_reference_pattern") {
        callback({
          token: payload?.token as number,
          items: [],
          truncated: false,
        });
      }
    });

    pressPaletteShortcut();
    await nextTick();
    await wrapper.find("[data-slot='command-input']").setValue("mc.jaime");
    await vi.advanceTimersByTimeAsync(200);
    await nextTick();

    const calls = vi.mocked(live.pushEvent).mock.calls;
    const calledPattern = calls.some(
      ([event, payload]) =>
        event === "palette_reference_pattern" && payload?.pattern === "mc.jaime",
    );
    const calledNavigation = calls.some(
      ([event, payload]) => event === "palette_nav" && payload?.query === "mc.jaime",
    );
    const values = itemValues(wrapper);
    const text = wrapper.text();
    pressPaletteShortcut();
    await nextTick();

    expect(calledPattern).toBe(true);
    expect(calledNavigation).toBe(true);
    expect(values).toContain("nav.sheet.7");
    expect(text).not.toContain("No references found");
  });

  it("blocks stale dotted-shortcut navigation while its replacement request is pending", async () => {
    vi.useFakeTimers();
    const { live, wrapper } = mountPalette([gotoOperation, variableDefinitionOperation], true);
    let resolveReplacementNavigation: (() => void) | undefined;

    const groups = [
      {
        key: "sheets",
        items: [
          {
            id: "nav.sheet.7",
            type: "sheet",
            label: "Jaime",
            shortcut: "mc.jaime",
            url: "/sheets/7",
          },
        ],
      },
    ];

    vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
      if (!callback) return;

      if (event === "palette_nav") {
        const reply = () => callback({ token: payload?.token as number, groups });

        if (payload?.query === "mc.jaime.health") {
          resolveReplacementNavigation = reply;
        } else {
          reply();
        }
      } else if (event === "palette_create_targets") {
        callback({ token: payload?.token as number, projects: [] });
      } else if (event === "palette_reference_pattern") {
        callback({
          token: payload?.token as number,
          items: [],
          truncated: false,
        });
      }
    });

    pressPaletteShortcut();
    await nextTick();
    const input = wrapper.find("[data-slot='command-input']");
    await input.setValue("mc.jaime");
    await vi.advanceTimersByTimeAsync(200);
    await nextTick();

    const readyItem = wrapper
      .findAllComponents(CommandItem)
      .find((candidate) => candidate.props("value") === "nav.sheet.7");
    expect(readyItem).toBeDefined();

    await input.setValue("mc.jaime.health");
    await vi.advanceTimersByTimeAsync(200);
    await nextTick();

    const pendingItem = wrapper
      .findAllComponents(CommandItem)
      .find((candidate) => candidate.props("value") === "nav.sheet.7");
    expect(pendingItem).toBeDefined();
    expect(pendingItem!.vm).not.toBe(readyItem!.vm);
    expect(pendingItem!.props("disabled")).toBe(true);

    selectItem(wrapper, "nav.sheet.7");
    expect(liveNavigate).not.toHaveBeenCalled();

    resolveReplacementNavigation!();
    await nextTick();

    const restoredItem = wrapper
      .findAllComponents(CommandItem)
      .find((candidate) => candidate.props("value") === "nav.sheet.7");
    expect(restoredItem).toBeDefined();
    expect(restoredItem!.vm).not.toBe(pendingItem!.vm);
    expect(restoredItem!.props("disabled")).toBe(false);

    selectItem(wrapper, "nav.sheet.7");
    await nextTick();
    expect(liveNavigate).toHaveBeenCalledWith("/sheets/7");
  });

  it("treats multi-word navigation text with a dotted first token as normal search", async () => {
    vi.useFakeTimers();
    const { live, wrapper } = mountPalette([gotoOperation, variableDefinitionOperation], true);

    vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
      if (!callback) return;

      if (event === "palette_nav") {
        callback({
          token: payload?.token as number,
          groups:
            payload?.query === "act1.scene two"
              ? [
                  {
                    key: "sheets",
                    items: [
                      {
                        id: "nav.sheet.8",
                        type: "sheet",
                        label: "Act 1 Scene Two",
                        url: "/sheets/8",
                      },
                    ],
                  },
                ]
              : [],
        });
      } else if (event === "palette_create_targets") {
        callback({ token: payload?.token as number, projects: [] });
      }
    });

    pressPaletteShortcut();
    await nextTick();
    await wrapper.find("[data-slot='command-input']").setValue("act1.scene two");
    await vi.advanceTimersByTimeAsync(200);
    await nextTick();

    const calledNavigation = vi
      .mocked(live.pushEvent)
      .mock.calls.some(
        ([event, payload]) => event === "palette_nav" && payload?.query === "act1.scene two",
      );
    const values = itemValues(wrapper);
    const text = wrapper.text();
    pressPaletteShortcut();
    await nextTick();

    expect(calledNavigation).toBe(true);
    expect(values).toContain("nav.sheet.8");
    expect(text).not.toContain("That reference pattern isn't valid");
  });

  it("keeps prior pattern results disabled while resolving a new pattern", async () => {
    vi.useFakeTimers();
    const { live, wrapper } = mountPalette([variableDefinitionOperation], true);
    let patternRequestCount = 0;
    let resolveSecondPattern: (() => void) | undefined;

    vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
      if (!callback) return;

      if (event === "palette_nav") {
        callback({ token: payload?.token as number, groups: [] });
      } else if (event === "palette_create_targets") {
        callback({ token: payload?.token as number, projects: [] });
      } else if (event === "palette_reference_pattern") {
        patternRequestCount += 1;
        const token = payload?.token as number;
        const item = {
          kind: "definition",
          type: "sheet",
          context: "Characters",
        };

        if (patternRequestCount === 1) {
          callback({
            token,
            items: [
              {
                ...item,
                id: "definition:health",
                label: "hero.health",
                url: "/sheets/hero?highlight=block:1",
              },
            ],
          });
        } else {
          resolveSecondPattern = () =>
            callback({
              token,
              items: [
                {
                  ...item,
                  id: "definition:mana",
                  label: "hero.mana",
                  url: "/sheets/hero?highlight=block:2",
                },
              ],
            });
        }
      }
    });

    pressPaletteShortcut();
    await nextTick();
    const input = wrapper.find("[data-slot='command-input']");
    await input.setValue("?health");
    await vi.advanceTimersByTimeAsync(200);
    await nextTick();
    expect(wrapper.find("[data-lookup-result-id='definition:health']").exists()).toBe(true);

    await input.setValue("?mana");
    await vi.advanceTimersByTimeAsync(200);
    await nextTick();
    expect(resolveSecondPattern).toBeDefined();

    selectItem(wrapper, "lookup-result-definition:health");
    await nextTick();
    expect(liveNavigate).not.toHaveBeenCalled();
    expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(true);

    resolveSecondPattern!();
    await nextTick();
    expect(wrapper.find("[data-lookup-result-id='definition:health']").exists()).toBe(false);
    expect(wrapper.find("[data-lookup-result-id='definition:mana']").exists()).toBe(true);
  });

  it("emits one lifecycle pair for one continuous pattern-door session", async () => {
    vi.useFakeTimers();
    const { live, wrapper } = mountPalette([variableDefinitionOperation], true);

    vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
      if (!callback) return;

      if (event === "palette_nav") {
        callback({ token: payload?.token as number, groups: [] });
      } else if (event === "palette_create_targets") {
        callback({ token: payload?.token as number, projects: [] });
      } else if (event === "palette_reference_pattern") {
        callback({
          token: payload?.token as number,
          items: [],
          truncated: false,
        });
      }
    });

    pressPaletteShortcut();
    await nextTick();
    vi.mocked(live.pushEvent).mockClear();
    const input = wrapper.find("[data-slot='command-input']");

    await input.setValue("?heal");
    await vi.advanceTimersByTimeAsync(200);
    await nextTick();
    await input.setValue("?health");
    await vi.advanceTimersByTimeAsync(200);
    await nextTick();

    const lifecycleEvents = vi
      .mocked(live.pushEvent)
      .mock.calls.filter(([event]) =>
        ["palette_operation_selected", "palette_operation_completed"].includes(event),
      )
      .map(([event]) => event);
    pressPaletteShortcut();
    await nextTick();

    expect(lifecycleEvents).toEqual(["palette_operation_selected", "palette_operation_completed"]);
  });

  it("ignores a superseded root navigation reply", async () => {
    vi.useFakeTimers();
    const { live, wrapper } = mountPalette();
    let resolveInitial: (() => void) | undefined;
    let resolveLatest: (() => void) | undefined;
    let navRequestCount = 0;

    vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
      if (!callback) return;

      if (event === "palette_nav") {
        navRequestCount += 1;
        const token = payload?.token as number;
        const reply = (id: string, label: string) => ({
          token,
          groups: [
            {
              key: "projects",
              items: [{ id, type: "project", label, url: `/${id}` }],
            },
          ],
        });

        if (navRequestCount === 1) {
          resolveInitial = () => callback(reply("nav.project.1", "Old project"));
        } else {
          resolveLatest = () => callback(reply("nav.project.2", "Latest project"));
        }
      } else if (event === "palette_create_targets") {
        callback({ token: payload?.token as number, projects: [] });
      }
    });

    pressPaletteShortcut();
    await nextTick();
    await wrapper.find("[data-slot='command-input']").setValue("latest");
    await vi.advanceTimersByTimeAsync(200);

    resolveInitial!();
    await nextTick();
    expect(itemValues(wrapper)).not.toContain("nav.project.1");

    resolveLatest!();
    await nextTick();
    expect(itemValues(wrapper)).toContain("nav.project.2");
  });

  it("does not query incomplete or invalid reference patterns", async () => {
    vi.useFakeTimers();
    const { live, wrapper } = mountPalette([variableDefinitionOperation], true);

    pressPaletteShortcut();
    await nextTick();
    const input = wrapper.find("[data-slot='command-input']");

    await input.setValue("?");
    await vi.advanceTimersByTimeAsync(250);
    expect(wrapper.text()).toContain("Keep typing the reference pattern");

    await input.setValue("mc..health");
    await vi.advanceTimersByTimeAsync(250);
    expect(wrapper.text()).toContain("That reference pattern isn't valid");

    expect(
      vi
        .mocked(live.pushEvent)
        .mock.calls.filter(([event]) => event === "palette_reference_pattern"),
    ).toHaveLength(0);
  });

  it("waits for root IME composition before resolving a reference pattern", async () => {
    vi.useFakeTimers();
    const { live, wrapper } = mountPalette([variableDefinitionOperation], true);

    pressPaletteShortcut();
    await nextTick();
    const input = wrapper.find<HTMLInputElement>("[data-slot='command-input']");

    input.element.dispatchEvent(new CompositionEvent("compositionstart", { bubbles: true }));
    await input.setValue("?health");
    await vi.advanceTimersByTimeAsync(250);

    expect(
      vi
        .mocked(live.pushEvent)
        .mock.calls.filter(([event]) => event === "palette_reference_pattern"),
    ).toHaveLength(0);

    input.element.dispatchEvent(new CompositionEvent("compositionend", { bubbles: true }));
    input.element.dispatchEvent(
      new KeyboardEvent("keydown", {
        key: "Enter",
        bubbles: true,
        cancelable: true,
        isComposing: true,
      }),
    );
    await nextTick();
    expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(true);
    await vi.advanceTimersByTimeAsync(200);

    expect(
      vi
        .mocked(live.pushEvent)
        .mock.calls.filter(([event]) => event === "palette_reference_pattern"),
    ).toHaveLength(1);
  });

  it("resumes root navigation after composition ends across a step transition", async () => {
    vi.useFakeTimers();
    const { live, wrapper } = mountPalette([gotoOperation], true);

    pressPaletteShortcut();
    await nextTick();
    const rootInput = wrapper.find<HTMLInputElement>("[data-slot='command-input']");

    rootInput.element.dispatchEvent(new CompositionEvent("compositionstart", { bubbles: true }));
    rootInput.element.dispatchEvent(new CompositionEvent("compositionend", { bubbles: true }));
    selectItem(wrapper, "operation-goto");
    await nextTick();

    const operationInput = wrapper.find<HTMLInputElement>(
      "[data-slot='palette-operation-input'] input",
    );
    await operationInput.trigger("keydown", { key: "Backspace" });
    await nextTick();

    const navCallsBeforeTyping = vi
      .mocked(live.pushEvent)
      .mock.calls.filter(([event]) => event === "palette_nav").length;

    await wrapper.find("[data-slot='command-input']").setValue("chapter");
    await vi.advanceTimersByTimeAsync(200);
    await nextTick();

    const navCallsAfterTyping = vi
      .mocked(live.pushEvent)
      .mock.calls.filter(([event]) => event === "palette_nav");
    pressPaletteShortcut();
    await nextTick();

    expect(navCallsAfterTyping).toHaveLength(navCallsBeforeTyping + 1);
    expect(navCallsAfterTyping.at(-1)?.[1]).toMatchObject({ query: "chapter" });
  });

  it("completes the generated-help round trip in Spanish", async () => {
    setTestLocale("es");
    const { live, wrapper } = mountPalette([gotoOperation]);
    vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
      if (!callback) return;

      if (event === "palette_nav") {
        callback({ token: payload?.token as number, groups: [] });
      } else if (event === "palette_create_targets") {
        callback({ token: payload?.token as number, projects: [] });
      } else if (event === "palette_operation_options") {
        callback({
          token: payload?.token as number,
          items: [
            {
              id: "nav.sheet.9",
              value: "/workspaces/acme/projects/veilbreak/sheets/9",
              label: "Capítulo dos",
              context: "Veilbreak",
            },
          ],
        });
      }
    });

    pressPaletteShortcut();
    await nextTick();
    expect(wrapper.find("[data-operation-id='goto']").text()).toContain("Ir a Capítulo 2");

    await wrapper.find("[data-slot='command-input']").setValue("help");
    await nextTick();
    expect(wrapper.text()).toContain("Qué puede hacer Storyarn");
    await wrapper.find("[data-slot='command-input']").setValue("");
    await nextTick();

    selectItem(wrapper, "operation-goto");
    await flushPromises();
    expect(wrapper.find("[data-slot='palette-operation-input']").text()).toContain("Ir a");
    expect(
      wrapper.find("[data-slot='palette-operation-input'] input").attributes("placeholder"),
    ).toBe("destino");

    selectItem(wrapper, "operation-option-nav.sheet.9");
    await nextTick();
    expect(
      wrapper.find<HTMLInputElement>("[data-slot='palette-operation-input'] input").element.value,
    ).toBe("Capítulo dos");
    selectItem(wrapper, "operation.execute");
    await nextTick();

    expect(liveNavigate).toHaveBeenCalledWith("/workspaces/acme/projects/veilbreak/sheets/9");
  });

  it("clears a filled slot when editing and never executes its stale value", async () => {
    const { live, wrapper } = mountPalette([gotoOperation]);
    vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
      if (!callback) return;

      if (event === "palette_nav") {
        callback({ token: payload?.token as number, groups: [] });
      } else if (event === "palette_create_targets") {
        callback({ token: payload?.token as number, projects: [] });
      } else if (event === "palette_operation_options") {
        callback({
          token: payload?.token as number,
          items: [
            {
              id: "nav.project.41",
              value: "/workspaces/acme/projects/veilbreak",
              label: "Veilbreak",
              context: "Acme",
            },
          ],
        });
      }
    });

    pressPaletteShortcut();
    await nextTick();
    selectItem(wrapper, "operation-goto");
    await nextTick();
    selectItem(wrapper, "operation-option-nav.project.41");
    await nextTick();

    expect(itemValues(wrapper)).toContain("operation.execute");

    const input = wrapper.find<HTMLInputElement>("[data-slot='palette-operation-input'] input");
    await input.setValue("Run operation");
    await nextTick();

    expect(itemValues(wrapper)).not.toContain("operation.execute");
    await input.trigger("keydown", { key: "Enter" });
    await nextTick();
    expect(liveNavigate).not.toHaveBeenCalled();
  });

  it("keeps shortcut-only operation completions visible in the client filter", async () => {
    const { live, wrapper } = mountPalette([gotoOperation]);
    vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
      if (!callback) return;

      if (event === "palette_nav") {
        callback({ token: payload?.token as number, groups: [] });
      } else if (event === "palette_create_targets") {
        callback({ token: payload?.token as number, projects: [] });
      } else if (event === "palette_operation_options") {
        callback({
          token: payload?.token as number,
          items: [
            {
              id: "nav.sheet.9",
              value: "/workspaces/acme/projects/veilbreak/sheets/9",
              label: "Chapter Two",
              context: "Veilbreak · Acme",
              meta: { shortcut: "ch2" },
            },
          ],
        });
      }
    });

    pressPaletteShortcut();
    await nextTick();
    selectItem(wrapper, "operation-goto");
    await nextTick();

    await wrapper
      .find<HTMLInputElement>("[data-slot='palette-operation-input'] input")
      .setValue("ch2");
    await nextTick();

    expect(itemValues(wrapper)).toContain("operation-option-nav.sheet.9");
  });

  it("updates client-backed operation completions without scheduling a server search", async () => {
    const { live, wrapper } = mountPalette([createOperation]);

    pressPaletteShortcut();
    await nextTick();
    selectItem(wrapper, "operation-create");
    await nextTick();

    await wrapper
      .find<HTMLInputElement>("[data-slot='palette-operation-input'] input")
      .setValue("flow");
    await nextTick();

    expect(itemValues(wrapper)).toContain("operation-option-entity-type:flow");
    expect(
      vi
        .mocked(live.pushEvent)
        .mock.calls.filter(([event]) => event === "palette_operation_options"),
    ).toHaveLength(0);
  });

  it("debounces server-backed operation completions at the root-search cadence", async () => {
    vi.useFakeTimers();
    const { live, wrapper } = mountPalette([gotoOperation]);

    pressPaletteShortcut();
    await nextTick();
    selectItem(wrapper, "operation-goto");
    await nextTick();

    const operationCalls = () =>
      vi
        .mocked(live.pushEvent)
        .mock.calls.filter(([event]) => event === "palette_operation_options");

    expect(operationCalls()).toHaveLength(1);
    await wrapper
      .find<HTMLInputElement>("[data-slot='palette-operation-input'] input")
      .setValue("Chapter");

    await vi.advanceTimersByTimeAsync(199);
    expect(operationCalls()).toHaveLength(1);

    await vi.advanceTimersByTimeAsync(1);
    expect(operationCalls()).toHaveLength(2);
  });

  it("keeps current-query options visible and preserves the highlighted result while reconciling", async () => {
    vi.useFakeTimers();
    const { live, wrapper } = mountPalette([gotoOperation]);
    let operationRequestCount = 0;
    let resolveCurrentQuery: (() => void) | undefined;

    vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
      if (!callback) return;

      if (event === "palette_nav") {
        callback({ token: payload?.token as number, groups: [] });
      } else if (event === "palette_create_targets") {
        callback({ token: payload?.token as number, projects: [] });
      } else if (event === "palette_operation_options") {
        operationRequestCount += 1;
        const token = payload?.token as number;
        const initialItems = [
          {
            id: "nav.chapter.alpha",
            value: "/chapters/alpha",
            label: "Chapter Alpha",
          },
          {
            id: "nav.chapter.beta",
            value: "/chapters/beta",
            label: "Chapter Beta",
          },
          {
            id: "nav.chapter.gamma",
            value: "/chapters/gamma",
            label: "Chapter Gamma",
          },
        ];

        if (operationRequestCount === 1) {
          callback({ token, items: initialItems });
        } else {
          resolveCurrentQuery = () =>
            callback({
              token,
              items: [
                {
                  id: "nav.chapter.delta",
                  value: "/chapters/delta",
                  label: "Chapter Delta",
                },
                initialItems[2]!,
                initialItems[1]!,
                initialItems[0]!,
              ],
            });
        }
      }
    });

    pressPaletteShortcut();
    await nextTick();
    selectItem(wrapper, "operation-goto");
    await nextTick();

    const input = wrapper.find<HTMLInputElement>("[data-slot='palette-operation-input'] input");
    await input.setValue("chapter");
    await nextTick();

    expect(itemValues(wrapper)).toEqual(
      expect.arrayContaining([
        "operation-option-nav.chapter.alpha",
        "operation-option-nav.chapter.beta",
      ]),
    );

    expect(
      wrapper.get("[data-operation-option-id='nav.chapter.alpha']").attributes("data-highlighted"),
    ).toBeDefined();
    await input.trigger("keydown", { key: "ArrowDown" });
    await nextTick();
    expect(
      wrapper.get("[data-operation-option-id='nav.chapter.beta']").attributes("data-highlighted"),
    ).toBeDefined();

    await vi.advanceTimersByTimeAsync(200);
    expect(resolveCurrentQuery).toBeDefined();
    expect(itemValues(wrapper)).toEqual(
      expect.arrayContaining([
        "operation-option-nav.chapter.alpha",
        "operation-option-nav.chapter.beta",
      ]),
    );

    await input.trigger("keydown", { key: "ArrowDown" });
    await nextTick();
    expect(
      wrapper.get("[data-operation-option-id='nav.chapter.gamma']").attributes("data-highlighted"),
    ).toBeDefined();
    resolveCurrentQuery!();
    await nextTick();
    await nextTick();

    const reconciledIds = wrapper
      .findAll("[data-operation-option-id]")
      .map((item) => item.attributes("data-operation-option-id"));
    expect(reconciledIds).toEqual([
      "nav.chapter.alpha",
      "nav.chapter.beta",
      "nav.chapter.gamma",
      "nav.chapter.delta",
    ]);
    expect(
      wrapper.get("[data-operation-option-id='nav.chapter.gamma']").attributes("data-highlighted"),
    ).toBeDefined();
  });

  it("does not restore options from a completion reply that lands after selection", async () => {
    vi.useFakeTimers();
    const { live, wrapper } = mountPalette([gotoOperation]);
    let operationRequestCount = 0;
    let resolveLateOptions: (() => void) | undefined;

    vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
      if (!callback) return;

      if (event === "palette_nav") {
        callback({ token: payload?.token as number, groups: [] });
      } else if (event === "palette_create_targets") {
        callback({ token: payload?.token as number, projects: [] });
      } else if (event === "palette_operation_options") {
        operationRequestCount += 1;
        const token = payload?.token as number;

        if (operationRequestCount === 1) {
          callback({
            token,
            items: [
              {
                id: "nav.project.41",
                value: "/workspaces/acme/projects/veilbreak",
                label: "Veilbreak",
                context: "Acme",
              },
            ],
          });
        } else {
          resolveLateOptions = () =>
            callback({
              token,
              items: [
                {
                  id: "nav.project.99",
                  value: "/workspaces/acme/projects/late",
                  label: "Late result",
                  context: "Acme",
                },
              ],
            });
        }
      }
    });

    pressPaletteShortcut();
    await nextTick();
    selectItem(wrapper, "operation-goto");
    await nextTick();

    const visibleOption = wrapper
      .findAllComponents(CommandItem)
      .find((candidate) => candidate.props("value") === "operation-option-nav.project.41");
    expect(visibleOption).toBeDefined();

    await wrapper
      .find<HTMLInputElement>("[data-slot='palette-operation-input'] input")
      .setValue("late");
    vi.advanceTimersByTime(200);
    expect(resolveLateOptions).toBeDefined();

    // Vue has not flushed the removal caused by the request yet, matching the
    // event/reply race at the boundary of a visible selection.
    visibleOption!.vm.$emit("select", new Event("select"));
    resolveLateOptions!();
    await nextTick();

    expect(itemValues(wrapper)).toContain("operation.execute");
    expect(itemValues(wrapper)).not.toContain("operation-option-nav.project.99");
  });

  it("lets an active IME consume Escape without cancelling the guided operation", async () => {
    const { wrapper } = mountPalette([gotoOperation]);
    pressPaletteShortcut();
    await nextTick();
    selectItem(wrapper, "operation-goto");
    await nextTick();

    const input = wrapper.find<HTMLInputElement>("[data-slot='palette-operation-input'] input");
    input.element.dispatchEvent(new CompositionEvent("compositionstart", { bubbles: true }));
    input.element.dispatchEvent(
      new KeyboardEvent("keydown", {
        key: "Escape",
        bubbles: true,
        cancelable: true,
        isComposing: true,
      }),
    );
    await nextTick();

    expect(wrapper.find("[data-slot='palette-operation-input']").exists()).toBe(true);
    expect(wrapper.find("[data-operation-id='goto']").exists()).toBe(false);
  });

  it("advances create from content type to authorized project and keeps durable mutation execution", async () => {
    const { live, wrapper } = mountPalette([createOperation]);
    vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
      if (!callback) return;

      if (event === "palette_nav") {
        callback({ token: payload?.token as number, groups: [] });
      } else if (event === "palette_create_targets") {
        callback({
          token: payload?.token as number,
          projects: [{ id: 11, label: "Veilbreak", context: "Acme" }],
        });
      } else if (event === "palette_create") {
        callback({ url: "/workspaces/acme/projects/veilbreak/flows/42" });
      }
    });

    pressPaletteShortcut();
    await nextTick();
    selectItem(wrapper, "operation-create");
    await nextTick();
    selectItem(wrapper, "operation-option-entity-type:flow");
    await nextTick();

    expect(
      vi.mocked(live.pushEvent).mock.calls.filter(([event]) => event === "palette_create_targets"),
    ).toHaveLength(1);
    expect(
      vi
        .mocked(live.pushEvent)
        .mock.calls.filter(
          ([event, payload]) =>
            event === "palette_operation_options" &&
            payload?.operation_id === "create" &&
            payload?.parameter_id === "project",
        ),
    ).toHaveLength(0);

    selectItem(wrapper, "operation-option-project:11");
    await nextTick();
    selectItem(wrapper, "operation.execute");
    await nextTick();

    expect(live.pushEvent).toHaveBeenCalledWith(
      "palette_create",
      expect.objectContaining({
        type: "flow",
        project_id: 11,
        execution_id: expect.any(String),
      }),
      expect.any(Function),
    );
    expect(liveNavigate).toHaveBeenCalledWith("/workspaces/acme/projects/veilbreak/flows/42");
  });

  it("routes guided delete through the existing confirmation and durable delete event", async () => {
    const { live, wrapper } = mountPalette([deleteOperation]);
    vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
      if (!callback) return;

      if (event === "palette_nav") {
        callback({ token: payload?.token as number, groups: [] });
      } else if (event === "palette_create_targets") {
        callback({
          token: payload?.token as number,
          projects: [{ id: 11, label: "Veilbreak", context: "Acme" }],
        });
      } else if (event === "palette_operation_options") {
        callback({
          token: payload?.token as number,
          items: [
            {
              id: "sheet:9",
              value: { id: 9, type: "sheet", projectId: 11 },
              label: "Old draft",
              context: "Veilbreak · Acme",
            },
          ],
        });
      } else if (event === "palette_delete") {
        callback({ deleted: true });
      }
    });

    pressPaletteShortcut();
    await nextTick();
    selectItem(wrapper, "operation-delete");
    await nextTick();
    selectItem(wrapper, "operation-option-sheet:9");
    await nextTick();
    selectItem(wrapper, "operation.execute");
    await nextTick();

    expect(wrapper.text()).toContain("Old draft");
    selectItem(wrapper, "palette.confirm-delete");
    await nextTick();

    expect(live.pushEvent).toHaveBeenCalledWith(
      "palette_delete",
      expect.objectContaining({
        type: "sheet",
        id: 9,
        project_id: 11,
        execution_id: expect.any(String),
      }),
      expect.any(Function),
    );
    expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(false);
  });

  it("uses live registrations as completions for run_command and open_view", async () => {
    const run = vi.fn();
    registerPaletteCommands("flows", [
      command("flows.fit", run),
      {
        id: "flows.panel",
        label: "Flow settings",
        groupKey: "palette.groups.view",
        href: "/workspaces/acme/projects/veilbreak/flows/9/settings",
      },
    ]);

    const { wrapper } = mountPalette([runCommandOperation, openViewOperation]);
    pressPaletteShortcut();
    await nextTick();
    selectItem(wrapper, "operation-run_command");
    await nextTick();
    selectItem(wrapper, "operation-option-command:flows.fit");
    await nextTick();
    selectItem(wrapper, "operation.execute");
    await flushPromises();

    expect(run).toHaveBeenCalledOnce();

    pressPaletteShortcut();
    await nextTick();
    selectItem(wrapper, "operation-open_view");
    await nextTick();
    selectItem(wrapper, "operation-option-command:flows.panel");
    await nextTick();
    selectItem(wrapper, "operation.execute");
    await nextTick();

    expect(liveNavigate).toHaveBeenCalledWith(
      "/workspaces/acme/projects/veilbreak/flows/9/settings",
    );
  });

  it("records a guided operation as recent only after its async command succeeds", async () => {
    let resolveCommand!: () => void;
    registerPaletteCommands("flows", [
      command(
        "flows.async-guided",
        () =>
          new Promise<void>((resolve) => {
            resolveCommand = resolve;
          }),
      ),
    ]);

    const { live, wrapper } = mountPalette([runCommandOperation]);
    pressPaletteShortcut();
    await nextTick();
    selectItem(wrapper, "operation-run_command");
    await nextTick();
    selectItem(wrapper, "operation-option-command:flows.async-guided");
    await nextTick();
    selectItem(wrapper, "operation.execute");
    await nextTick();

    expect(localStorage.getItem("storyarn.command-palette.recent-operations.v1")).toBeNull();
    expect(
      vi
        .mocked(live.pushEvent)
        .mock.calls.filter(([event]) => event === "palette_operation_completed"),
    ).toHaveLength(0);

    resolveCommand();
    await flushPromises();

    expect(localStorage.getItem("storyarn.command-palette.recent-operations.v1")).toBe(
      '["run_command"]',
    );
    expect(
      vi
        .mocked(live.pushEvent)
        .mock.calls.filter(([event]) =>
          [
            "palette_operation_selected",
            "palette_operation_completed",
            "palette_operation_abandoned",
          ].includes(event),
        ),
    ).toEqual([
      ["palette_operation_selected", { operation_id: "run_command", surface: "flows" }, undefined],
      ["palette_operation_completed", { operation_id: "run_command", surface: "flows" }, undefined],
    ]);
  });

  it("does not record a failed guided operation and emits a content-free abandonment", async () => {
    registerPaletteCommands("flows", [
      command("flows.reject-guided", () => Promise.reject(new Error("failed"))),
    ]);

    const { live, wrapper } = mountPalette([runCommandOperation]);
    pressPaletteShortcut();
    await nextTick();
    selectItem(wrapper, "operation-run_command");
    await nextTick();
    selectItem(wrapper, "operation-option-command:flows.reject-guided");
    await nextTick();
    selectItem(wrapper, "operation.execute");
    await flushPromises();

    expect(localStorage.getItem("storyarn.command-palette.recent-operations.v1")).toBeNull();
    expect(wrapper.find('[role="alert"]').text()).toBe("The command failed to run. Try again.");

    pressPaletteShortcut();
    await nextTick();

    expect(
      vi
        .mocked(live.pushEvent)
        .mock.calls.filter(([event]) =>
          [
            "palette_operation_selected",
            "palette_operation_completed",
            "palette_operation_abandoned",
          ].includes(event),
        ),
    ).toEqual([
      ["palette_operation_selected", { operation_id: "run_command", surface: "flows" }, undefined],
      ["palette_operation_abandoned", { operation_id: "run_command", surface: "flows" }, undefined],
    ]);
  });

  it("runs the command, tracks execution, and closes on select", async () => {
    let ran = false;
    registerPaletteCommands("flows", [
      command("flows.run-me", () => {
        ran = true;
      }),
    ]);

    const { live, wrapper } = mountPalette();
    pressPaletteShortcut();
    await nextTick();

    wrapper.findComponent(CommandItem).vm.$emit("select", new Event("select"));
    await flushPromises();

    expect(ran).toBe(true);
    expect(live.pushEvent).toHaveBeenCalledWith(
      "palette_command_executed",
      { command_id: "flows.run-me", surface: "flows" },
      undefined,
    );
    expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(false);
  });

  it("tracks a no-results search with the query length only", async () => {
    vi.useFakeTimers();
    registerPaletteCommands("flows", [command("flows.a")]);
    const { live, wrapper } = mountPalette();

    pressPaletteShortcut();
    await nextTick();

    await wrapper.find("[data-slot='command-input']").setValue("zzzz");
    await vi.advanceTimersByTimeAsync(199);
    expect(
      vi.mocked(live.pushEvent).mock.calls.filter(([event]) => event === "palette_nav"),
    ).toHaveLength(1);

    await vi.advanceTimersByTimeAsync(1);
    await nextTick();

    expect(wrapper.find("[data-slot='command-empty']").exists()).toBe(true);
    expect(
      vi.mocked(live.pushEvent).mock.calls.filter(([event]) => event === "palette_nav"),
    ).toHaveLength(2);
    expect(live.pushEvent).toHaveBeenCalledWith(
      "palette_search_no_results",
      { query_length: 4, surface: "flows" },
      undefined,
    );
    const noResultCalls = vi
      .mocked(live.pushEvent)
      .mock.calls.filter(([event]) => event === "palette_search_no_results");
    expect(noResultCalls).toHaveLength(1);
    vi.useRealTimers();
  });

  it("a throwing command keeps the palette open with an explicit error and is NOT tracked as executed", async () => {
    registerPaletteCommands("flows", [
      command("flows.boom", () => {
        throw new Error("boom");
      }),
    ]);

    const { live, wrapper } = mountPalette();
    pressPaletteShortcut();
    await nextTick();

    wrapper.findComponent(CommandItem).vm.$emit("select", new Event("select"));
    await nextTick();

    expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(true);
    expect(wrapper.find('[role="alert"]').text()).toBe("The command failed to run. Try again.");

    const executedCalls = vi
      .mocked(live.pushEvent)
      .mock.calls.filter(([event]) => event === "palette_command_executed");
    expect(executedCalls).toHaveLength(0);
  });

  it("awaits async commands and records only a fulfilled result", async () => {
    let resolveCommand!: () => void;
    registerPaletteCommands("flows", [
      command(
        "flows.async",
        () =>
          new Promise<void>((resolve) => {
            resolveCommand = resolve;
          }),
      ),
    ]);

    const { live, wrapper } = mountPalette();
    pressPaletteShortcut();
    await nextTick();
    selectItem(wrapper, "flows.async");
    await nextTick();

    expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(true);
    expect(
      vi
        .mocked(live.pushEvent)
        .mock.calls.filter(([event]) => event === "palette_command_executed"),
    ).toHaveLength(0);

    resolveCommand();
    await flushPromises();

    expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(false);
    expect(live.pushEvent).toHaveBeenCalledWith(
      "palette_command_executed",
      { command_id: "flows.async", surface: "flows" },
      undefined,
    );
  });

  it("ignores operation selection while a root command is pending", async () => {
    let resolveCommand!: () => void;
    registerPaletteCommands("flows", [
      command(
        "flows.async",
        () =>
          new Promise<void>((resolve) => {
            resolveCommand = resolve;
          }),
      ),
    ]);

    const { live, wrapper } = mountPalette([gotoOperation]);
    pressPaletteShortcut();
    await nextTick();
    selectItem(wrapper, "flows.async");
    await nextTick();

    // Bypass Reka's visual disabled state: the handler is the logical fence.
    selectItem(wrapper, "operation-goto");
    await nextTick();

    expect(wrapper.find("[data-slot='palette-operation-input']").exists()).toBe(false);
    expect(
      vi
        .mocked(live.pushEvent)
        .mock.calls.filter(([event]) => event === "palette_operation_selected"),
    ).toHaveLength(0);

    resolveCommand();
    await flushPromises();
  });

  it("keeps the palette open when an async command rejects", async () => {
    registerPaletteCommands("flows", [
      command("flows.reject", () => Promise.reject(new Error("failed"))),
    ]);

    const { live, wrapper } = mountPalette();
    pressPaletteShortcut();
    await nextTick();
    selectItem(wrapper, "flows.reject");
    await flushPromises();

    expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(true);
    expect(wrapper.find('[role="alert"]').text()).toBe("The command failed to run. Try again.");
    expect(
      vi
        .mocked(live.pushEvent)
        .mock.calls.filter(([event]) => event === "palette_command_executed"),
    ).toHaveLength(0);
  });

  it("keeps an AI command pending and disabled until launch settles", async () => {
    let resolveLaunch!: () => void;
    registerPaletteCommands("flows", [
      aiLaunchCommand({
        launch: () =>
          new Promise((resolve) => {
            resolveLaunch = () => resolve({ status: "launched" });
          }),
      }),
    ]);

    const { live, wrapper } = mountPalette();
    pressPaletteShortcut();
    await nextTick();
    selectItem(wrapper, "ai.contract.launch");
    await nextTick();

    expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(true);
    expect(
      wrapper.find<HTMLInputElement>("[data-slot='command-input']").attributes("disabled"),
    ).toBeDefined();
    expect(
      vi
        .mocked(live.pushEvent)
        .mock.calls.filter(([event]) => event === "palette_command_executed"),
    ).toHaveLength(0);

    resolveLaunch();
    await flushPromises();

    expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(false);
    expect(live.pushEvent).toHaveBeenCalledWith(
      "palette_command_executed",
      { command_id: "ai.contract.launch", surface: "flows" },
      undefined,
    );
  });

  it("keeps the palette open and untracked for a classified AI block", async () => {
    registerPaletteCommands("flows", [
      aiLaunchCommand({
        launch: vi.fn().mockResolvedValue({
          status: "blocked",
          reasonKey: "palette.not_allowed",
        }),
      }),
    ]);

    const { live, wrapper } = mountPalette();
    pressPaletteShortcut();
    await nextTick();
    selectItem(wrapper, "ai.contract.launch");
    await flushPromises();

    expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(true);
    expect(wrapper.find('[role="alert"]').text()).toBe("You don't have permission to do that.");
    expect(
      vi
        .mocked(live.pushEvent)
        .mock.calls.filter(([event]) => event === "palette_command_executed"),
    ).toHaveLength(0);
  });

  it("clears an AI CTA when the query changes or the user enters another step", async () => {
    const cta = {
      labelKey: "settings.nav.items.integrations",
      destination: { type: "route", id: "account-ai-integrations" } as const,
      launch: vi.fn().mockResolvedValue({ status: "launched" } as const),
    };

    registerPaletteCommands("flows", [
      aiLaunchCommand({
        availability: { state: "cta", reasonKey: "palette.not_allowed", cta },
      }),
    ]);

    const { wrapper } = mountPalette();
    pressPaletteShortcut();
    await nextTick();
    selectItem(wrapper, "ai.contract.launch");
    await flushPromises();
    expect(wrapper.find('[role="alert"] button').exists()).toBe(true);

    await wrapper.find("[data-slot='command-input']").setValue("new query");
    await nextTick();
    expect(wrapper.find('[role="alert"] button').exists()).toBe(false);

    await wrapper.find("[data-slot='command-input']").setValue("");
    selectItem(wrapper, "ai.contract.launch");
    await flushPromises();
    expect(wrapper.find('[role="alert"] button').exists()).toBe(true);

    selectItem(wrapper, "create.sheet");
    await nextTick();
    expect(wrapper.find('[role="alert"] button').exists()).toBe(false);
  });

  it("distinguishes a remote search failure from an empty result", async () => {
    const { live, wrapper } = mountPalette();
    vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
      if (event === "palette_nav") throw new Error("socket gone");
      if (event === "palette_create_targets" && callback) {
        callback({ token: payload?.token as number, projects: [] });
      }
    });

    pressPaletteShortcut();
    await nextTick();

    expect(wrapper.find('[role="alert"]').text()).toBe(
      "Storyarn couldn't load these results. Try again.",
    );
    expect(wrapper.find("[data-slot='command-empty']").exists()).toBe(false);
  });

  describe("server-driven navigation", () => {
    function navReplyMock(live: LiveInterface, tokenOffset = 0) {
      vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
        if (event !== "palette_nav" || !payload || !callback) return;

        callback({
          token: (payload.token as number) + tokenOffset,
          groups: [
            {
              key: "projects",
              items: [
                {
                  id: "nav.project.1",
                  type: "project",
                  label: "Veilbreak",
                  url: "/workspaces/ws/projects/veilbreak",
                },
              ],
            },
          ],
        });
      });
    }

    it("fetches destinations on open and navigates on select", async () => {
      const { live, wrapper } = mountPalette();
      navReplyMock(live);

      pressPaletteShortcut();
      await nextTick();

      const headings = wrapper
        .findAll("[data-slot='command-group-heading']")
        .map((heading) => heading.text());
      expect(headings).toContain("Projects");

      const item = wrapper
        .findAllComponents(CommandItem)
        .find((candidate) => candidate.props("value") === "nav.project.1");
      expect(item).toBeDefined();

      item!.vm.$emit("select", new Event("select"));
      await nextTick();

      expect(liveNavigate).toHaveBeenCalledWith("/workspaces/ws/projects/veilbreak");
      expect(live.pushEvent).toHaveBeenCalledWith(
        "palette_command_executed",
        { command_id: "nav.project.1", surface: "global" },
        undefined,
      );
      expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(false);
      const analyticsCall = vi
        .mocked(live.pushEvent)
        .mock.invocationCallOrder.find(
          (_order, index) =>
            vi.mocked(live.pushEvent).mock.calls[index]?.[0] === "palette_command_executed",
        );
      expect(analyticsCall).toBeLessThan(vi.mocked(liveNavigate).mock.invocationCallOrder.at(-1)!);
    });

    it("reopening after a search shows default results immediately (no debounce delay)", async () => {
      const { live, wrapper } = mountPalette();
      navReplyMock(live);

      pressPaletteShortcut();
      await nextTick();
      await wrapper.find("[data-slot='command-input']").setValue("old search");

      pressPaletteShortcut(); // close
      await nextTick();
      pressPaletteShortcut(); // reopen
      await nextTick();

      const navCalls = vi
        .mocked(live.pushEvent)
        .mock.calls.filter(([event]) => event === "palette_nav");
      const lastPayload = navCalls.at(-1)![1] as { query: string };
      expect(lastPayload.query).toBe("");

      const item = wrapper
        .findAllComponents(CommandItem)
        .find((candidate) => candidate.props("value") === "nav.project.1");
      expect(item).toBeDefined();
    });

    it("drops replies whose token does not match the latest request", async () => {
      const { live, wrapper } = mountPalette();
      navReplyMock(live, 999);

      pressPaletteShortcut();
      await nextTick();

      const item = wrapper
        .findAllComponents(CommandItem)
        .find((candidate) => candidate.props("value") === "nav.project.1");
      expect(item).toBeUndefined();
    });
  });

  function selectItem(wrapper: ReturnType<typeof mountPalette>["wrapper"], value: string) {
    const item = wrapper
      .findAllComponents(CommandItem)
      .find((candidate) => candidate.props("value") === value);
    expect(item, `expected a command item with value ${value}`).toBeDefined();
    item!.vm.$emit("select", new Event("select"));
  }

  function itemValues(wrapper: ReturnType<typeof mountPalette>["wrapper"]): string[] {
    return wrapper.findAllComponents(CommandItem).map((item) => String(item.props("value")));
  }

  describe("create flow (multi-step)", () => {
    function createReplyMock(
      live: LiveInterface,
      { targets = [{ id: 11, label: "Veilbreak", context: "Acme" }], createReply = {} } = {},
    ) {
      vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
        if (!callback) return;

        if (event === "palette_create_targets") {
          callback({ token: (payload as { token: number }).token, projects: targets });
        }

        if (event === "palette_create") {
          callback({ url: "/workspaces/acme/projects/veilbreak/sheets/42", ...createReply });
        }
      });
    }

    it("New Sheet opens the project picker, creates in the chosen project, and navigates", async () => {
      const { live, wrapper } = mountPalette();
      createReplyMock(live);

      pressPaletteShortcut();
      await nextTick();

      selectItem(wrapper, "create.sheet");
      await nextTick();

      // Picker step: authorized projects with the pending action as heading.
      const headings = wrapper
        .findAll("[data-slot='command-group-heading']")
        .map((heading) => heading.text());
      expect(headings).toContain("New Sheet");
      expect(document.activeElement?.getAttribute("data-slot")).toBe("command-input");

      selectItem(wrapper, "create-target-11");
      await nextTick();

      expect(live.pushEvent).toHaveBeenCalledWith(
        "palette_create",
        expect.objectContaining({
          type: "sheet",
          project_id: 11,
          execution_id: expect.any(String),
        }),
        expect.any(Function),
      );
      expect(liveNavigate).toHaveBeenCalledWith("/workspaces/acme/projects/veilbreak/sheets/42");
      expect(live.pushEvent).toHaveBeenCalledWith(
        "palette_command_executed",
        { command_id: "create.sheet", surface: "global" },
        undefined,
      );
      expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(false);
    });

    it("hides create/delete actions when no project accepts content mutations", async () => {
      const { live, wrapper } = mountPalette();
      createReplyMock(live, { targets: [] });

      pressPaletteShortcut();
      await nextTick();

      expect(itemValues(wrapper)).not.toContain("create.sheet");
      expect(itemValues(wrapper)).not.toContain("create.flow");
      expect(itemValues(wrapper)).not.toContain("create.scene");
      expect(itemValues(wrapper)).not.toContain("palette.delete-entity");
    });

    it("a limit_reached reply surfaces its specific error and stays open", async () => {
      const { live, wrapper } = mountPalette();
      createReplyMock(live, { createReply: { url: undefined, error: "limit_reached" } });

      pressPaletteShortcut();
      await nextTick();
      selectItem(wrapper, "create.scene");
      await nextTick();
      selectItem(wrapper, "create-target-11");
      await nextTick();

      expect(wrapper.find('[role="alert"]').text()).toBe("Item limit reached for your plan");
      expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(true);

      const executedCalls = vi
        .mocked(live.pushEvent)
        .mock.calls.filter(([event]) => event === "palette_command_executed");
      expect(executedCalls).toHaveLength(0);
    });

    it("Escape inside a step goes back to the root instead of closing", async () => {
      const { live, wrapper } = mountPalette();
      createReplyMock(live);

      pressPaletteShortcut();
      await nextTick();
      selectItem(wrapper, "create.sheet");
      await nextTick();

      await wrapper.find("[data-slot='command-input']").trigger("keydown", { key: "Escape" });
      await nextTick();

      expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(true);
      expect(itemValues(wrapper)).toContain("create.sheet");
      expect(itemValues(wrapper)).not.toContain("create-target-11");
    });
  });

  describe("delete flow (multi-step, never leaves the palette)", () => {
    function deleteReplyMock(
      live: LiveInterface,
      {
        deleteReply = { deleted: true },
      }: { deleteReply?: { deleted?: boolean; error?: string } } = {},
    ) {
      vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
        if (!callback) return;

        if (event === "palette_create_targets") {
          callback({
            token: (payload as { token: number }).token,
            projects: [{ id: 11, label: "Veilbreak", context: "Acme" }],
          });
        }

        if (event === "palette_delete_search") {
          callback({
            token: (payload as { token: number }).token,
            items: [
              {
                id: 7,
                type: "sheet",
                label: "Kael the Wanderer",
                context: "Veilbreak",
                projectId: 11,
              },
            ],
          });
        }

        if (event === "palette_delete") {
          callback(deleteReply);
        }
      });
    }

    it("explains when editable projects do not contain deletable content", async () => {
      const { live, wrapper } = mountPalette();
      vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
        if (!callback) return;

        if (event === "palette_nav") {
          callback({ token: payload?.token as number, groups: [] });
        } else if (event === "palette_create_targets") {
          callback({
            token: payload?.token as number,
            projects: [{ id: 11, label: "Veilbreak", context: "Acme" }],
          });
        } else if (event === "palette_delete_search") {
          callback({ token: payload?.token as number, items: [] });
        }
      });

      pressPaletteShortcut();
      await nextTick();
      selectItem(wrapper, "palette.delete-entity");
      await nextTick();

      expect(wrapper.text()).toContain("No sheets, flows or scenes are available to delete");
      expect(wrapper.text()).not.toContain("No matching commands");
    });

    it("lists deletable entities, confirms inline, deletes, and returns to the listing", async () => {
      const { live, wrapper } = mountPalette();
      deleteReplyMock(live);

      pressPaletteShortcut();
      await nextTick();
      selectItem(wrapper, "palette.delete-entity");
      await nextTick();

      selectItem(wrapper, "delete-sheet-7");
      await nextTick();

      // Inline confirm step: title + question with the entity name; the
      // search input is hidden while confirming.
      expect(wrapper.text()).toContain("Delete sheet?");
      expect(wrapper.text()).toContain('Are you sure you want to delete "Kael the Wanderer"?');
      expect(wrapper.find("[data-slot='command-input']").exists()).toBe(false);

      selectItem(wrapper, "palette.confirm-delete");
      await nextTick();

      expect(live.pushEvent).toHaveBeenCalledWith(
        "palette_delete",
        expect.objectContaining({
          type: "sheet",
          id: 7,
          project_id: 11,
          execution_id: expect.any(String),
        }),
        expect.any(Function),
      );
      expect(live.pushEvent).toHaveBeenCalledWith(
        "palette_command_executed",
        { command_id: "delete.sheet", surface: "global" },
        undefined,
      );

      // Back on the refreshed listing, still inside the palette.
      expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(true);
      expect(itemValues(wrapper)).toContain("delete-sheet-7");
    });

    it("cancel returns to the listing without deleting", async () => {
      const { live, wrapper } = mountPalette();
      deleteReplyMock(live);

      pressPaletteShortcut();
      await nextTick();
      selectItem(wrapper, "palette.delete-entity");
      await nextTick();
      selectItem(wrapper, "delete-sheet-7");
      await nextTick();

      selectItem(wrapper, "palette.cancel-delete");
      await nextTick();

      expect(itemValues(wrapper)).toContain("delete-sheet-7");

      const deleteCalls = vi
        .mocked(live.pushEvent)
        .mock.calls.filter(([event]) => event === "palette_delete");
      expect(deleteCalls).toHaveLength(0);
    });

    it("Escape during the inline confirm goes back to the listing, not out of the palette", async () => {
      const { live, wrapper } = mountPalette();
      deleteReplyMock(live);

      pressPaletteShortcut();
      await nextTick();
      selectItem(wrapper, "palette.delete-entity");
      await nextTick();
      selectItem(wrapper, "delete-sheet-7");
      await nextTick();

      // The search input is hidden here — Escape must still step back.
      await wrapper.find("[data-slot='command-item']").trigger("keydown", { key: "Escape" });
      await nextTick();

      expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(true);
      expect(itemValues(wrapper)).toContain("delete-sheet-7");
      expect(itemValues(wrapper)).not.toContain("palette.confirm-delete");
    });

    it("a pending mutation blocks re-submits until the server replies", async () => {
      const { live, wrapper } = mountPalette();
      let deleteCallback: ((reply: { deleted: boolean }) => void) | null = null;

      vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
        if (!callback) return;

        if (event === "palette_create_targets") {
          callback({
            token: (payload as { token: number }).token,
            projects: [{ id: 11, label: "Veilbreak", context: "Acme" }],
          });
        }

        if (event === "palette_delete_search") {
          callback({
            token: (payload as { token: number }).token,
            items: [{ id: 7, type: "sheet", label: "Kael", context: "Veilbreak", projectId: 11 }],
          });
        }

        if (event === "palette_delete") {
          // Hold the reply: the palette must not accept a second submit.
          deleteCallback = callback as (reply: { deleted: boolean }) => void;
        }
      });

      pressPaletteShortcut();
      await nextTick();
      selectItem(wrapper, "palette.delete-entity");
      await nextTick();
      selectItem(wrapper, "delete-sheet-7");
      await nextTick();

      selectItem(wrapper, "palette.confirm-delete");
      await nextTick();
      selectItem(wrapper, "palette.confirm-delete");
      await nextTick();

      const deleteCalls = vi
        .mocked(live.pushEvent)
        .mock.calls.filter(([event]) => event === "palette_delete");
      expect(deleteCalls).toHaveLength(1);

      deleteCallback!({ deleted: true });
      await nextTick();
      expect(itemValues(wrapper)).toContain("delete-sheet-7");
    });

    it("a transport failure clears the pending state and stays recoverable", async () => {
      const { live, wrapper } = mountPalette();

      vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
        if (event === "palette_create_targets" && callback) {
          callback({
            token: (payload as { token: number }).token,
            projects: [{ id: 11, label: "Veilbreak", context: "Acme" }],
          });
        }

        if (event === "palette_delete_search" && callback) {
          callback({
            token: (payload as { token: number }).token,
            items: [{ id: 7, type: "sheet", label: "Kael", context: "Veilbreak", projectId: 11 }],
          });
        }

        // The raw LiveVue pushEvent throws when the socket is gone; the
        // useLive wrapper turns that into the component's onError callback.
        if (event === "palette_delete") {
          throw new Error("socket gone");
        }
      });

      pressPaletteShortcut();
      await nextTick();
      selectItem(wrapper, "palette.delete-entity");
      await nextTick();
      selectItem(wrapper, "delete-sheet-7");
      await nextTick();

      selectItem(wrapper, "palette.confirm-delete");
      await nextTick();

      expect(wrapper.find('[role="alert"]').text()).toBe("The command failed to run. Try again.");

      // Not stuck pending: the confirm can be retried.
      selectItem(wrapper, "palette.confirm-delete");
      await nextTick();

      const deleteCalls = vi
        .mocked(live.pushEvent)
        .mock.calls.filter(([event]) => event === "palette_delete");
      expect(deleteCalls).toHaveLength(2);
      expect((deleteCalls[0]![1] as { execution_id: string }).execution_id).toBe(
        (deleteCalls[1]![1] as { execution_id: string }).execution_id,
      );
    });

    it("times out a lost reply and retries with the same durable operation id", async () => {
      vi.useFakeTimers();
      const { live, wrapper } = mountPalette();

      vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
        if (event === "palette_create_targets" && callback) {
          callback({
            token: (payload as { token: number }).token,
            projects: [{ id: 11, label: "Veilbreak", context: "Acme" }],
          });
        }

        if (event === "palette_delete_search" && callback) {
          callback({
            token: (payload as { token: number }).token,
            items: [{ id: 7, type: "sheet", label: "Kael", context: "Veilbreak", projectId: 11 }],
          });
        }

        // Simulate a push accepted by LiveView whose reply is lost when the
        // connection drops: neither callback fires.
      });

      pressPaletteShortcut();
      await nextTick();
      selectItem(wrapper, "palette.delete-entity");
      await nextTick();
      selectItem(wrapper, "delete-sheet-7");
      await nextTick();
      selectItem(wrapper, "palette.confirm-delete");
      await nextTick();

      await vi.advanceTimersByTimeAsync(15_000);
      await nextTick();

      expect(wrapper.find("[role='alert']").text()).toBe("The command failed to run. Try again.");

      selectItem(wrapper, "palette.confirm-delete");
      await nextTick();

      const deleteCalls = vi
        .mocked(live.pushEvent)
        .mock.calls.filter(([event]) => event === "palette_delete");
      expect(deleteCalls).toHaveLength(2);
      expect((deleteCalls[0]![1] as { execution_id: string }).execution_id).toBe(
        (deleteCalls[1]![1] as { execution_id: string }).execution_id,
      );
    });

    it("cannot close during a mutation and always reconciles its reply", async () => {
      const { live, wrapper } = mountPalette();
      let deleteCallback: ((reply: { deleted: boolean }) => void) | null = null;

      vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
        if (event === "palette_create_targets" && callback) {
          callback({
            token: (payload as { token: number }).token,
            projects: [{ id: 11, label: "Veilbreak", context: "Acme" }],
          });
        }

        if (event === "palette_delete_search" && callback) {
          callback({
            token: (payload as { token: number }).token,
            items: [{ id: 7, type: "sheet", label: "Kael", context: "Veilbreak", projectId: 11 }],
          });
        }

        if (event === "palette_delete" && callback) {
          deleteCallback = callback as (reply: { deleted: boolean }) => void;
        }
      });

      pressPaletteShortcut();
      await nextTick();
      selectItem(wrapper, "palette.delete-entity");
      await nextTick();
      selectItem(wrapper, "delete-sheet-7");
      await nextTick();
      selectItem(wrapper, "palette.confirm-delete");
      await nextTick();

      pressPaletteShortcut(); // close while the delete is in flight
      await nextTick();

      expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(true);

      deleteCallback!({ deleted: true });
      await nextTick();

      expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(true);
      expect(itemValues(wrapper)).toContain("delete-sheet-7");

      const executedCalls = vi
        .mocked(live.pushEvent)
        .mock.calls.filter(([event]) => event === "palette_command_executed");
      expect(executedCalls).toHaveLength(1);
    });

    it("an unauthorized reply keeps the confirm step with an explicit error", async () => {
      const { live, wrapper } = mountPalette();
      deleteReplyMock(live, { deleteReply: { error: "unauthorized" } });

      pressPaletteShortcut();
      await nextTick();
      selectItem(wrapper, "palette.delete-entity");
      await nextTick();
      selectItem(wrapper, "delete-sheet-7");
      await nextTick();
      selectItem(wrapper, "palette.confirm-delete");
      await nextTick();

      expect(wrapper.find('[role="alert"]').text()).toBe("You don't have permission to do that.");
      expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(true);

      const executedCalls = vi
        .mocked(live.pushEvent)
        .mock.calls.filter(([event]) => event === "palette_command_executed");
      expect(executedCalls).toHaveLength(0);
    });
  });
});
