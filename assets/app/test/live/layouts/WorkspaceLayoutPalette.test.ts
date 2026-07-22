import { mount } from "@vue/test-utils";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { defineComponent, nextTick } from "vue";
import WorkspaceLayout from "../../../live/layouts/workspace/Layout.vue";
import { paletteGroups, resetPaletteRegistry } from "../../../shared/command-palette/registry";
import { setTestLocale } from "../../setup";

const WorkspaceSidebarStub = defineComponent({
  name: "WorkspaceSidebar",
  template: "<nav />",
});

const OnboardingDialogStub = defineComponent({
  name: "OnboardingDialog",
  template: "<div />",
});

type MediaListener = (event: { matches: boolean }) => void;

// jsdom has no matchMedia; a controllable fake lets tests cross the desktop
// breakpoint that decides whether the sidebar toggle can execute at all.
function stubMatchMedia(initialMatches: boolean) {
  const listeners = new Set<MediaListener>();
  const mediaQueryList = {
    matches: initialMatches,
    addEventListener: (_event: string, listener: MediaListener) => listeners.add(listener),
    removeEventListener: (_event: string, listener: MediaListener) => listeners.delete(listener),
  };

  vi.stubGlobal("matchMedia", vi.fn().mockReturnValue(mediaQueryList as unknown as MediaQueryList));

  return {
    setMatches(matches: boolean): void {
      mediaQueryList.matches = matches;
      listeners.forEach((listener) => listener({ matches }));
    },
  };
}

function mountLayout() {
  return mount(WorkspaceLayout, {
    props: {
      currentUser: { id: 1, email: "user@example.com" },
      workspaces: [
        { id: 1, slug: "current-ws", name: "Current WS" },
        { id: 2, slug: "other-ws", name: "Other WS" },
      ],
      currentWorkspaceSlug: "current-ws",
    },
    global: {
      stubs: {
        WorkspaceSidebar: WorkspaceSidebarStub,
        OnboardingDialog: OnboardingDialogStub,
      },
    },
  });
}

function allCommandIds(): string[] {
  return paletteGroups.value.flatMap((group) => group.commands.map((command) => command.id));
}

describe("workspace layout palette commands", () => {
  beforeEach(() => {
    setTestLocale("en");
    resetPaletteRegistry();
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("on desktop the force-open sidebar toggle is NOT listed (it cannot execute)", async () => {
    stubMatchMedia(true);
    mountLayout();
    await nextTick();

    const ids = allCommandIds();
    expect(ids).not.toContain("workspace.toggle-sidebar");
  });

  it("below the breakpoint the toggle is listed and actually toggles the sidebar", async () => {
    stubMatchMedia(false);
    const wrapper = mountLayout();
    await nextTick();

    const findToggle = () =>
      paletteGroups.value
        .flatMap((group) => group.commands)
        .find((command) => command.id === "workspace.toggle-sidebar");

    const toggle = findToggle();
    expect(toggle).toBeDefined();
    expect(toggle!.labelKey).toBe("layout.main_sidebar.show_panel");
    expect(toggle).toHaveProperty("run");

    const aside = wrapper.find("aside");
    expect(aside.attributes("aria-hidden")).toBe("true");

    if (!toggle || typeof toggle.run !== "function") throw new Error("Expected an action command");
    toggle.run();
    await nextTick();

    expect(aside.attributes("aria-hidden")).toBe("false");
    // The command's label mirrors the toolbar button's state naming.
    expect(findToggle()!.labelKey).toBe("layout.main_sidebar.hide_panel");
  });

  it("crossing the breakpoint registers/unregisters the toggle live", async () => {
    const media = stubMatchMedia(true);
    mountLayout();
    await nextTick();

    expect(allCommandIds()).not.toContain("workspace.toggle-sidebar");

    media.setMatches(false);
    await nextTick();

    expect(allCommandIds()).toContain("workspace.toggle-sidebar");

    media.setMatches(true);
    await nextTick();

    expect(allCommandIds()).not.toContain("workspace.toggle-sidebar");
  });

  it("unmount removes every workspace command", async () => {
    stubMatchMedia(false);
    const wrapper = mountLayout();
    await nextTick();

    wrapper.unmount();

    expect(allCommandIds()).toEqual([]);
  });
});
