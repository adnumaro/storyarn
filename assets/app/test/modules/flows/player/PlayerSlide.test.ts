import { describe, it, expect } from "vitest";
import { mount, flushPromises } from "@vue/test-utils";
import PlayerSlide from "@modules/flows/player/PlayerSlide.vue";
import type { SlideData } from "@modules/flows/player/PlayerSlide.vue";

async function mountSlide(slide: SlideData) {
  const w = mount(PlayerSlide, { props: { slide } });
  await flushPromises();
  return w;
}

describe("PlayerSlide", () => {
  describe("dialogue type", () => {
    it("renders speaker info and text", async () => {
      const w = await mountSlide({
        type: "dialogue",
        speaker_name: "Jaime",
        speaker_initials: "JA",
        speaker_avatar_url: null,
        speaker_color: "#8b5cf6",
        text: "<p>Hello, traveler!</p>",
        stage_directions: "",
      });

      expect(w.find(".player-slide-dialogue").exists()).toBe(true);
      expect(w.find(".player-speaker").exists()).toBe(true);
      expect(w.text()).toContain("JA");
      expect(w.text()).toContain("Jaime");
      expect(w.find(".player-text").html()).toContain("Hello, traveler!");
    });

    it("renders speaker avatar image when URL is provided", async () => {
      const w = await mountSlide({
        type: "dialogue",
        speaker_name: "Luna",
        speaker_initials: "LU",
        speaker_avatar_url: "/avatar.png",
        speaker_color: null,
        text: "<p>Hi</p>",
        stage_directions: "",
      });

      const img = w.find("[data-slot='avatar'] img");
      expect(img.exists()).toBe(true);
      expect(img.attributes("src")).toBe("/avatar.png");
    });

    it("renders initials fallback with color when no avatar URL", async () => {
      const w = await mountSlide({
        type: "dialogue",
        speaker_name: "Luna",
        speaker_initials: "LU",
        speaker_avatar_url: null,
        speaker_color: "#22c55e",
        text: "<p>Greetings.</p>",
        stage_directions: "",
      });

      const fallback = w.find("[data-slot='avatar-fallback']");
      expect(fallback.text()).toBe("LU");
      expect(fallback.attributes("style")).toMatch(
        /background-color:.*22c55e|background-color: rgb\(34, 197, 94\)/,
      );
    });

    it("renders without speaker color when nil", async () => {
      const w = await mountSlide({
        type: "dialogue",
        speaker_name: "Unknown",
        speaker_initials: "UN",
        speaker_avatar_url: null,
        speaker_color: null,
        text: "<p>Who?</p>",
        stage_directions: "",
      });

      const fallback = w.find("[data-slot='avatar-fallback']");
      expect(fallback.attributes("style")).toBeUndefined();
    });

    it("hides speaker name when null", async () => {
      const w = await mountSlide({
        type: "dialogue",
        speaker_name: null,
        speaker_initials: "??",
        speaker_avatar_url: null,
        speaker_color: null,
        text: "<p>Narrator</p>",
        stage_directions: "",
      });

      expect(w.find(".player-speaker-name").exists()).toBe(false);
    });

    it("renders stage directions when present", async () => {
      const w = await mountSlide({
        type: "dialogue",
        speaker_name: "Jaime",
        speaker_initials: "JA",
        speaker_avatar_url: null,
        speaker_color: null,
        text: "<p>I see...</p>",
        stage_directions: "looks away nervously",
      });

      expect(w.find(".player-stage-directions").exists()).toBe(true);
      expect(w.text()).toContain("looks away nervously");
    });

    it("hides stage directions when empty", async () => {
      const w = await mountSlide({
        type: "dialogue",
        speaker_name: "Jaime",
        speaker_initials: "JA",
        speaker_avatar_url: null,
        speaker_color: null,
        text: "<p>Hello</p>",
        stage_directions: "",
      });

      expect(w.find(".player-stage-directions").exists()).toBe(false);
    });

    it("preserves rich text formatting via v-html", async () => {
      const w = await mountSlide({
        type: "dialogue",
        speaker_name: "Narrator",
        speaker_initials: "NA",
        speaker_avatar_url: null,
        speaker_color: null,
        text: "<p>This is <strong>bold</strong> and <em>italic</em> text.</p>",
        stage_directions: "",
      });

      const html = w.find(".player-text").html();
      expect(html).toContain("<strong>bold</strong>");
      expect(html).toContain("<em>italic</em>");
    });
  });

  describe("empty type", () => {
    it("renders empty slide with message", async () => {
      const w = await mountSlide({ type: "empty" });

      expect(w.find(".player-slide-empty").exists()).toBe(true);
      expect(w.text()).toContain("No content to display");
    });
  });

  describe("fallback (unknown type)", () => {
    it("renders empty div for unknown type", async () => {
      const w = await mountSlide({ type: "unknown" as SlideData["type"] });

      expect(w.find(".player-slide").exists()).toBe(true);
      expect(w.find(".player-slide-dialogue").exists()).toBe(false);
      expect(w.find(".player-slide-slug-line").exists()).toBe(false);
      expect(w.find(".player-slide-empty").exists()).toBe(false);
    });
  });
});
