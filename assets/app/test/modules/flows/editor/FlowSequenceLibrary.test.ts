import { mount } from "@vue/test-utils";
import { nextTick } from "vue";
import FlowSequenceLibrary from "@modules/flows/editor/components/sequence/FlowSequenceLibrary.vue";
import { createMockLive } from "../../../setup";
import {
  parseSequenceLibraryImage,
  SEQUENCE_LIBRARY_IMAGE_MIME,
  type SequenceLibraryImage,
  type SequenceLibrarySheet,
} from "@modules/flows/editor/components/sequence/sequence-library";

const mockLive = createMockLive();
vi.mock("@shared/composables/useLive", () => ({ useLive: () => mockLive }));

const sheets: SequenceLibrarySheet[] = [
  {
    id: 1,
    name: "Aria",
    gallery_images: [{ id: 11, asset_id: 101, url: "/aria.png", label: "Viajera" }],
  },
  {
    id: 2,
    name: "Zora",
    gallery_images: [
      { id: 21, asset_id: 201, url: "/zora.png", label: "Enfadada" },
      { id: 22, asset_id: 202, url: "/zora-happy.png", label: "Sonríe" },
    ],
    avatars: [{ id: 23, asset_id: 203, url: "/zora-avatar.png", name: "Retrato" }],
  },
];

const zoraImage: SequenceLibraryImage = {
  asset_id: 201,
  url: "/zora.png",
  label: "Zora · Enfadada",
  sheet_id: 2,
  source: "gallery",
};

type LibraryProps = InstanceType<typeof FlowSequenceLibrary>["$props"];

function mountLibrary(props: Partial<LibraryProps> = {}) {
  return mount(FlowSequenceLibrary, {
    props: { sheets, canEdit: true, speakerSheetId: "2", ...props },
  });
}

async function switchToAssets(wrapper: ReturnType<typeof mountLibrary>) {
  await wrapper
    .get("[data-library-tab-assets]")
    .trigger("mousedown", { button: 0, ctrlKey: false });
  await wrapper.get("[data-library-tab-assets]").trigger("click");
}

describe("FlowSequenceLibrary", () => {
  it("prioritizes the current speaker and adds the gallery asset rather than its association id", async () => {
    const wrapper = mountLibrary();
    expect(
      wrapper
        .findAll("[data-library-group]")
        .map((group) => group.attributes("data-library-group")),
    ).toEqual(["sheet-2", "sheet-1"]);
    const zora = wrapper.get('[data-library-group="sheet-2"]');
    expect(
      zora.findAll("[data-library-item]").map((item) => item.attributes("data-library-item")),
    ).toEqual(["gallery-21", "gallery-22", "portrait-23"]);

    await zora.get('[data-library-item="gallery-21"] [data-library-add]').trigger("click");
    expect(wrapper.emitted("add-image")).toEqual([[zoraImage]]);
    expect(wrapper.emitted("replace-image")).toBeUndefined();
  });

  it("searches by ficha name and accent-insensitive image label", async () => {
    const wrapper = mountLibrary();
    await wrapper.get("[data-library-search]").setValue("sonrie");
    expect(wrapper.findAll("[data-library-item]")).toHaveLength(1);
    expect(wrapper.get("[data-library-item]").attributes("data-library-item")).toBe("gallery-22");

    await wrapper.get("[data-library-search]").setValue("aria");
    expect(wrapper.findAll("[data-library-item]")).toHaveLength(1);
    expect(wrapper.get("[data-library-group]").text()).toContain("Aria");

    await wrapper.get("[data-library-search]").setValue("does not exist");
    expect(wrapper.find("[data-library-empty]").exists()).toBe(true);
  });

  it("keeps replacing separate from adding and disables replacement by the existing asset", async () => {
    const wrapper = mountLibrary({ canReplace: true, selectedAssetId: "201" });
    expect(
      wrapper.get('[data-library-item="gallery-21"] [data-library-replace]').attributes("disabled"),
    ).toBeDefined();

    await wrapper.get('[data-library-item="gallery-22"] [data-library-replace]').trigger("click");
    expect(wrapper.emitted("replace-image")).toEqual([
      [
        {
          asset_id: 202,
          url: "/zora-happy.png",
          label: "Zora · Sonríe",
          sheet_id: 2,
          source: "gallery",
        },
      ],
    ]);
    expect(wrapper.emitted("add-image")).toBeUndefined();
  });

  it("uses the same typed image for drag and click", async () => {
    const wrapper = mountLibrary();
    const dataTransfer = { effectAllowed: "none", setData: vi.fn() };
    await wrapper
      .get('[data-library-item="gallery-21"] [data-library-add]')
      .trigger("dragstart", { dataTransfer });

    expect(dataTransfer.effectAllowed).toBe("copy");
    expect(dataTransfer.setData).toHaveBeenCalledWith(
      SEQUENCE_LIBRARY_IMAGE_MIME,
      JSON.stringify(zoraImage),
    );
    expect(parseSequenceLibraryImage(dataTransfer.setData.mock.calls[0]![1])).toEqual(zoraImage);
    expect(wrapper.emitted("add-image")).toBeUndefined();
  });

  it("never guesses a missing asset id from the gallery row or matching URL", async () => {
    const wrapper = mountLibrary({
      sheets: [
        { id: 4, name: "Lost", gallery_images: [{ id: 444, url: "/lost.png", label: "Original" }] },
      ],
      imageAssets: [{ id: 888, filename: "lost.png", url: "/lost.png" }],
      canReplace: true,
    });
    const button = wrapper.get("[data-library-add]");
    expect(button.attributes("disabled")).toBeDefined();
    expect(button.attributes("draggable")).toBe("false");
    expect(wrapper.find("[data-library-unavailable]").exists()).toBe(true);
    const dataTransfer = { setData: vi.fn() };
    await button.trigger("dragstart", { dataTransfer });
    expect(dataTransfer.setData).not.toHaveBeenCalled();
    expect(wrapper.emitted("add-image")).toBeUndefined();
  });

  it("allows read-only browsing while preventing add, replace and drag", async () => {
    const wrapper = mountLibrary({ canEdit: false, canReplace: true });
    expect(wrapper.get("[data-library-add]").attributes("disabled")).toBeDefined();
    expect(wrapper.get("[data-library-replace]").attributes("disabled")).toBeDefined();
    const dataTransfer = { setData: vi.fn() };
    await wrapper.get("[data-library-add]").trigger("dragstart", { dataTransfer });
    expect(dataTransfer.setData).not.toHaveBeenCalled();
    await wrapper.get("[data-library-search]").setValue("Viajera");
    expect(wrapper.findAll("[data-library-item]")).toHaveLength(1);
  });

  it("searches assets beyond the first rendered page and exposes more without reuploading", async () => {
    const imageAssets = Array.from({ length: 75 }, (_, index) => ({
      id: index + 1,
      filename: `image-${index + 1}.png`,
      url: `/image-${index + 1}.png`,
    }));
    const wrapper = mountLibrary({ imageAssets });
    await switchToAssets(wrapper);
    expect(wrapper.findAll("[data-library-item]")).toHaveLength(60);
    await wrapper.get("[data-library-show-more]").trigger("click");
    expect(wrapper.findAll("[data-library-item]")).toHaveLength(75);
    await wrapper.get("[data-library-search]").setValue("image-75");
    expect(wrapper.findAll("[data-library-item]")).toHaveLength(1);
    await wrapper.get("[data-library-add]").trigger("click");
    expect(wrapper.emitted("add-image")).toEqual([
      [{ asset_id: 75, url: "/image-75.png", label: "image-75.png", source: "asset" }],
    ]);
  });
});

describe("sequence library global asset search", () => {
  let wrapper: ReturnType<typeof mountLibrary>;

  beforeEach(() => {
    vi.useFakeTimers();
    vi.clearAllMocks();
    vi.mocked(mockLive.handleEvent).mockReturnValue(42);
  });

  afterEach(() => {
    wrapper?.unmount();
    vi.useRealTimers();
  });

  function request(index = -1) {
    return vi.mocked(mockLive.pushEvent).mock.calls.at(index)![1]!;
  }

  async function reply(requestId: unknown, ids: number[], hasMore = false) {
    const handler = vi.mocked(mockLive.handleEvent).mock.calls[0]![1];
    handler({
      request_id: requestId,
      results: ids.map((id) => ({ id, filename: `remote-${id}.png`, url: `/remote-${id}.png` })),
      has_more: hasMore,
    });
    await nextTick();
  }

  it("finds project images missing from the initial catalog and preserves add/replace identity", async () => {
    wrapper = mountLibrary({
      remoteSearch: true,
      canReplace: true,
      selectedAssetId: 101,
      imageAssets: [{ id: 101, filename: "initial.png", url: "/initial.png" }],
    });
    await wrapper.get("[data-library-search]").setValue("remote-999");
    expect(mockLive.pushEvent).not.toHaveBeenCalled();
    await switchToAssets(wrapper);
    expect(wrapper.find("[data-library-searching]").exists()).toBe(true);
    expect(wrapper.find("[data-library-empty]").exists()).toBe(false);
    await vi.advanceTimersByTimeAsync(160);
    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "picker_search",
      expect.objectContaining({
        resource: "asset",
        kind: "image",
        query: "remote-999",
        limit: 100,
      }),
      undefined,
      expect.any(Function),
    );
    await reply(request().request_id, [999]);
    expect(wrapper.find("[data-library-searching]").exists()).toBe(false);
    await wrapper.get('[data-library-item="asset-999"] [data-library-add]').trigger("click");
    await wrapper.get('[data-library-item="asset-999"] [data-library-replace]').trigger("click");
    const image = {
      asset_id: 999,
      url: "/remote-999.png",
      label: "remote-999.png",
      source: "asset",
    };
    expect(wrapper.emitted("add-image")).toEqual([[image]]);
    expect(wrapper.emitted("replace-image")).toEqual([[image]]);
  });

  it("invalidates an old query before debounce and ignores out-of-order and inactive-tab replies", async () => {
    wrapper = mountLibrary({ remoteSearch: true });
    await switchToAssets(wrapper);
    await vi.advanceTimersByTimeAsync(160);
    const first = request().request_id;
    await wrapper.get("[data-library-search]").setValue("new");
    await reply(first, [100]);
    expect(wrapper.findAll("[data-library-item]")).toHaveLength(0);
    expect(wrapper.find("[data-library-searching]").exists()).toBe(true);
    await vi.advanceTimersByTimeAsync(160);
    const second = request().request_id;
    await wrapper.get("[data-library-search]").setValue("latest");
    await vi.advanceTimersByTimeAsync(160);
    await reply(request().request_id, [300]);
    await reply(second, [200]);
    expect(wrapper.get("[data-library-item]").attributes("data-library-item")).toBe("asset-300");

    await wrapper.get("[data-library-search]").setValue("pending");
    await vi.advanceTimersByTimeAsync(160);
    const pending = request().request_id;
    await wrapper.get("[data-library-tab-sheets]").trigger("mousedown", { button: 0 });
    await wrapper.get("[data-library-tab-sheets]").trigger("click");
    await reply(pending, [400]);
    await switchToAssets(wrapper);
    expect(wrapper.find('[data-library-item="asset-400"]').exists()).toBe(false);
  });

  it("shows the bounded result count and invites refinement when more global matches exist", async () => {
    wrapper = mountLibrary({ remoteSearch: true });
    await switchToAssets(wrapper);
    await vi.advanceTimersByTimeAsync(160);
    await reply(
      request().request_id,
      Array.from({ length: 100 }, (_, index) => index + 1),
      true,
    );
    expect(wrapper.findAll("[data-library-item]")).toHaveLength(60);
    expect(wrapper.get("[data-library-limited]").text()).toContain("60");
    await wrapper.get("[data-library-show-more]").trigger("click");
    expect(wrapper.findAll("[data-library-item]")).toHaveLength(100);
    expect(wrapper.get("[data-library-limited]").text()).toContain("100");
    expect(mockLive.pushEvent).toHaveBeenCalledOnce();
  });

  it("offers retry on failure or timeout and cancels pending work on unmount", async () => {
    wrapper = mountLibrary({ remoteSearch: true });
    await switchToAssets(wrapper);
    await vi.advanceTimersByTimeAsync(160);
    vi.mocked(mockLive.pushEvent).mock.calls[0]![3]!(new Error("disconnected"));
    await nextTick();
    expect(wrapper.find("[data-library-search-failed]").exists()).toBe(true);
    expect(wrapper.find("[data-library-empty]").exists()).toBe(false);
    await wrapper.get("[data-library-retry]").trigger("click");
    await vi.advanceTimersByTimeAsync(10_160);
    expect(wrapper.find("[data-library-search-failed]").exists()).toBe(true);
    expect(mockLive.pushEvent).toHaveBeenCalledTimes(2);
    await wrapper.get("[data-library-search]").setValue("pending");
    wrapper.unmount();
    await vi.advanceTimersByTimeAsync(160);
    expect(mockLive.pushEvent).toHaveBeenCalledTimes(2);
    expect(mockLive.removeHandleEvent).toHaveBeenCalledWith(42);
  });
});

describe("sequence library drag contract", () => {
  it("rejects malformed payloads and non-asset associations", () => {
    for (const raw of [
      "",
      "null",
      "{",
      "[]",
      JSON.stringify({ ...zoraImage, asset_id: -1 }),
      JSON.stringify({ ...zoraImage, source: "audio" }),
      JSON.stringify({ ...zoraImage, url: null }),
    ]) {
      expect(parseSequenceLibraryImage(raw)).toBeNull();
    }
    expect(parseSequenceLibraryImage(JSON.stringify({ ...zoraImage, extra: "ignored" }))).toEqual(
      zoraImage,
    );
  });
});
