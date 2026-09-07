import { mount } from "@vue/test-utils";
import FlowSequencePlayback from "@modules/flows/editor/components/sequence/FlowSequencePlayback.vue";
import type { SequencePlaybackState } from "@modules/flows/editor/components/sequence/sequence-playback";

function state(): SequencePlaybackState {
  return {
    slide: {
      type: "dialogue",
      speaker_name: "Aria",
      text: "<p>Hello</p>",
      responses: [
        { id: "yes", text: "Yes", valid: true, number: 1, has_condition: false },
        { id: "locked", text: "Locked response", valid: false, number: 2, has_condition: true },
      ],
    },
    visualLayers: [],
    audioTracks: [],
    voice: null,
    canGoBack: false,
    showContinue: false,
    isFinished: false,
    error: null,
  };
}

function player(overrides: Partial<SequencePlaybackState> = {}) {
  return mount(FlowSequencePlayback, {
    props: { state: { ...state(), ...overrides } },
  });
}

describe("FlowSequencePlayback", () => {
  beforeEach(() => {
    vi.spyOn(HTMLMediaElement.prototype, "play").mockResolvedValue();
    vi.spyOn(HTMLMediaElement.prototype, "pause").mockImplementation(() => {});
  });
  afterEach(() => vi.restoreAllMocks());

  it("renders stage directions as plain text beneath the dialogue and omits empty directions", async () => {
    const wrapper = player({
      slide: { type: "dialogue", text: "Hello", stage_directions: "<quietly> Look away" },
    });
    const directions = wrapper.get("[data-playback-stage-directions]");
    expect(directions.text()).toBe("<quietly> Look away");
    expect(directions.find("quietly").exists()).toBe(false);
    expect(directions.element.previousElementSibling?.textContent).toBe("Hello");
    await wrapper.setProps({ state: state() });
    expect(wrapper.find("[data-playback-stage-directions]").exists()).toBe(false);
    wrapper.unmount();
  });

  it("shows only valid choices inside a clipped frame and emits the chosen response", async () => {
    const wrapper = player();
    expect(wrapper.get("[data-playback-frame]").classes()).toContain("overflow-hidden");
    expect(wrapper.findAll("[data-playback-response]")).toHaveLength(1);
    expect(wrapper.text()).toContain("Hello");
    expect(wrapper.find("[data-sequence-layer-controls]").exists()).toBe(false);
    await wrapper.get('[data-playback-response="yes"]').trigger("click");
    expect(wrapper.emitted("action")).toEqual([["choose", "yes"]]);
    await wrapper.setProps({ pending: true });
    expect(wrapper.get('[data-playback-response="yes"]').attributes("disabled")).toBeDefined();
    wrapper.unmount();
  });

  it("advances, goes back and restarts without links or a new route", async () => {
    const wrapper = player({
      slide: { type: "dialogue", text: "Hello", responses: [] },
      showContinue: true,
      canGoBack: true,
    });
    await wrapper.get("[data-playback-continue]").trigger("click");
    await wrapper.get("[data-playback-back]").trigger("click");
    await wrapper.get("[data-playback-restart]").trigger("click");
    expect(wrapper.emitted("action")).toEqual([["continue"], ["back"], ["restart"]]);
    expect(wrapper.findAll("a")).toHaveLength(0);
    await wrapper.setProps({
      state: { ...state(), isFinished: true, slide: { type: "outcome", label: "The end" } },
    });
    expect(wrapper.text()).toContain("The end");
    expect(wrapper.find("[data-playback-continue]").exists()).toBe(false);
    expect(wrapper.findAll("[data-playback-response]")).toHaveLength(0);
    await wrapper.get("[data-playback-play-again]").trigger("click");
    expect(wrapper.emitted("action")?.at(-1)).toEqual(["restart"]);
    wrapper.unmount();
  });

  it("stops the previous voice when advancing and when the player is closed", async () => {
    const pause = vi.spyOn(HTMLMediaElement.prototype, "pause").mockImplementation(() => {});
    const wrapper = player({ voice: { key: "visit-1", url: "/voice.mp3" } });
    const first = wrapper.get("audio").element;
    expect(first.loop).toBe(false);
    await wrapper.setProps({ state: { ...state(), voice: { key: "visit-2", url: "/voice.mp3" } } });
    expect(wrapper.get("audio").element).not.toBe(first);
    expect(pause).toHaveBeenCalled();
    pause.mockClear();
    wrapper.unmount();
    expect(pause).toHaveBeenCalled();
  });

  it("loops background audio, plays effects once and stops all tracks on close", async () => {
    vi.spyOn(HTMLMediaElement.prototype, "play").mockResolvedValue();
    const pause = vi.spyOn(HTMLMediaElement.prototype, "pause").mockImplementation(() => {});
    const wrapper = mount(FlowSequencePlayback, {
      props: {
        state: {
          ...state(),
          audioTracks: [
            { id: "music", kind: "music", url: "/music.mp3" },
            { id: "effect", kind: "sfx", url: "/effect.mp3" },
          ],
        },
      },
    });
    expect(wrapper.get<HTMLAudioElement>('audio[data-kind="music"]').element.loop).toBe(true);
    expect(wrapper.get<HTMLAudioElement>('audio[data-kind="sfx"]').element.loop).toBe(false);
    wrapper.unmount();
    expect(pause).toHaveBeenCalledTimes(2);
  });
  it("supports numbered choices and navigation without handling keys from controls", async () => {
    const wrapper = player({ canGoBack: true });
    const viewport = wrapper.get("[data-playback-viewport]");
    await viewport.trigger("keydown", { key: "1" });
    await viewport.trigger("keydown", { key: "2" });
    await viewport.trigger("keydown", { key: "ArrowLeft" });
    expect(wrapper.emitted("action")).toEqual([["choose", "yes"], ["back"]]);
    await wrapper.get("[data-playback-response]").trigger("keydown", { key: "1" });
    expect(wrapper.emitted("action")).toHaveLength(2);
    await wrapper.setProps({ pending: true });
    await viewport.trigger("keydown", { key: "1" });
    expect(wrapper.emitted("action")).toHaveLength(2);
    wrapper.unmount();
  });
});
