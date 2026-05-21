import type { NodeEditor } from "rete";
import type { AreaPlugin } from "rete-area-plugin";
import { watch } from "vue";

import { i18n } from "@/app/i18n";
import {
  activeFlowPlacement,
  cancelFlowPlacement,
  type FlowPlacementTarget,
} from "../lib/flow-placement-state";
import type { FlowNode } from "../lib/flow-node";
import { NODE_CONFIGS, type FlowNodeType } from "../lib/node-configs";
import type { FlowAreaExtra, FlowSchemes } from "../lib/rete-schemes";
import { SEQUENCE_MIN_HEIGHT, SEQUENCE_MIN_WIDTH } from "../lib/sequence-layout";

interface FlowPlacementOptions {
  containerEl: HTMLElement;
  editor: NodeEditor<FlowSchemes>;
  area: AreaPlugin<FlowSchemes, FlowAreaExtra>;
  pushEvent: (event: string, payload: Record<string, unknown>) => void;
}

interface PlacementSize {
  width: number;
  height: number;
}

const DEFAULT_NODE_SIZE: PlacementSize = { width: 190, height: 130 };
const ANNOTATION_SIZE: PlacementSize = { width: 200, height: 120 };
const SEQUENCE_SIZE: PlacementSize = { width: SEQUENCE_MIN_WIDTH, height: SEQUENCE_MIN_HEIGHT };

export function createFlowPlacement({
  containerEl,
  editor,
  area,
  pushEvent,
}: FlowPlacementOptions): () => void {
  let shadow: HTMLDivElement | null = null;
  let latestPointer: PointerEvent | null = null;

  function onPointerMove(event: PointerEvent): void {
    latestPointer = event;
    updateShadow(event);
  }

  function onPointerLeave(): void {
    hideShadow();
  }

  function onPointerDown(event: PointerEvent): void {
    const target = activeFlowPlacement.value;
    if (!target || event.button !== 0 || shouldIgnorePointerDown(event)) {
      return;
    }

    event.preventDefault();
    event.stopImmediatePropagation();

    const position = canvasPointFromEvent(event);
    const payload = {
      position_x: Math.round(position.x),
      position_y: Math.round(position.y),
    };
    const parentId = parentSequenceIdAt(position);
    const eventPayload = parentId == null ? payload : { ...payload, parent_id: parentId };

    if (target.kind === "annotation") {
      pushEvent("add_annotation", eventPayload);
    } else {
      pushEvent("add_node", { ...eventPayload, type: target.type });
    }

    cancelFlowPlacement();
  }

  function onKeyDown(event: KeyboardEvent): void {
    if (event.key === "Escape" && activeFlowPlacement.value) {
      event.preventDefault();
      cancelFlowPlacement();
    }
  }

  function shouldIgnorePointerDown(event: PointerEvent): boolean {
    const target = event.target as HTMLElement | null;
    if (!target) {
      return false;
    }

    return Boolean(
      target.closest(
        [
          "button",
          "a",
          "input",
          "textarea",
          "select",
          "[contenteditable='true']",
          "[data-flow-interactive='true']",
          "[data-testid='flow-context-menu']",
          ".minimap",
        ].join(", "),
      ),
    );
  }

  function canvasPointFromEvent(event: PointerEvent): { x: number; y: number } {
    const rect = containerEl.getBoundingClientRect();
    const transform = area.area.transform;
    const zoom = transform.k || 1;

    return {
      x: (event.clientX - rect.left - transform.x) / zoom,
      y: (event.clientY - rect.top - transform.y) / zoom,
    };
  }

  function containerPointFromEvent(event: PointerEvent): { x: number; y: number } {
    const rect = containerEl.getBoundingClientRect();
    return {
      x: event.clientX - rect.left,
      y: event.clientY - rect.top,
    };
  }

  function updateShadow(event: PointerEvent): void {
    const target = activeFlowPlacement.value;
    if (!target) {
      hideShadow();
      return;
    }

    const element = ensureShadow(target);
    const point = containerPointFromEvent(event);
    const size = placementSize(target);
    const zoom = area.area.transform.k || 1;

    element.style.display = "block";
    element.style.transform = `translate(${point.x}px, ${point.y}px)`;
    element.style.width = `${Math.max(1, size.width * zoom)}px`;
    element.style.height = `${Math.max(1, size.height * zoom)}px`;
  }

  function ensureShadow(target: FlowPlacementTarget): HTMLDivElement {
    if (!shadow) {
      shadow = document.createElement("div");
      shadow.className = "flow-placement-shadow";
      shadow.innerHTML = `
        <div class="flow-placement-shadow__header">
          <span class="flow-placement-shadow__title"></span>
        </div>
        <div class="flow-placement-shadow__body"></div>
      `;
      containerEl.appendChild(shadow);
    }

    const title = shadow.querySelector(".flow-placement-shadow__title");
    shadow.dataset.kind = target.kind === "annotation" ? "annotation" : target.type;
    shadow.style.setProperty("--flow-placement-color", placementColor(target));
    if (title) {
      title.textContent = placementLabel(target);
    }

    return shadow;
  }

  function hideShadow(): void {
    if (shadow) {
      shadow.style.display = "none";
    }
  }

  function removeShadow(): void {
    shadow?.remove();
    shadow = null;
  }

  function parentSequenceIdAt(position: { x: number; y: number }): number | null {
    const candidates = editor
      .getNodes()
      .filter((node): node is FlowNode => node.nodeType === "sequence")
      .filter((node) => {
        const view = area.nodeViews.get(node.id);
        return (
          Boolean(view) &&
          position.x > view!.position.x &&
          position.y > view!.position.y &&
          position.x < view!.position.x + node.width &&
          position.y < view!.position.y + node.height
        );
      });

    candidates.sort((a, b) => sequenceDepth(b) - sequenceDepth(a));
    return nodeDbId(candidates[0] ?? null);
  }

  function sequenceDepth(node: FlowNode): number {
    let depth = 0;
    let parentId = node.parent;

    while (parentId) {
      depth += 1;
      parentId = editor.getNode(parentId)?.parent;
    }

    return depth;
  }

  const stopWatch = watch(
    activeFlowPlacement,
    (target) => {
      containerEl.classList.toggle("flow-placement-active", Boolean(target));
      if (target && latestPointer) {
        updateShadow(latestPointer);
      } else {
        removeShadow();
      }
    },
    { immediate: true },
  );

  containerEl.addEventListener("pointermove", onPointerMove, { capture: true });
  containerEl.addEventListener("pointerleave", onPointerLeave);
  containerEl.addEventListener("pointerdown", onPointerDown, { capture: true });
  document.addEventListener("keydown", onKeyDown);

  return () => {
    stopWatch();
    containerEl.classList.remove("flow-placement-active");
    containerEl.removeEventListener("pointermove", onPointerMove, { capture: true });
    containerEl.removeEventListener("pointerleave", onPointerLeave);
    containerEl.removeEventListener("pointerdown", onPointerDown, { capture: true });
    document.removeEventListener("keydown", onKeyDown);
    removeShadow();
    cancelFlowPlacement();
  };
}

function placementSize(target: FlowPlacementTarget): PlacementSize {
  if (target.kind === "annotation") {
    return ANNOTATION_SIZE;
  }

  if (target.type === "sequence") {
    return SEQUENCE_SIZE;
  }

  return DEFAULT_NODE_SIZE;
}

function placementColor(target: FlowPlacementTarget): string {
  if (target.kind === "annotation") {
    return NODE_CONFIGS.annotation.color;
  }

  return NODE_CONFIGS[target.type]?.color ?? NODE_CONFIGS.dialogue.color;
}

function placementLabel(target: FlowPlacementTarget): string {
  if (target.kind === "annotation") {
    return i18n.global.t("flows.dock.add_note");
  }

  return i18n.global.t(`flows.node_types.${target.type as FlowNodeType}`);
}

function nodeDbId(node: FlowNode | null): number | null {
  if (!node) {
    return null;
  }

  if (typeof node.nodeId === "number") {
    return node.nodeId;
  }

  const parsed = Number.parseInt(String(node.nodeId), 10);
  return Number.isFinite(parsed) ? parsed : null;
}
