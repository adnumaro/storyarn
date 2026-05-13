import { describe, it, expect } from "vitest";
import { mount } from "@vue/test-utils";
import PlayerToolbar from "../../../../modules/flows/player/components/PlayerToolbar.vue";

function mountToolbar(overrides: Record<string, unknown> = {}) {
  return mount(PlayerToolbar, {
    props: {
      canGoBack: false,
      playerMode: "player" as const,
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
      const btn = w.find(".player-toolbar-left").findAll("button")[0]!;
      expect(btn.attributes("disabled")).toBeDefined();
    });

    it("is enabled when canGoBack is true", () => {
      const w = mountToolbar({ canGoBack: true });
      const btn = w.find(".player-toolbar-left").findAll("button")[0]!;
      expect(btn.attributes("disabled")).toBeUndefined();
    });

    it("emits go-back on click", async () => {
      const w = mountToolbar({ canGoBack: true });
      const btn = w.find(".player-toolbar-left").findAll("button")[0]!;
      await btn.trigger("click");
      expect(w.emitted("go-back")).toHaveLength(1);
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
      const btn = w.find(".player-toolbar-right").findAll("button")[0]!;
      expect(btn).toBeDefined();
      await btn.trigger("click");
      expect(w.emitted("restart")).toHaveLength(1);
    });
  });

  describe("back to editor link", () => {
    it("renders link with correct URL", () => {
      const w = mountToolbar({ editorUrl: "/workspaces/my-ws/projects/my-proj/flows/flow-xyz" });
      const link = w.find(".player-toolbar-right a");
      expect(link.attributes("href")).toBe("/workspaces/my-ws/projects/my-proj/flows/flow-xyz");
    });
  });
});
