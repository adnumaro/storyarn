import { computed, nextTick, onUnmounted, ref, watch, type Ref } from "vue";
import type { LiveInterface } from "@shared/composables/useLive";
import { sequenceLayerKey as layerKey } from "@modules/flows/sequence/layerOrder";
import type {
  SequenceEntityId,
  SequenceStageState,
  SequenceVisualLayer,
} from "@modules/flows/sequence/types";
import {
  changedGeometry,
  layerAnchor,
  layerGeometry,
  moveLayer,
  resizeLayer,
  type LayerGeometry,
  type ResizeHandle,
} from "../lib/sequence-stage-geometry";

interface StageManipulationOptions {
  stage: () => SequenceStageState;
  canEdit: () => boolean;
  selectedKey: () => string | null;
  select: (key: string | null) => void;
  lockedKeys: () => string[];
  viewport: Ref<HTMLElement | null>;
  live: LiveInterface;
}

const NUDGE_DIRECTIONS: { [key: string]: { x: number; y: number } | undefined } = {
  ArrowLeft: { x: -1, y: 0 },
  ArrowRight: { x: 1, y: 0 },
  ArrowUp: { x: 0, y: -1 },
  ArrowDown: { x: 0, y: 1 },
};

interface Gesture {
  kind: "pointer" | "keyboard";
  ownerId: SequenceEntityId;
  layer: SequenceVisualLayer;
  geometry: LayerGeometry;
  handle?: ResizeHandle;
  pointerId?: number;
  clientX: number;
  clientY: number;
  viewportWidth: number;
  viewportHeight: number;
}

export function useSequenceStageManipulation(options: StageManipulationOptions) {
  const draft = ref<{ key: string; geometry: LayerGeometry } | null>(null);
  let gesture: Gesture | null = null;
  const pending = ref(new Map<string, { geometry: LayerGeometry; interactionId: string }>());
  const layers = computed(() => options.stage().composition?.layers ?? []);
  const canManipulate = computed(
    () => options.canEdit() && options.stage().status === "ready" && options.stage().owner != null,
  );
  const displayLayers = computed(() =>
    layers.value.map((layer) => ({
      ...layer,
      ...pending.value.get(layerKey(layer))?.geometry,
      ...(layerKey(layer) === draft.value?.key ? draft.value.geometry : {}),
    })),
  );

  function isLocked(layer: SequenceVisualLayer): boolean {
    return options.lockedKeys().includes(layerKey(layer));
  }

  function cancel() {
    window.removeEventListener("pointermove", movePointer);
    window.removeEventListener("pointerup", finishPointer);
    window.removeEventListener("pointercancel", cancelPointer);
    window.removeEventListener("keydown", cancelKey);
    window.removeEventListener("keyup", finishKeyboard);
    window.removeEventListener("blur", cancel);
    gesture = null;
    draft.value = null;
  }

  function begin(layer: SequenceVisualLayer, kind: Gesture["kind"]): Gesture | null {
    if (!canManipulate.value || isLocked(layer) || !options.viewport.value) return null;
    const owner = options.stage().owner;
    if (!owner) return null;
    const bounds = options.viewport.value.getBoundingClientRect();
    if (bounds.width <= 0 || bounds.height <= 0) return null;
    cancel();
    options.select(layerKey(layer));
    const session: Gesture = {
      kind,
      ownerId: owner.nodeId,
      layer,
      geometry: layerGeometry(
        displayLayers.value.find((item) => layerKey(item) === layerKey(layer)) ?? layer,
      ),
      clientX: 0,
      clientY: 0,
      viewportWidth: bounds.width,
      viewportHeight: bounds.height,
    };
    gesture = session;
    draft.value = { key: layerKey(layer), geometry: session.geometry };
    window.addEventListener("keydown", cancelKey);
    window.addEventListener("blur", cancel);
    return session;
  }

  function startPointer(event: PointerEvent, layer: SequenceVisualLayer, handle?: ResizeHandle) {
    if (event.button !== 0 || event.isPrimary === false) return;
    const session = begin(layer, "pointer");
    if (!session) return;
    event.preventDefault();
    event.stopPropagation();
    (event.currentTarget as HTMLElement).focus();
    session.clientX = event.clientX;
    session.clientY = event.clientY;
    session.pointerId = event.pointerId;
    session.handle = handle;
    window.addEventListener("pointermove", movePointer);
    window.addEventListener("pointerup", finishPointer);
    window.addEventListener("pointercancel", cancelPointer);
  }

  function matchingPointer(event: PointerEvent): boolean {
    return gesture?.kind === "pointer" && gesture.pointerId === event.pointerId;
  }

  function movePointer(event: PointerEvent) {
    if (!gesture || !matchingPointer(event)) return;
    const dx = (event.clientX - gesture.clientX) / gesture.viewportWidth;
    const dy = (event.clientY - gesture.clientY) / gesture.viewportHeight;
    const geometry = gesture.handle
      ? resizeLayer(
          gesture.geometry,
          layerAnchor(gesture.layer),
          gesture.handle,
          dx,
          dy,
          gesture.layer.kind === "character",
        )
      : moveLayer(gesture.geometry, dx, dy);
    draft.value = { key: layerKey(gesture.layer), geometry };
  }

  function finishPointer(event: PointerEvent) {
    if (!matchingPointer(event)) return;
    movePointer(event);
    finish();
  }

  function cancelPointer(event: PointerEvent) {
    if (matchingPointer(event)) cancel();
  }

  function cancelKey(event: KeyboardEvent) {
    if (event.key !== "Escape") return;
    event.preventDefault();
    event.stopPropagation();
    cancel();
  }

  function nudge(event: KeyboardEvent, layer: SequenceVisualLayer) {
    const direction = NUDGE_DIRECTIONS[event.key];
    if (!direction || event.metaKey || event.ctrlKey || event.altKey) return;
    event.preventDefault();
    event.stopPropagation();
    if (!keyboardGesture(layer) || !gesture || !draft.value) return;
    const step = event.shiftKey ? 10 : 1;
    draft.value.geometry = moveLayer(
      draft.value.geometry,
      (direction.x * step) / gesture.viewportWidth,
      (direction.y * step) / gesture.viewportHeight,
    );
  }

  function keyboardGesture(layer: SequenceVisualLayer): boolean {
    if (!canManipulate.value || isLocked(layer)) return false;
    if (gesture?.kind === "keyboard" && layerKey(gesture.layer) === layerKey(layer)) return true;
    if (!begin(layer, "keyboard")) return false;
    window.addEventListener("keyup", finishKeyboard);
    return true;
  }

  function finishKeyboard(event: KeyboardEvent) {
    if (gesture?.kind === "keyboard" && event.key.startsWith("Arrow")) finish();
  }

  function finish() {
    const session = gesture;
    const geometry = draft.value?.geometry;
    cancel();
    if (!session || !geometry || !canCommit(session)) return;
    const changes = changedGeometry(session.geometry, geometry);
    if (Object.keys(changes).length > 0) persist(session, changes);
  }

  function canCommit(session: Gesture): boolean {
    const owner = options.stage().owner;
    return (
      owner != null &&
      canManipulate.value &&
      !isLocked(session.layer) &&
      String(owner.nodeId) === String(session.ownerId)
    );
  }

  function persist(session: Gesture, changes: Partial<LayerGeometry>) {
    const interactionId = crypto.randomUUID();
    const key = layerKey(session.layer);
    pending.value.set(key, { geometry: { ...session.geometry, ...changes }, interactionId });
    const clearPending = () => {
      if (pending.value.get(key)?.interactionId === interactionId) pending.value.delete(key);
    };
    const acknowledged = () => {
      void nextTick(clearPending);
    };
    const failed = () => {
      if (pending.value.get(key)?.interactionId !== interactionId) return;
      if (gesture && layerKey(gesture.layer) === key) cancel();
      clearPending();
    };
    const rowId = session.layer.row_id ?? session.layer.rowId;
    const sequenceId = session.layer.sequence_id ?? session.layer.sequenceId;
    if (rowId != null && sequenceId != null && String(sequenceId) === String(session.ownerId)) {
      options.live.pushEvent(
        "update_sequence_visual_layer",
        {
          id: session.ownerId,
          layer_id: rowId,
          interaction_id: interactionId,
          ...changes,
        },
        acknowledged,
        failed,
      );
    } else {
      options.live.pushEvent(
        "override_sequence_visual_layer",
        {
          id: session.ownerId,
          layer_key: layerKey(session.layer),
          interaction_id: interactionId,
          ...changes,
        },
        acknowledged,
        failed,
      );
    }
  }

  watch(
    () => options.stage().owner?.nodeId,
    () => {
      cancel();
      pending.value.clear();
      options.select(null);
    },
    { flush: "sync" },
  );
  watch(layers, (current) => {
    for (const layer of current) {
      const entry = pending.value.get(layerKey(layer));
      if (
        entry &&
        Object.keys(changedGeometry(layerGeometry(layer), entry.geometry)).length === 0
      ) {
        pending.value.delete(layerKey(layer));
      }
    }
  });
  watch(canManipulate, (allowed) => {
    if (!allowed) pending.value.clear();
  });
  watch([canManipulate, () => options.lockedKeys(), () => options.selectedKey(), layers], () => {
    if (!gesture) return;
    if (
      !canManipulate.value ||
      isLocked(gesture.layer) ||
      options.selectedKey() !== layerKey(gesture.layer) ||
      !layers.value.some((layer) => layerKey(layer) === layerKey(gesture!.layer))
    )
      cancel();
  });
  onUnmounted(() => {
    cancel();
    pending.value.clear();
  });
  return { canManipulate, displayLayers, layerKey, isLocked, startPointer, nudge, cancel };
}
