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
  registerPaletteCommands,
  resetPaletteRegistry,
  type PaletteCommand,
} from "../../../shared/command-palette/registry";
import type { AILaunchCommand } from "../../../shared/command-palette/aiCommands";
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
  },
  emits: ["update:open", "escapeKeyDown"],
  template: `<div v-if="open" data-testid="palette-dialog" @keydown.esc="$emit('escapeKeyDown', $event)"><Command><slot /></Command></div>`,
});

function livePlugin(live: LiveInterface) {
  return {
    install(app: App) {
      app.config.globalProperties.$live = live;
    },
  };
}

function mountPalette() {
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
  });
  const wrapper = mount(CommandPalette, {
    attachTo: document.body,
    global: {
      plugins: [livePlugin(live)],
      provide: { _live_vue: live },
      stubs: { CommandDialog: CommandDialogStub },
    },
  });

  return { live, wrapper };
}

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
    await vi.advanceTimersByTimeAsync(200);
    await nextTick();

    expect(wrapper.find("[data-slot='command-empty']").exists()).toBe(true);
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

  it("survives a dead socket — analytics failures never break the palette", async () => {
    registerPaletteCommands("flows", [command("flows.a")]);
    const { live, wrapper } = mountPalette();
    vi.mocked(live.pushEvent).mockImplementation(() => {
      throw new Error("socket gone");
    });

    pressPaletteShortcut();
    await nextTick();

    expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(true);
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
          operation_id: expect.any(String),
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
          operation_id: expect.any(String),
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
      expect((deleteCalls[0]![1] as { operation_id: string }).operation_id).toBe(
        (deleteCalls[1]![1] as { operation_id: string }).operation_id,
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
      expect((deleteCalls[0]![1] as { operation_id: string }).operation_id).toBe(
        (deleteCalls[1]![1] as { operation_id: string }).operation_id,
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
