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

    const items = wrapper.findAll("[data-slot='command-item']");
    expect(items).toHaveLength(1);
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
});
