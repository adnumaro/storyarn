import { describe, it, expect, vi, beforeEach } from "vitest";
import { mount } from "@vue/test-utils";
import { createMockLive } from "../../../../setup";

const mockLive = createMockLive();

vi.mock("@shared/composables/useLive", () => ({
  useLive: () => mockLive,
}));

const { default: DialogueToolbar } =
  await import("../../../../../modules/flows/editor/components/entities/toolbar/sections/DialogueToolbar.vue");

/** F3-B regression guard: DialogueToolbar receives raw rete `node.data`
 * (snake_case) and adapts it internally to camelCase. These tests pin the
 * adapter — if a future change reads `nodeData.audio_asset_id` directly
 * outside the adapter, the test will fail because the prop shape can't
 * be assumed snake_case at the consumption site. */

interface RawData {
  speaker_sheet_id?: number | string | null;
  location_sheet_id?: number | string | null;
  technical_id?: string;
  audio_asset_id?: number | string | null;
  avatar_id?: number | string | null;
}

function mountIt(nodeData: RawData = {}, sheetAvatars: unknown[] = []) {
  return mount(DialogueToolbar, {
    props: { nodeData, nodeId: 42, sheetAvatars },
    global: {
      // ToolbarAvatarPicker uses reka-ui Popover under the hood (ResizeObserver
      // not in jsdom). Stubbing keeps the surface alive without rendering it.
      stubs: {
        ToolbarAvatarPicker: {
          name: "ToolbarAvatarPicker",
          props: ["avatars", "hasOverride"],
          template: "<div data-stub-avatar-picker />",
        },
        ToolbarTooltip: { template: "<div><slot /></div>" },
        ToolbarSeparator: { template: "<span data-stub-sep />" },
      },
    },
  });
}

describe("DialogueToolbar — camelCase adapter (F3-B)", () => {
  beforeEach(() => {
    vi.mocked(mockLive.pushEvent).mockClear();
  });

  it("renders technical_id from snake_case prop into the input", () => {
    const w = mountIt({ technical_id: "mc_jaime_1" });
    const input = w.find("input.toolbar-input");
    expect(input.exists()).toBe(true);
    expect((input.element as HTMLInputElement).value).toBe("mc_jaime_1");
  });

  it("shows the audio Volume2 icon only when audio_asset_id is set", () => {
    // Lucide-vue-next icons don't expose a Vue `name` reliably across builds;
    // probe by class instead (lucide adds `lucide-volume-2`).
    const empty = mountIt({});
    expect(empty.find(".lucide-volume-2").exists()).toBe(false);

    const withAudio = mountIt({ audio_asset_id: 7 });
    expect(withAudio.find(".lucide-volume-2").exists()).toBe(true);
  });

  it("avatar override flag derives from avatar_id (camelCase locals stay correct for null / 0 / set)", () => {
    const sheetAvatars = [
      {
        id: "sheet-1",
        avatars: [
          { id: 100, name: "happy", asset: { url: "/a.png" }, position: 0 },
          { id: 200, name: "sad", asset: { url: "/b.png" }, position: 1 },
        ],
      },
    ];
    // The picker only renders when the speaker has at least one avatar
    // available (`v-if="speakerAvatars.length > 0"`). All cases here have a
    // matching speaker_sheet_id with two avatars — the variable is `avatar_id`.
    const cases: Array<[RawData, boolean]> = [
      [{ speaker_sheet_id: "sheet-1" }, false],
      [{ speaker_sheet_id: "sheet-1", avatar_id: null }, false],
      [{ speaker_sheet_id: "sheet-1", avatar_id: 0 }, false],
      [{ speaker_sheet_id: "sheet-1", avatar_id: "" }, false],
      [{ speaker_sheet_id: "sheet-1", avatar_id: 100 }, true],
    ];
    for (const [data, expected] of cases) {
      const w = mountIt(data, sheetAvatars);
      const picker = w.findComponent({ name: "ToolbarAvatarPicker" });
      expect(picker.exists()).toBe(true);
      expect(picker.props("hasOverride")).toBe(expected);
    }
  });

  it("falls back to location_sheet_id when speaker_sheet_id is null (legacy import data)", () => {
    const sheetAvatars = [
      {
        id: "loc-1",
        avatars: [{ id: 50, name: "x", asset: { url: "/c.png" }, position: 0 }],
      },
    ];
    const w = mountIt({ location_sheet_id: "loc-1" }, sheetAvatars);
    const picker = w.findComponent({ name: "ToolbarAvatarPicker" });
    expect(picker.exists()).toBe(true);
    expect(picker.props("avatars")).toHaveLength(1);
  });

  it("technical_id input @blur pushes update_node_data with snake_case wire key", async () => {
    const w = mountIt({ technical_id: "" });
    const input = w.find("input.toolbar-input");
    await input.setValue("new_id");
    await input.trigger("blur");
    expect(mockLive.pushEvent).toHaveBeenCalledWith("update_node_data", {
      node: { technical_id: "new_id" },
    });
  });
});
