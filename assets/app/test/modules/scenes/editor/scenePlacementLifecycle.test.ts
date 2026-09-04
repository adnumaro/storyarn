import { nextTick, ref } from "vue";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { createMockLive, withSetup } from "@app/test/setup";

const live = createMockLive();
vi.mock("@shared/composables/useLive", () => ({ useLive: () => live }));
const { useZoneDrawing } = await import("@modules/scenes/editor/composables/useZoneDrawing");
const { useConnectionDrawing } =
  await import("@modules/scenes/editor/composables/useConnectionDrawing");
const { useCanvasCreation } = await import("@modules/scenes/editor/composables/useCanvasCreation");

function stageFixture() {
  const stage = {
    getPointerPosition: () => ({ x: 40, y: 60 }),
    getStage: () => stage,
  };
  return { stage, stageRef: ref({ getStage: () => stage }) };
}

beforeEach(() => {
  vi.mocked(live.pushEvent).mockReset();
  vi.mocked(live.handleEvent).mockReset();
  vi.mocked(live.removeHandleEvent).mockReset();
});

describe("Scene creation lifecycle", () => {
  it("discards an unfinished freeform zone when comments switch the tool to select", async () => {
    const activeTool = ref("freeform");
    const { stage, stageRef } = stageFixture();
    const { result, app } = withSetup(() =>
      useZoneDrawing({
        stageRef,
        stageConfig: { x: 0, y: 0, scaleX: 1, scaleY: 1 },
        pixelToPercent: (x, y) => ({ x, y }),
        percentToPixel: (x, y) => ({ x, y }),
        activeTool,
        editMode: ref(true),
        canEdit: ref(true),
      }),
    );

    expect(result.handleZoneCreationClick({ target: stage } as never)).toBe(true);
    expect(result.isDrawing.value).toBe(true);
    expect(result.drawingOverlay.value?.vertexConfigs).toHaveLength(1);

    activeTool.value = "select";
    await nextTick();
    expect(result.isDrawing.value).toBe(false);
    expect(result.drawingOverlay.value).toBeNull();
    app.unmount();
  });

  it("discards an unfinished connector when comments switch the tool to select", async () => {
    const activeTool = ref("connector");
    const { stageRef } = stageFixture();
    const { result, app } = withSetup(() =>
      useConnectionDrawing({
        stageRef,
        stageConfig: { x: 0, y: 0, scaleX: 1, scaleY: 1 },
        pixelToPercent: (x, y) => ({ x, y }),
        percentToPixel: (x, y) => ({ x, y }),
        activeTool,
        editMode: ref(true),
        canEdit: ref(true),
        pins: ref([{ id: 1, positionX: 20, positionY: 30 }]),
      }),
    );

    expect(result.handlePinClickForConnection(1)).toBe(true);
    expect(result.sourcePinId.value).toBe(1);

    activeTool.value = "select";
    await nextTick();
    expect(result.sourcePinId.value).toBeNull();
    expect(result.isDrawingConnection.value).toBe(false);
    app.unmount();
  });

  it("cancels a pending sheet-pin placement when comments take the active tool", async () => {
    const activeTool = ref("pin");
    const { stageRef } = stageFixture();
    let pendingSheetChanged: Parameters<typeof live.handleEvent>[1] | undefined;
    vi.mocked(live.handleEvent).mockImplementation((event, callback) => {
      if (event === "pending_sheet_changed") pendingSheetChanged = callback;
      return 31;
    });
    const { result, app } = withSetup(() =>
      useCanvasCreation({
        stageRef,
        stageConfig: { x: 0, y: 0, scaleX: 1, scaleY: 1 },
        pixelToPercent: (x, y) => ({ x, y }),
        activeTool,
        editMode: ref(true),
        canEdit: ref(true),
      }),
    );
    pendingSheetChanged?.({ active: true });
    expect(result.hasPendingSheet.value).toBe(true);

    activeTool.value = "select";
    await nextTick();
    expect(result.hasPendingSheet.value).toBe(false);
    expect(live.pushEvent).toHaveBeenCalledExactlyOnceWith("cancel_sheet_picker", {});

    app.unmount();
    expect(live.removeHandleEvent).toHaveBeenCalledWith(31);
  });
});
