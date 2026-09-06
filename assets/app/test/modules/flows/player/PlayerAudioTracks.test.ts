import { flushPromises, mount } from "@vue/test-utils";
import PlayerAudioTracks from "@modules/flows/player/components/PlayerAudioTracks.vue";
import type { SequenceAudioTrack } from "@modules/flows/sequence/types";

function track(overrides: Partial<SequenceAudioTrack> = {}): SequenceAudioTrack {
  return {
    id: 301,
    continuityKey: "room:asset-901",
    sequenceId: 10,
    kind: "ambience",
    url: "/media/assets/901",
    volume: 0.8,
    ...overrides,
  };
}

describe("PlayerAudioTracks", () => {
  let playSpy: ReturnType<typeof vi.spyOn>;
  let pauseSpy: ReturnType<typeof vi.spyOn>;
  let loadSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    playSpy = vi.spyOn(HTMLMediaElement.prototype, "play").mockResolvedValue();
    pauseSpy = vi.spyOn(HTMLMediaElement.prototype, "pause").mockImplementation(() => {});
    loadSpy = vi.spyOn(HTMLMediaElement.prototype, "load").mockImplementation(() => {});
  });

  afterEach(() => {
    playSpy.mockRestore();
    pauseSpy.mockRestore();
    loadSpy.mockRestore();
  });

  it("keeps the same audio element and playback position for a volume-only override", async () => {
    const wrapper = mount(PlayerAudioTracks, { props: { tracks: [track()] } });
    await flushPromises();

    const original = wrapper.get("audio").element as HTMLAudioElement;
    expect(playSpy).toHaveBeenCalledTimes(1);
    original.currentTime = 23;
    pauseSpy.mockClear();

    await wrapper.setProps({
      tracks: [track({ id: 999, continuityKey: "room:asset-901", volume: 0.35 })],
    });
    await flushPromises();

    const updated = wrapper.get("audio").element as HTMLAudioElement;
    expect(updated).toBe(original);
    expect(updated.currentTime).toBe(23);
    expect(updated.volume).toBe(0.35);
    expect(playSpy).toHaveBeenCalledTimes(1);
    expect(pauseSpy).not.toHaveBeenCalled();

    wrapper.unmount();
  });

  it("stops and replaces a track when its serialized asset identity changes", async () => {
    const wrapper = mount(PlayerAudioTracks, { props: { tracks: [track()] } });
    await flushPromises();

    const original = wrapper.get("audio").element as HTMLAudioElement;
    pauseSpy.mockClear();

    await wrapper.setProps({
      tracks: [
        track({
          id: 302,
          continuityKey: "room:asset-902",
          url: "/media/assets/902",
        }),
      ],
    });
    await flushPromises();

    expect(pauseSpy).toHaveBeenCalled();
    expect(wrapper.get("audio").element).not.toBe(original);
    expect(wrapper.get("audio").attributes("src")).toBe("/media/assets/902");

    wrapper.unmount();
  });

  it("stops a track when it is removed", async () => {
    const wrapper = mount(PlayerAudioTracks, { props: { tracks: [track()] } });
    await flushPromises();
    pauseSpy.mockClear();

    await wrapper.setProps({ tracks: [] });
    await flushPromises();

    expect(pauseSpy).toHaveBeenCalled();
    expect(wrapper.find("audio").exists()).toBe(false);

    wrapper.unmount();
  });

  it("falls back to the legacy sequence, kind and row identity", async () => {
    const legacy = track({ continuityKey: undefined });
    const wrapper = mount(PlayerAudioTracks, { props: { tracks: [legacy] } });
    await flushPromises();

    expect(wrapper.get("audio").attributes("data-continuity-key")).toBe("10:ambience:301");

    wrapper.unmount();
  });

  it("reports blocked playback and clears it after an explicit retry", async () => {
    playSpy.mockRejectedValue(new DOMException("Playback blocked", "NotAllowedError"));
    const wrapper = mount(PlayerAudioTracks, { props: { tracks: [track()] } });
    await flushPromises();

    expect(wrapper.emitted("blocked-change")?.at(-1)).toEqual([true]);

    playSpy.mockResolvedValue();
    (wrapper.vm as unknown as { retryBlockedAudio: () => void }).retryBlockedAudio();
    await flushPromises();

    expect(wrapper.emitted("blocked-change")?.at(-1)).toEqual([false]);

    wrapper.unmount();
  });
  it("cancels queued autoplay on Stop and resumes only with the next projection", async () => {
    const wrapper = mount(PlayerAudioTracks, { props: { tracks: [track()] } });
    wrapper.vm.stop();
    await flushPromises();
    expect(playSpy).not.toHaveBeenCalled();
    await wrapper.setProps({ tracks: [track()] });
    await flushPromises();
    expect(playSpy).toHaveBeenCalledTimes(1);
    const audio = wrapper.get("audio").element as HTMLAudioElement;
    audio.currentTime = 17;
    wrapper.vm.stop();
    expect(audio.currentTime).toBe(0);
    wrapper.unmount();
  });

  it("ignores a rejected play promise after that track is stopped", async () => {
    let reject!: (reason?: unknown) => void;
    playSpy.mockReturnValue(
      new Promise<void>((_resolve, failure) => {
        reject = failure;
      }),
    );
    const wrapper = mount(PlayerAudioTracks, { props: { tracks: [track()] } });
    await flushPromises();
    wrapper.vm.stop();
    reject(new DOMException("Old attempt", "NotAllowedError"));
    await flushPromises();
    expect(wrapper.emitted("blocked-change")).toBeUndefined();
    wrapper.unmount();
  });
});
