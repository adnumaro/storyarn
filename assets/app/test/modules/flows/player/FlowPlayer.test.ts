import { createMockLive } from "../../../setup";
import { mount } from "@vue/test-utils";
import { nextTick } from "vue";

const mockLive = createMockLive();

vi.mock("@shared/composables/useLive", () => ({
  useLive: () => mockLive,
}));

const { default: FlowPlayer } = await import("@app/live/flow/player/FlowPlayer.vue");

function defaultProps() {
  return {
    slide: {
      type: "dialogue" as const,
      speaker_name: "Jaime",
      speaker_initials: "JA",
      speaker_avatar_url: null,
      speaker_color: "#8b5cf6",
      text: "<p>Hello!</p>",
      stage_directions: "",
    },
    playerMode: "player" as const,
    canGoBack: false,
    showContinue: true,
    isFinished: false,
    backgrounds: [] as Array<{
      sequence_id?: string | number;
      url: string;
      position?: string | null;
      fit?: "cover" | "contain" | "fill" | null;
      depth?: number | null;
    }>,
    audioTracks: [] as Array<{
      id: string | number;
      sequence_id?: string | number;
      kind: string;
      url: string;
      volume?: number | null;
      depth?: number | null;
    }>,
    editorUrl: "/flows/123",
    responses: [] as Array<{
      id: string;
      text: string;
      valid: boolean;
      number: number;
      has_condition: boolean;
    }>,
  };
}

let wrapper: ReturnType<typeof mount> | null = null;

function mountPlayer(overrides: Record<string, unknown> = {}) {
  wrapper = mount(FlowPlayer, {
    props: { ...defaultProps(), ...overrides },
  });
  return wrapper;
}

describe("FlowPlayer", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    wrapper?.unmount();
    wrapper = null;
  });

  describe("rendering", () => {
    it("renders dialogue slide", () => {
      const w = mountPlayer();
      expect(w.find(".player-slide-dialogue").exists()).toBe(true);
      expect(w.find(".player-toolbar").exists()).toBe(true);
    });

    it("renders outcome slide when type is outcome", () => {
      const w = mountPlayer({
        slide: {
          type: "outcome" as const,
          label: "The End",
          outcome_color: null,
          outcome_tags: [],
          step_count: 5,
          choices_made: 2,
          variables_changed: 1,
        },
      });

      expect(w.find(".player-slide-outcome").exists()).toBe(true);
      expect(w.find(".player-slide-dialogue").exists()).toBe(false);
    });

    it("renders player background layers ordered by sequence depth", () => {
      const w = mountPlayer({
        backgrounds: [
          { sequence_id: 10, url: "/outer.png", position: "top-left", fit: "cover", depth: 0 },
          { sequence_id: 11, url: "/inner.png", position: "top-right", fit: "contain", depth: 1 },
        ],
      });
      const backdrops = w.findAll(".player-backdrop");
      expect(backdrops).toHaveLength(2);
      expect(backdrops[0]!.element.tagName).toBe("IMG");
      expect(backdrops[0]!.attributes("src")).toBe("/outer.png");
      expect(backdrops[0]!.attributes("style")).toContain("object-fit: cover");
      expect(backdrops[0]!.attributes("style")).toContain("object-position: top left");
      expect(backdrops[1]!.attributes("src")).toBe("/inner.png");
      expect(backdrops[1]!.attributes("style")).toContain("object-fit: contain");
      expect(backdrops[1]!.attributes("style")).toContain("object-position: top right");
      expect(backdrops[1]!.attributes("data-depth")).toBe("1");
    });

    it("hides player background when URL is null", () => {
      const w = mountPlayer({ backgrounds: [] });
      expect(w.find(".player-backdrop").exists()).toBe(false);
    });

    it("renders sequence audio tracks", async () => {
      const playSpy = vi.spyOn(window.HTMLMediaElement.prototype, "play").mockResolvedValue();
      const pauseSpy = vi
        .spyOn(window.HTMLMediaElement.prototype, "pause")
        .mockImplementation(() => {});

      const w = mountPlayer({
        audioTracks: [
          {
            id: 5,
            sequence_id: 10,
            kind: "music",
            url: "/theme.mp3",
            volume: 0.5,
            depth: 1,
          },
        ],
      });

      const audio = w.find(".player-audio-tracks audio");
      expect(audio.exists()).toBe(true);
      expect(audio.attributes("src")).toBe("/theme.mp3");
      expect(audio.attributes("data-kind")).toBe("music");
      expect(audio.attributes("data-depth")).toBe("1");
      expect(audio.attributes("loop")).toBeDefined();
      expect(audio.attributes("autoplay")).toBeDefined();
      await nextTick();
      expect(playSpy).toHaveBeenCalled();

      w.unmount();
      wrapper = null;
      playSpy.mockRestore();
      pauseSpy.mockRestore();
    });
  });

  describe("events via pushEvent", () => {
    it("pushes continue event", async () => {
      const w = mountPlayer({ showContinue: true, isFinished: false });
      const btn = w.find(".player-response-continue");
      await btn.trigger("click");
      expect(mockLive.pushEvent).toHaveBeenCalledWith("continue", {});
    });

    it("pushes go_back event", async () => {
      const w = mountPlayer({ canGoBack: true });
      const btn = w.find(".player-toolbar-left").findAll("button")[0]!;
      await btn.trigger("click");
      expect(mockLive.pushEvent).toHaveBeenCalledWith("go_back", {});
    });

    it("pushes toggle_mode event", async () => {
      const w = mountPlayer();
      const btn = w.find(".player-toolbar-btn-mode");
      await btn.trigger("click");
      expect(mockLive.pushEvent).toHaveBeenCalledWith("toggle_mode", {});
    });

    it("pushes restart event", async () => {
      const w = mountPlayer();
      const btn = w.find(".player-toolbar-right").findAll("button")[0]!;
      await btn.trigger("click");
      expect(mockLive.pushEvent).toHaveBeenCalledWith("restart", {});
    });

    it("pushes choose_response event on choice click", async () => {
      const w = mountPlayer({
        responses: [{ id: "r1", text: "Go", valid: true, number: 1, has_condition: false }],
      });

      const choiceBtn = w.find(".player-response");
      await choiceBtn.trigger("click");
      expect(mockLive.pushEvent).toHaveBeenCalledWith("choose_response", { id: "r1" });
    });
  });

  describe("keyboard shortcuts", () => {
    it("pushes continue on Space key", () => {
      mountPlayer({ showContinue: true, isFinished: false });
      document.dispatchEvent(new KeyboardEvent("keydown", { key: " " }));
      expect(mockLive.pushEvent).toHaveBeenCalledWith("continue", {});
    });

    it("pushes go_back on ArrowLeft", () => {
      mountPlayer({ canGoBack: true });
      document.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowLeft" }));
      expect(mockLive.pushEvent).toHaveBeenCalledWith("go_back", {});
    });

    it("pushes exit_player on Escape", () => {
      mountPlayer();
      document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
      expect(mockLive.pushEvent).toHaveBeenCalledWith("exit_player", {});
    });

    it("pushes toggle_mode on P key", () => {
      mountPlayer();
      document.dispatchEvent(new KeyboardEvent("keydown", { key: "p" }));
      expect(mockLive.pushEvent).toHaveBeenCalledWith("toggle_mode", {});
    });

    it("pushes restart on R key", () => {
      mountPlayer();
      document.dispatchEvent(new KeyboardEvent("keydown", { key: "r" }));
      expect(mockLive.pushEvent).toHaveBeenCalledWith("restart", {});
    });

    it("chooses response by number key", () => {
      mountPlayer({
        responses: [
          { id: "r1", text: "First", valid: true, number: 1, has_condition: false },
          { id: "r2", text: "Second", valid: true, number: 2, has_condition: false },
        ],
      });

      document.dispatchEvent(new KeyboardEvent("keydown", { key: "2" }));
      expect(mockLive.pushEvent).toHaveBeenCalledWith("choose_response", { id: "r2" });
    });

    it("ignores number keys for out-of-range responses", () => {
      mountPlayer({
        responses: [{ id: "r1", text: "Only", valid: true, number: 1, has_condition: false }],
      });

      document.dispatchEvent(new KeyboardEvent("keydown", { key: "5" }));
      expect(mockLive.pushEvent).not.toHaveBeenCalledWith("choose_response", expect.anything());
    });

    it("does not push continue when showContinue is false", () => {
      mountPlayer({ showContinue: false });
      document.dispatchEvent(new KeyboardEvent("keydown", { key: " " }));
      expect(mockLive.pushEvent).not.toHaveBeenCalledWith("continue", expect.anything());
    });
  });
});
