import { describe, it, expect } from "vitest";
import { mount } from "@vue/test-utils";
import PlayerChoices from "../../../../modules/flows/player/components/PlayerChoices.vue";
import type { ResponseData } from "../../../../modules/flows/player/components/PlayerChoices.vue";

function mountChoices(responses: ResponseData[], playerMode: "player" | "analysis" = "player") {
  return mount(PlayerChoices, {
    props: { responses, playerMode },
  });
}

describe("PlayerChoices", () => {
  describe("player mode", () => {
    it("renders only valid responses", () => {
      const w = mountChoices(
        [
          { id: "r1", text: "Accept", valid: true, number: 1, has_condition: false },
          { id: "r2", text: "Refuse", valid: false, number: 2, has_condition: true },
          { id: "r3", text: "Ask more", valid: true, number: 3, has_condition: false },
        ],
        "player",
      );

      expect(w.text()).toContain("Accept");
      expect(w.text()).toContain("Ask more");
      expect(w.text()).not.toContain("Refuse");
    });

    it("renders response numbers", () => {
      const w = mountChoices(
        [
          { id: "r1", text: "Yes", valid: true, number: 1, has_condition: false },
          { id: "r2", text: "No", valid: true, number: 2, has_condition: false },
        ],
        "player",
      );

      const numbers = w.findAll(".player-response-number");
      expect(numbers[0].text()).toBe("1");
      expect(numbers[1].text()).toBe("2");
    });

    it("does not show condition badge in player mode", () => {
      const w = mountChoices(
        [{ id: "r1", text: "Guarded", valid: true, number: 1, has_condition: true }],
        "player",
      );

      expect(w.find(".player-response-badge").exists()).toBe(false);
    });

    it("emits choose event with response id on click", async () => {
      const w = mountChoices(
        [{ id: "resp-abc", text: "Go", valid: true, number: 1, has_condition: false }],
        "player",
      );

      await w.find("button").trigger("click");
      expect(w.emitted("choose")).toEqual([["resp-abc"]]);
    });

    it("renders nothing when no valid responses", () => {
      const w = mountChoices(
        [
          { id: "r1", text: "Locked", valid: false, number: 1, has_condition: true },
          { id: "r2", text: "Also locked", valid: false, number: 2, has_condition: true },
        ],
        "player",
      );

      expect(w.find(".player-choices").exists()).toBe(false);
    });

    it("renders nothing when responses list is empty", () => {
      const w = mountChoices([], "player");
      expect(w.find(".player-choices").exists()).toBe(false);
    });
  });

  describe("analysis mode", () => {
    it("renders all responses including invalid ones", () => {
      const w = mountChoices(
        [
          { id: "r1", text: "Accept", valid: true, number: 1, has_condition: false },
          { id: "r2", text: "Refuse", valid: false, number: 2, has_condition: true },
        ],
        "analysis",
      );

      expect(w.text()).toContain("Accept");
      expect(w.text()).toContain("Refuse");
    });

    it("marks invalid responses with invalid CSS class", () => {
      const w = mountChoices(
        [{ id: "r1", text: "Invalid", valid: false, number: 1, has_condition: false }],
        "analysis",
      );

      expect(w.find(".player-response-invalid").exists()).toBe(true);
    });

    it("disables invalid response buttons", () => {
      const w = mountChoices(
        [{ id: "r1", text: "Blocked", valid: false, number: 1, has_condition: false }],
        "analysis",
      );

      const btn = w.find("button");
      expect(btn.attributes("disabled")).toBeDefined();
    });

    it("does not disable valid response buttons", () => {
      const w = mountChoices(
        [{ id: "r1", text: "Open", valid: true, number: 1, has_condition: false }],
        "analysis",
      );

      expect(w.find("button").attributes("disabled")).toBeUndefined();
    });

    it("shows condition badge for responses with conditions", () => {
      const w = mountChoices(
        [{ id: "r1", text: "Conditional", valid: true, number: 1, has_condition: true }],
        "analysis",
      );

      expect(w.find(".player-response-badge").exists()).toBe(true);
    });

    it("hides condition badge for responses without conditions", () => {
      const w = mountChoices(
        [{ id: "r1", text: "Simple", valid: true, number: 1, has_condition: false }],
        "analysis",
      );

      expect(w.find(".player-response-badge").exists()).toBe(false);
    });
  });
});
