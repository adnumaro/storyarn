import { flushPromises, mount } from "@vue/test-utils";
import { createMockLive } from "@app/test/setup";
import type { SequenceAudioTrackRecord } from "@modules/flows/sequence/types";
const live = createMockLive();
vi.mock("@shared/composables/useLive", () => ({ useLive: () => live }));
const uploadFile = vi.fn();
vi.mock("@shared/composables/useUpload", () => ({ useUpload: () => ({ uploadFile }) }));
const { default: Panel } =
  await import("@modules/flows/editor/components/sequence/FlowSequenceAudio.vue");
const { default: Slot } =
  await import("@modules/flows/editor/components/sequence/FlowSequenceAudioSlot.vue");
const inherited: SequenceAudioTrackRecord = {
  id: "music:v1",
  trackKey: "music",
  sequenceId: 1,
  kind: "music",
  assetId: 3,
  volume: 0.8,
};
afterEach(() => vi.clearAllMocks());
it("edits inherited audio as a local override and removes it by identity", async () => {
  const wrapper = mount(Panel, {
    props: { ownerId: 2, data: { tracks: [inherited] }, canEdit: true },
    global: { stubs: { FlowSequenceAudioSlot: true } },
  });
  const slot = wrapper.findAllComponents(Slot).find((s) => s.props("kind") === "music")!;
  slot.vm.$emit("volume", 0.4);
  expect(live.pushEvent).toHaveBeenCalledWith("override_sequence_track", {
    id: 2,
    track_key: "music",
    volume: 0.4,
  });
  slot.vm.$emit("remove");
  expect(live.pushEvent).toHaveBeenCalledWith("remove_sequence_track", {
    id: 2,
    track_key: "music",
  });
  const empty = wrapper.findAllComponents(Slot).find((s) => s.props("kind") === "sfx")!;
  empty.vm.$emit("select", 9);
  expect(live.pushEvent).toHaveBeenCalledWith("upsert_sequence_track", {
    id: 2,
    kind: "sfx",
    asset_id: 9,
  });
  wrapper.unmount();
});
it("does not mutate from read-only controls", () => {
  const wrapper = mount(Panel, {
    props: { ownerId: 2, data: { tracks: [inherited] }, canEdit: false },
    global: { stubs: { FlowSequenceAudioSlot: true } },
  });
  wrapper.findComponent(Slot).vm.$emit("volume", 0.1);
  expect(live.pushEvent).not.toHaveBeenCalled();
  wrapper.unmount();
});
it("keeps an upload in Assets without attaching it after its intervention has been left", async () => {
  let complete!: (asset: { id: number; url: string }) => void;
  uploadFile.mockReturnValue(
    new Promise((resolve) => {
      complete = resolve;
    }),
  );
  const wrapper = mount(Slot, {
    props: { kind: "music", canEdit: true },
    global: { stubs: { AssetPicker: { template: '<div><slot name="trigger" /></div>' } } },
  });
  const input = wrapper.get<HTMLInputElement>('input[type="file"]');
  Object.defineProperty(input.element, "files", {
    value: [new File(["audio"], "music.mp3", { type: "audio/mpeg" })],
  });
  await input.trigger("change");
  wrapper.unmount();
  complete({ id: 10, url: "/media/assets/10" });
  await flushPromises();
  expect(wrapper.emitted("select")).toBeUndefined();
});
