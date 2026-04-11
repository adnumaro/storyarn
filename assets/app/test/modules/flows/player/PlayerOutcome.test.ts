import { describe, it, expect } from "vitest";
import { mount } from "@vue/test-utils";
import PlayerOutcome from "@modules/flows/player/PlayerOutcome.vue";
import type { OutcomeData } from "@modules/flows/player/PlayerOutcome.vue";

function buildSlide(overrides: Partial<OutcomeData> = {}): OutcomeData {
  return {
    type: "outcome" as const,
    label: "Game Over",
    outcome_color: "#ff0000",
    outcome_tags: ["bad ending", "death"],
    step_count: 12,
    choices_made: 5,
    variables_changed: 3,
    ...overrides,
  };
}

function mountOutcome(slide: OutcomeData = buildSlide(), editorUrl = "/flows/123") {
  return mount(PlayerOutcome, {
    props: { slide, editorUrl },
  });
}

describe("PlayerOutcome", () => {
  describe("basic rendering", () => {
    it("renders outcome with title", () => {
      const w = mountOutcome();

      expect(w.find(".player-slide-outcome").exists()).toBe(true);
      expect(w.find(".player-outcome-title").text()).toBe("Game Over");
    });

    it("renders accent bar with color", () => {
      const w = mountOutcome(buildSlide({ outcome_color: "#22c55e" }));
      const accent = w.find(".player-outcome-accent");
      expect(accent.attributes("style")).toMatch(
        /background-color:.*22c55e|background-color: rgb\(34, 197, 94\)/,
      );
    });

    it("renders accent bar without color when null", () => {
      const w = mountOutcome(buildSlide({ outcome_color: null }));
      const accent = w.find(".player-outcome-accent");
      expect(accent.attributes("style")).toBeUndefined();
    });
  });

  describe("tags", () => {
    it("renders outcome tags as badges", () => {
      const w = mountOutcome(buildSlide({ outcome_tags: ["victory", "heroic"] }));

      expect(w.find(".player-outcome-tags").exists()).toBe(true);
      const badges = w.findAll("[data-slot='badge']");
      expect(badges).toHaveLength(2);
      expect(w.text()).toContain("victory");
      expect(w.text()).toContain("heroic");
    });

    it("hides tags section when empty", () => {
      const w = mountOutcome(buildSlide({ outcome_tags: [] }));
      expect(w.find(".player-outcome-tags").exists()).toBe(false);
    });
  });

  describe("stats", () => {
    it("renders step count", () => {
      const w = mountOutcome(buildSlide({ step_count: 42 }));
      expect(w.text()).toContain("42");
    });

    it("renders choices made", () => {
      const w = mountOutcome(buildSlide({ choices_made: 7 }));
      expect(w.text()).toContain("7");
    });

    it("renders variables changed", () => {
      const w = mountOutcome(buildSlide({ variables_changed: 15 }));
      expect(w.text()).toContain("15");
    });

    it("renders zero stats", () => {
      const w = mountOutcome(buildSlide({ step_count: 0, choices_made: 0, variables_changed: 0 }));
      expect(w.find(".player-outcome-stats").exists()).toBe(true);
    });
  });

  describe("actions", () => {
    it("emits restart on play again click", async () => {
      const w = mountOutcome();
      const btns = w.findAll("[data-slot='button']");
      const playAgain = btns.find((b) => b.text().includes("Play again"))!;
      await playAgain.trigger("click");
      expect(w.emitted("restart")).toHaveLength(1);
    });

    it("renders back to editor link with correct path", () => {
      const w = mountOutcome(buildSlide(), "/workspaces/ws/projects/proj/flows/abc");
      const link = w.find("a");
      expect(link.attributes("href")).toBe("/workspaces/ws/projects/proj/flows/abc");
    });
  });
});
