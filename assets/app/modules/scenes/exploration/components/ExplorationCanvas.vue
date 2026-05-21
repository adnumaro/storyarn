<script setup lang="ts">
import { computed, onMounted, ref, toRef } from "vue";
import type Konva from "konva";
import { useLive } from "@shared/composables/useLive";
import type { LayerData } from "../../canvas/composables/useLayerVisibility";
import { useConnections } from "../../canvas/composables/useConnections";
import { useKonvaStage } from "../../canvas/composables/useKonvaStage";
import { usePins } from "../../canvas/composables/usePins";
import { useZones } from "../../canvas/composables/useZones";
import { useAmbientDisplay } from "../composables/useAmbientDisplay";
import { useExplorationInteraction } from "../composables/useExplorationInteraction";
import { useMovement } from "../composables/useMovement";
import { usePatrols } from "../composables/usePatrols";
import SpeechBubble from "./SpeechBubble.vue";
import SubtitleBar from "./SubtitleBar.vue";

interface SceneData {
  width?: number;
  height?: number;
  backgroundUrl?: string;
}

interface ExplorationPin {
  id: number | string;
  positionX: number;
  positionY: number;
  size: string | null;
  color: string | null;
  opacity: number | null;
  pinType: string;
  label: string | null;
  locked: boolean;
  layerId: number | string | null;
  hidden: boolean;
  iconAssetUrl: string | null;
  sheetAvatarUrl: string | null;
  sheetId: number | string | null;
  position: number | null;
  visibility: string;
  isPlayable: boolean;
  isLeader: boolean;
  flowId: number | string | null;
  patrolMode: string | null;
  patrolRoute: { x: number; y: number; isPinStop?: boolean }[] | null;
  patrolPauseMs: number;
  patrolSpeed: number | null;
  [key: string]: unknown;
}

interface ExplorationZone {
  id: number | string;
  name: string;
  vertices: { x: number; y: number }[] | null;
  fillColor: string | null;
  borderColor: string | null;
  borderWidth: number | null;
  borderStyle: string | null;
  opacity: number | null;
  position: number | null;
  layerId: number | string | null;
  locked: boolean;
  visibility: string;
  actionType: string | null;
  isWalkable: boolean;
  targetType: string | null;
  targetId: number | string | null;
  actionData: Record<string, string | number | boolean | null>;
  [key: string]: unknown;
}

interface ExplorationConnection {
  id: number | string;
  fromPinId: number | string;
  toPinId: number | string;
  waypoints: { x: number; y: number }[] | null;
  color: string | null;
  lineWidth: number | null;
  lineStyle: string | null;
  label: string | null;
  showLabel: boolean;
  bidirectional: boolean;
  [key: string]: unknown;
}

interface ExplorationData {
  zones?: ExplorationZone[];
  pins?: ExplorationPin[];
  connections?: ExplorationConnection[];
}

const {
  sceneData = null,
  explorationData,
  showZones = false,
  flowMode = false,
} = defineProps<{
  sceneData?: SceneData | null;
  explorationData: ExplorationData;
  showZones?: boolean;
  flowMode?: boolean;
}>();

const containerRef = ref<HTMLDivElement | null>(null);
const live = useLive();

// --- Stage (pan/zoom/background) ---
const {
  stageConfig,
  stageRef,
  backgroundConfig,
  cursorStyle,
  handleWheel,
  percentToPixel,
  pixelToPercent,
} = useKonvaStage({
  containerRef,
  sceneData: toRef(() => sceneData),
  activeTool: ref("select"),
  editMode: ref(false),
});

// --- Static refs for read-only mode ---
const nullType = ref<string | null>(null);
const nullId = ref<number | string | null>(null);
const falseRef = ref(false);
const emptyLocks = ref<Record<string, { userId: number | string }>>({});
const emptyDragOverrides = ref<Record<string | number, { x: number; y: number }>>({});
const emptyLayers = ref<LayerData[]>([]);

// --- Filter visible elements from exploration data ---
const allZones = computed(() => explorationData?.zones || []);
const allPins = computed(() => explorationData?.pins || []);

const visiblePins = computed(() => allPins.value.filter((p) => p.visibility !== "hide"));
const visibleZones = computed(() => allZones.value.filter((z) => z.visibility !== "hide"));
const connections = computed(() => explorationData?.connections || []);

// --- Visibility lookup maps ---
const zoneVisibility = computed(() =>
  Object.fromEntries(allZones.value.map((z) => [z.id, z.visibility])),
);
const pinVisibility = computed(() =>
  Object.fromEntries(allPins.value.map((p) => [p.id, p.visibility])),
);

// --- Interaction ---
const { handleZoneClick, handlePinClick, zoneShowOverride, clickableZoneIds, clickablePinIds } =
  useExplorationInteraction({
    pushEvent: live.pushEvent,
    explorationZones: allZones,
    explorationPins: allPins,
    showZones: toRef(() => showZones),
  });

// --- Pin node refs for direct Konva updates ---
const pinNodeRefs: Record<number | string, { getNode?: () => Konva.Node }> = {};

function setPinRef(pinId: number | string, el: { getNode?: () => Konva.Node } | null) {
  if (el) {
    pinNodeRefs[pinId] = el;
  }
}

function getPinNode(pinId: number | string): Konva.Node | null {
  const ref = pinNodeRefs[pinId];
  return ref?.getNode?.() || null;
}

// --- Movement ---
const {
  handleStageClick: movementClick,
  getPositions,
  restorePositions,
} = useMovement({
  explorationPins: allPins,
  explorationZones: allZones,
  flowMode: toRef(() => flowMode),
  percentToPixel,
  getPinNode,
});

// --- Patrols ---
const { pause: pausePatrols, resume: resumePatrols } = usePatrols({
  explorationPins: allPins,
  percentToPixel,
  getPinNode,
});

// --- Ambient display ---
const { bubble, subtitle } = useAmbientDisplay({
  handleEvent: live.handleEvent,
});

// --- Container click: movement (DOM level for reliable click detection) ---
function onContainerClick(e: MouseEvent) {
  const rect = containerRef.value?.getBoundingClientRect();
  if (!rect) return;

  // Screen → stage local → world (account for pan/zoom)
  const stageX = e.clientX - rect.left;
  const stageY = e.clientY - rect.top;
  const worldX = (stageX - stageConfig.x) / stageConfig.scaleX;
  const worldY = (stageY - stageConfig.y) / stageConfig.scaleY;

  const pct = pixelToPercent(worldX, worldY);
  const result = movementClick(pct.x, pct.y);

  if (result) {
    showClickFeedback(e, result === "walkable");
  }
}

// --- Click feedback rings ---
function showClickFeedback(evt: MouseEvent, walkable: boolean) {
  const ring = document.createElement("div");
  ring.style.position = "fixed";
  ring.style.left = `${evt.clientX}px`;
  ring.style.top = `${evt.clientY}px`;
  ring.style.transform = "translate(-50%, -50%)";
  ring.style.zIndex = "9999";
  ring.style.pointerEvents = "none";
  ring.style.borderRadius = "50%";

  if (walkable) {
    ring.style.width = "24px";
    ring.style.height = "24px";
    ring.style.border = "2px solid rgba(74, 222, 128, 0.8)";
    ring.style.animation = "exploration-ring-expand 0.5s ease-out forwards";
  } else {
    ring.style.width = "16px";
    ring.style.height = "16px";
    ring.style.border = "2px solid rgba(248, 113, 113, 0.8)";
    ring.style.animation = "exploration-ring-blocked 0.3s ease-out forwards";
  }

  document.body.appendChild(ring);
  ring.addEventListener("animationend", () => ring.remove());
}

// --- Server events: position save/restore ---
onMounted(() => {
  live.handleEvent("request_positions", () => {
    const pos = getPositions();
    live.pushEvent("report_positions", {
      leader: pos.leader,
      party: pos.party,
      camera: null,
    });
  });

  live.handleEvent("restore_positions", (payload) => {
    const { leader, party } = payload as { leader: unknown; party: unknown };
    restorePositions(leader, party);
  });

  live.handleEvent("patrol_pause", () => pausePatrols());
  live.handleEvent("patrol_resume", () => resumePatrols());
});

// --- Composables in read-only mode ---
const emptyVertices = ref<{ x: number; y: number }[]>([]);
const nullDragOverride = ref<{ id: number | string; vertices: { x: number; y: number }[] } | null>(
  null,
);

const { pinConfigs } = usePins({
  pins: visiblePins,
  layers: emptyLayers,
  entityLocks: emptyLocks,
  currentUserId: ref(0),
  percentToPixel,
  activeTool: ref("pan"),
  selectedType: nullType,
  selectedId: nullId,
  isSelectMode: falseRef,
  editMode: falseRef,
  canEdit: falseRef,
});

const { zoneConfigs } = useZones({
  zones: visibleZones,
  layers: emptyLayers,
  entityLocks: emptyLocks,
  currentUserId: ref(0),
  percentToPixel,
  selectedType: nullType,
  selectedId: nullId,
  isSelectMode: falseRef,
  zoneDragOverride: nullDragOverride,
  editingZoneId: nullId,
  editingVertices: emptyVertices,
});

const { connectionConfigs } = useConnections({
  connections,
  pins: visiblePins,
  layers: emptyLayers,
  percentToPixel,
  selectedType: nullType,
  selectedId: nullId,
  isSelectMode: falseRef,
  dragOverrides: emptyDragOverrides,
});

// --- Helpers ---
function clipCircle(radius: number) {
  return (ctx: CanvasRenderingContext2D) => {
    ctx.arc(0, 0, radius, 0, Math.PI * 2);
  };
}

function getZoneFill(zone: { id: number | string }): { fill: string; opacity: number } {
  const raw = allZones.value.find((z) => z.id === zone.id);
  if (!raw) return { fill: "transparent", opacity: 0 };
  const override = zoneShowOverride(raw);
  if (override) return override;
  return { fill: "transparent", opacity: 0 };
}

function getElementOpacity(
  id: number | string,
  visMap: Record<number | string, string>,
  fallback: number,
): number {
  return visMap[id] === "disable" ? 0.3 : fallback;
}

const LABEL_COLOR = "#d1d5db";
</script>

<template>
  <div
    ref="containerRef"
    class="w-full h-full relative"
    :style="{ cursor: cursorStyle }"
    @click="onContainerClick"
  >
    <v-stage ref="stageRef" :config="stageConfig" @wheel="handleWheel">
      <!-- Background layer -->
      <v-layer :config="{ listening: false }">
        <v-image v-if="backgroundConfig" :config="backgroundConfig" />
      </v-layer>

      <!-- Zones + Connections layer -->
      <v-layer>
        <v-group
          v-for="zone in zoneConfigs"
          :key="'zone-' + zone.id"
          :config="{ listening: clickableZoneIds.has(zone.id) }"
          @click="() => handleZoneClick(zone.id)"
        >
          <v-line
            :config="{
              points: zone.points,
              fill: getZoneFill(zone).fill,
              stroke: zone.stroke,
              strokeWidth: zone.strokeWidth,
              dash: zone.dash,
              opacity: getElementOpacity(zone.id, zoneVisibility, getZoneFill(zone).opacity),
              closed: true,
              hitStrokeWidth: zone.hitStrokeWidth,
              perfectDrawEnabled: false,
            }"
          />
          <v-text
            v-if="zone.name"
            :config="{
              text: zone.name,
              fill: LABEL_COLOR,
              fontSize: 12,
              fontStyle: '600',
              align: 'center',
              x: zone.centroidX - 50,
              y: zone.centroidY - 8,
              width: 100,
              ellipsis: true,
              wrap: 'none',
              shadowColor: 'black',
              shadowBlur: 3,
              shadowOpacity: 0.8,
              shadowForStrokeEnabled: false,
              listening: false,
            }"
          />
        </v-group>
        <v-group
          v-for="conn in connectionConfigs"
          :key="'conn-' + conn.id"
          :config="{ listening: false }"
        >
          <v-arrow
            :config="{
              points: conn.points,
              stroke: conn.stroke,
              fill: conn.fill,
              strokeWidth: conn.strokeWidth,
              dash: conn.dash,
              opacity: conn.opacity,
              pointerLength: conn.pointerLength,
              pointerWidth: conn.pointerWidth,
              pointerAtBeginning: conn.pointerAtBeginning,
              pointerAtEnding: conn.pointerAtEnding,
            }"
          />
          <v-text v-if="conn.labelConfig" :config="conn.labelConfig" />
        </v-group>
      </v-layer>

      <!-- Pins layer -->
      <v-layer>
        <v-group
          v-for="pin in pinConfigs"
          :key="'pin-' + pin.id"
          :ref="(el: unknown) => setPinRef(pin.id, el as { getNode?: () => Konva.Node } | null)"
          :config="{
            x: pin.x,
            y: pin.y,
            listening: clickablePinIds.has(pin.id),
            opacity: getElementOpacity(pin.id, pinVisibility, pin.opacity ?? 1),
          }"
          @click="() => handlePinClick(pin.id)"
        >
          <v-image
            v-if="pin.iconCanvas"
            :key="'pin-icon-' + pin.id + '-' + pin.iconVersion"
            :config="{
              image: pin.iconCanvas,
              x: -pin.iconCanvas.width / 2,
              y: -pin.iconCanvas.height / 2,
              width: pin.iconCanvas.width,
              height: pin.iconCanvas.height,
            }"
          />
          <v-image
            v-else-if="pin.initialsCanvas"
            :config="{
              image: pin.initialsCanvas,
              x: -pin.initialsCanvas.width / 2,
              y: -pin.initialsCanvas.height / 2,
              width: pin.initialsCanvas.width,
              height: pin.initialsCanvas.height,
            }"
          />
          <template v-else-if="pin.image">
            <v-circle
              :config="{
                radius: pin.radius,
                fill: pin.color,
                opacity: pin.opacity,
                shadowColor: 'black',
                shadowBlur: 6,
                shadowOpacity: 0.3,
                shadowOffsetY: 2,
                shadowForStrokeEnabled: false,
                perfectDrawEnabled: false,
              }"
            />
            <v-group :config="{ clipFunc: clipCircle(pin.radius) }">
              <v-image
                :config="{
                  image: pin.image,
                  x: -pin.radius,
                  y: -pin.radius,
                  width: pin.diameter,
                  height: pin.diameter,
                }"
              />
            </v-group>
          </template>
          <v-text
            v-if="pin.label"
            :config="{
              text: pin.label,
              fill: LABEL_COLOR,
              fontSize: 11,
              fontStyle: '600',
              align: 'center',
              x: -50,
              y: pin.radius + 6,
              width: 100,
              ellipsis: true,
              wrap: 'none',
              listening: false,
            }"
          />
        </v-group>
      </v-layer>
    </v-stage>

    <!-- Ambient: speech bubble over pin -->
    <SpeechBubble :bubble="bubble" :get-pin-node="getPinNode" :stage-ref="stageRef" />

    <!-- Ambient: subtitle bar -->
    <SubtitleBar :subtitle="subtitle" />
  </div>
</template>

<style>
@keyframes exploration-ring-expand {
  from {
    transform: translate(-50%, -50%) scale(0.5);
    opacity: 1;
  }
  to {
    transform: translate(-50%, -50%) scale(2);
    opacity: 0;
  }
}
@keyframes exploration-ring-blocked {
  0% {
    transform: translate(-50%, -50%) scale(0.8);
    opacity: 1;
  }
  50% {
    transform: translate(-50%, -50%) scale(1.2);
    opacity: 0.6;
  }
  100% {
    transform: translate(-50%, -50%) scale(1.5);
    opacity: 0;
  }
}
</style>
