import { mount } from "@vue/test-utils";
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
  emits: ["update:open"],
  template: `<div v-if="open" data-testid="palette-dialog"><Command><slot /></Command></div>`,
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

function command(id: string, run: () => void = () => undefined): PaletteCommand {
  return {
    id,
    labelKey: `label.${id}`,
    groupKey: "palette.groups.navigation",
    run,
  };
}

describe("CommandPalette", () => {
  beforeEach(() => {
    setTestLocale("en");
    resetPaletteRegistry();
  });

  afterEach(() => {
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
    registerPaletteCommands("flows", [command("flows.run-me", () => (ran = true))]);

    const { live, wrapper } = mountPalette();
    pressPaletteShortcut();
    await nextTick();

    wrapper.findComponent(CommandItem).vm.$emit("select", new Event("select"));
    await nextTick();

    expect(ran).toBe(true);
    expect(live.pushEvent).toHaveBeenCalledWith(
      "palette_command_executed",
      { command_id: "flows.run-me", surface: "flows" },
      undefined,
    );
    expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(false);
  });

  it("tracks a no-results search with the query length only", async () => {
    registerPaletteCommands("flows", [command("flows.a")]);
    const { live, wrapper } = mountPalette();

    pressPaletteShortcut();
    await nextTick();

    await wrapper.find("[data-slot='command-input']").setValue("zzzz");
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

      selectItem(wrapper, "create-target-11");
      await nextTick();

      expect(live.pushEvent).toHaveBeenCalledWith(
        "palette_create",
        { type: "sheet", project_id: 11 },
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

    it("shows an explicit empty state when no project accepts new content", async () => {
      const { live, wrapper } = mountPalette();
      createReplyMock(live, { targets: [] });

      pressPaletteShortcut();
      await nextTick();
      selectItem(wrapper, "create.flow");
      await nextTick();

      expect(wrapper.text()).toContain("No projects where you can create content");
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
        { type: "sheet", id: 7, project_id: 11 },
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
    });

    it("a mutation reply arriving after close is discarded", async () => {
      const { live, wrapper } = mountPalette();
      let deleteCallback: ((reply: { deleted: boolean }) => void) | null = null;

      vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
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

      deleteCallback!({ deleted: true });
      await nextTick();

      // The stale reply must not reopen state or track an execution.
      expect(wrapper.find('[data-testid="palette-dialog"]').exists()).toBe(false);

      const executedCalls = vi
        .mocked(live.pushEvent)
        .mock.calls.filter(([event]) => event === "palette_command_executed");
      expect(executedCalls).toHaveLength(0);
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
