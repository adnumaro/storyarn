import { flushPromises, mount } from "@vue/test-utils";
import DialogueVoice from "@modules/flows/player/components/DialogueVoice.vue";
import type { SequenceDialogueVoice } from "@modules/flows/sequence/types";

function voice(overrides: Partial<SequenceDialogueVoice> = {}): SequenceDialogueVoice {
  return {
    id: "dialogue-42:asset-901",
    continuityKey: "dialogue-42:asset-901",
    nodeId: 42,
    url: "/media/assets/901",
    volume: 1,
    ...overrides,
  };
}

describe("DialogueVoice", () => {
  let playSpy: ReturnType<typeof vi.spyOn>;
  let pauseSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    playSpy = vi.spyOn(HTMLMediaElement.prototype, "play").mockResolvedValue();
    pauseSpy = vi.spyOn(HTMLMediaElement.prototype, "pause").mockImplementation(() => {});
  });

  afterEach(() => {
    playSpy.mockRestore();
    pauseSpy.mockRestore();
  });

  it("plays dialogue voice once without looping", async () => {
    const wrapper = mount(DialogueVoice, { props: { voice: voice() } });
    await flushPromises();

    const audio = wrapper.get("audio");
    expect(audio.attributes("autoplay")).toBeDefined();
    expect(audio.attributes("loop")).toBeUndefined();
    expect(audio.attributes("data-node-id")).toBe("42");
    expect(playSpy).toHaveBeenCalled();

    wrapper.unmount();
  });

  it("supports an explicit editor preview without autoplay", async () => {
    const wrapper = mount(DialogueVoice, {
      props: { voice: voice(), autoplay: false },
    });
    await flushPromises();

    expect(wrapper.get("audio").attributes("autoplay")).toBeUndefined();
    expect(playSpy).not.toHaveBeenCalled();

    (wrapper.vm as unknown as { play: () => void }).play();
    await flushPromises();
    expect(playSpy).toHaveBeenCalledTimes(1);
    expect(wrapper.emitted("playing-change")?.at(-1)).toEqual([true]);

    (wrapper.vm as unknown as { pause: () => void }).pause();
    expect(pauseSpy).toHaveBeenCalled();
    expect(wrapper.emitted("playing-change")?.at(-1)).toEqual([false]);

    wrapper.unmount();
  });

  it("stops the current voice synchronously", async () => {
    const wrapper = mount(DialogueVoice, { props: { voice: voice() } });
    await flushPromises();
    const audio = wrapper.get("audio").element as HTMLAudioElement;
    audio.currentTime = 8;
    pauseSpy.mockClear();

    (wrapper.vm as unknown as { stop: () => void }).stop();

    expect(pauseSpy).toHaveBeenCalledTimes(1);
    expect(audio.currentTime).toBe(0);

    wrapper.unmount();
  });

  it("does not restart a scheduled autoplay after it is stopped", async () => {
    const wrapper = mount(DialogueVoice, { props: { voice: voice() } });

    (wrapper.vm as unknown as { stop: () => void }).stop();
    await flushPromises();

    expect(playSpy).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it("stops the previous voice before replacing its identity", async () => {
    const wrapper = mount(DialogueVoice, { props: { voice: voice() } });
    await flushPromises();
    const original = wrapper.get("audio").element;
    pauseSpy.mockClear();

    await wrapper.setProps({
      voice: voice({
        id: "dialogue-43:asset-902",
        continuityKey: "dialogue-43:asset-902",
        nodeId: 43,
        url: "/media/assets/902",
      }),
    });
    await flushPromises();

    expect(pauseSpy).toHaveBeenCalled();
    expect(wrapper.get("audio").element).not.toBe(original);

    wrapper.unmount();
  });

  it("does not mount media when the source voice is unavailable", () => {
    const wrapper = mount(DialogueVoice, {
      props: {
        voice: voice({
          id: "dialogue-42:source",
          continuityKey: "dialogue-42:source:none",
          available: false,
          assetId: null,
          url: null,
        }),
      },
    });

    expect(wrapper.find("audio").exists()).toBe(false);
    expect(playSpy).not.toHaveBeenCalled();
    wrapper.unmount();
  });
});
