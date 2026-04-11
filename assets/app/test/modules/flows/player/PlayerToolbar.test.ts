import { describe, it, expect } from "vitest";
import { mount } from "@vue/test-utils";
import PlayerToolbar from "@modules/flows/player/PlayerToolbar.vue";

function mountToolbar(overrides: Record<string, unknown> = {}) {
  return mount(PlayerToolbar, {
    props: {
      canGoBack: false,
      showContinue: false,
      playerMode: "player" as const,
      isFinished: false,
      editorUrl: "/workspaces/ws/projects/proj/flows/123",
      ...overrides,
    },
  });
}

describe("PlayerToolbar", () => {
  describe("basic structure", () => {
    it("renders toolbar with left, center, and right sections", () => {
      const w = mountToolbar();

      expect(w.find(".player-toolbar").exists()).toBe(true);
      expect(w.find(".player-toolbar-left").exists()).toBe(true);
      expect(w.find(".player-toolbar-center").exists()).toBe(true);
      expect(w.find(".player-toolbar-right").exists()).toBe(true);
    });
  });

  describe("go back button", () => {
    it("is disabled when canGoBack is false", () => {
      const w = mountToolbar({ canGoBack: false });
      const btn = w.findAll("button").find((b) => b.attributes("title") === "Back")!;
      expect(btn.attributes("disabled")).toBeDefined();
    });

    it("is enabled when canGoBack is true", () => {
      const w = mountToolbar({ canGoBack: true });
      const btn = w.findAll("button").find((b) => b.attributes("title") === "Back")!;
      expect(btn.attributes("disabled")).toBeUndefined();
    });

    it("emits go-back on click", async () => {
      const w = mountToolbar({ canGoBack: true });
      const btn = w.findAll("button").find((b) => b.attributes("title") === "Back")!;
      await btn.trigger("click");
      expect(w.emitted("go-back")).toHaveLength(1);
    });
  });

  describe("continue button", () => {
    it("shows when showContinue is true and not finished", () => {
      const w = mountToolbar({ showContinue: true, isFinished: false });
      const btn = w.findAll("button").find((b) => b.attributes("title") === "Continue");
      expect(btn).toBeDefined();
    });

    it("hides when showContinue is false", () => {
      const w = mountToolbar({ showContinue: false });
      const btn = w.findAll("button").find((b) => b.attributes("title") === "Continue");
      expect(btn).toBeUndefined();
    });

    it("hides when isFinished is true", () => {
      const w = mountToolbar({ showContinue: true, isFinished: true });
      const btn = w.findAll("button").find((b) => b.attributes("title") === "Continue");
      expect(btn).toBeUndefined();
    });

    it("emits continue on click", async () => {
      const w = mountToolbar({ showContinue: true, isFinished: false });
      const btn = w.findAll("button").find((b) => b.attributes("title") === "Continue")!;
      await btn.trigger("click");
      expect(w.emitted("continue")).toHaveLength(1);
    });
  });

  describe("mode toggle", () => {
    it("emits toggle-mode on click", async () => {
      const w = mountToolbar();
      const toggle = w.find(".player-toolbar-btn-mode");
      await toggle.trigger("click");
      expect(w.emitted("toggle-mode")).toHaveLength(1);
    });

    it("shows Player label in player mode", () => {
      const w = mountToolbar({ playerMode: "player" });
      expect(w.find(".player-toolbar-btn-mode").text()).toContain("Player");
    });

    it("shows Analysis label in analysis mode", () => {
      const w = mountToolbar({ playerMode: "analysis" });
      expect(w.find(".player-toolbar-btn-mode").text()).toContain("Analysis");
    });
  });

  describe("restart button", () => {
    it("renders and emits restart", async () => {
      const w = mountToolbar();
      const btn = w.findAll("button").find((b) => b.attributes("title") === "Restart")!;
      expect(btn).toBeDefined();
      await btn.trigger("click");
      expect(w.emitted("restart")).toHaveLength(1);
    });
  });

  describe("back to editor link", () => {
    it("renders link with correct URL", () => {
      const w = mountToolbar({ editorUrl: "/workspaces/my-ws/projects/my-proj/flows/flow-xyz" });
      const link = w.find("a[title='Back to editor']");
      expect(link.attributes("href")).toBe("/workspaces/my-ws/projects/my-proj/flows/flow-xyz");
    });
  });
});
