import { AutoLayoutAction, buildBatchPositions } from "../services/historyPreset";
import type { FlowCanvasRuntime } from "./flowCanvasRuntime";

export interface FlowCanvasAutoLayoutOptions {
  fitSequencesToChildren(opts: { mode: "fit"; track: true }): Promise<void>;
  flushPendingSequenceGeometry(): void;
}

export async function performFlowCanvasAutoLayout(
  runtime: FlowCanvasRuntime,
  { fitSequencesToChildren, flushPendingSequenceGeometry }: FlowCanvasAutoLayoutOptions,
): Promise<void> {
  if (runtime.autoLayoutInProgress) return;
  if (!runtime.area || !runtime.editor) return;

  const area = runtime.area;
  const editor = runtime.editor;

  runtime.autoLayoutInProgress = true;
  try {
    const [{ AreaExtensions }, { runFlowAutoLayout, snapshotFlowPositions }] = await Promise.all([
      import("rete-area-plugin"),
      import("../services/flowAutoLayout"),
    ]);

    const prevPositions = snapshotFlowPositions(area);

    runtime.loadingFromServerCount++;
    try {
      await runFlowAutoLayout(
        {
          editor,
          area,
        },
        {
          duration: 400,
          timingFunction: (t: number) => t * (2 - t),
        },
      );
      await fitSequencesToChildren({ mode: "fit", track: true });
      flushPendingSequenceGeometry();
    } finally {
      runtime.loadingFromServerCount = Math.max(0, runtime.loadingFromServerCount - 1);
    }

    await AreaExtensions.zoomAt(area, editor.getNodes());

    const newPositions = snapshotFlowPositions(area);
    runtime.hookProxy.pushEvent("batch_update_positions", {
      positions: buildBatchPositions(newPositions),
    });

    if (runtime.history) {
      runtime.history.add(
        new AutoLayoutAction(runtime.hookProxy, runtime.area, prevPositions, newPositions),
      );
    }
  } catch (error) {
    // biome-ignore lint/suspicious/noConsole: error feedback for unlikely ELK layout failure
    console.error("Auto-layout failed:", error);
  } finally {
    runtime.autoLayoutInProgress = false;
  }
}
