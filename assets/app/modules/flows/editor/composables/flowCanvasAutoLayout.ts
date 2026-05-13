import { AutoLayoutAction, buildBatchPositions, type Position } from "../services/historyPreset";
import { runFlowAutoLayout, snapshotFlowPositions } from "../services/flowAutoLayout";
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

  runtime.autoLayoutInProgress = true;
  try {
    const { AreaExtensions } = await import("rete-area-plugin");

    const prevPositions = snapshotPositions(runtime);

    runtime.loadingFromServerCount++;
    try {
      await runFlowAutoLayout(
        {
          editor: runtime.editor,
          area: runtime.area,
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

    await AreaExtensions.zoomAt(runtime.area, runtime.editor.getNodes());

    const newPositions = snapshotPositions(runtime);
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

function snapshotPositions(runtime: FlowCanvasRuntime): Map<string, Position> {
  if (!runtime.editor || !runtime.area) {
    return new Map<string, Position>();
  }
  return snapshotFlowPositions(runtime.area);
}
