<script setup lang="ts">
import { computed, onBeforeUnmount, watch } from "vue";
import { ListChecks } from "@lucide/vue";
import DecisionCard from "@app/live/ideation/DecisionCard.vue";
import { shownRevision } from "@app/live/ideation/decisionStatus";
import type { DecisionSource } from "@app/live/ideation/decisionTypes";
import { useBoardText } from "../composables/useBoardText";
import { LANE_CARD_WIDTH, type LaneLayout } from "../lib/decisionLanes";

interface Bounds {
  x: number;
  y: number;
  width: number;
  height: number;
}

const {
  lanes,
  focusId = null,
  comments = {},
  roundNumbers,
  roundCount = 1,
  zoom = 1,
  movable = () => false,
  anchor,
} = defineProps<{
  lanes: LaneLayout[];
  focusId?: number | null;
  /** Messages in each decision's open discussion. */
  comments?: Record<string, number>;
  /** Round number of every band holding a lane, for its label. */
  roundNumbers: Map<number, number>;
  roundCount?: number;
  zoom?: number;
  /** Whether a round's lane can be dragged, by its frame or by any of its cards. */
  movable?: (roundId: number) => boolean;
  /** Where a source sits on the canvas, when the reader can see it. */
  anchor: (source: DecisionSource) => Bounds | null;
}>();
const emit = defineEmits<{
  focus: [id: number];
  open: [id: number];
  measure: [height: number];
  pointer: [event: PointerEvent, roundId: number];
}>();
const { t } = useBoardText();

// Connectors rise from the top of a card to the bottom of each source it cites.
const links = computed(() =>
  lanes.flatMap((lane) =>
    lane.cards.flatMap((card) =>
      shownRevision(card.decision).sources.flatMap((source) => {
        const bounds = source.available ? anchor(source) : null;
        if (!bounds) return [];
        return [
          {
            key: `${card.decision.id}-${source.identity}`,
            decision: card.decision.id,
            x1: card.x + LANE_CARD_WIDTH / 2,
            y1: card.y,
            x2: bounds.x + bounds.width / 2,
            y2: bounds.y + bounds.height,
          },
        ];
      }),
    ),
  ),
);
// A focused decision outlines its sources the way a multi-selection does.
const outlines = computed(() => {
  if (focusId === null) return [];
  const card = lanes.flatMap((lane) => lane.cards).find((item) => item.decision.id === focusId);
  if (!card) return [];
  return shownRevision(card.decision)
    .sources.map((source) => (source.available ? anchor(source) : null))
    .filter((bounds): bounds is Bounds => bounds !== null);
});

let observer: ResizeObserver | null = null;
const heights = new Map<Element, number>();
function measure(element: Element | null) {
  if (!element || typeof ResizeObserver === "undefined") return;
  observer ??= new ResizeObserver((entries) => {
    for (const entry of entries)
      heights.set(entry.target, (entry.target as HTMLElement).offsetHeight);
    emit("measure", Math.max(0, ...heights.values()));
  });
  observer.observe(element);
}
watch(
  () => lanes.map((lane) => lane.cards.length).join(","),
  () => heights.clear(),
);
onBeforeUnmount(() => observer?.disconnect());

// Cards stay in place inside the lane, so a press that turns into a drag moves
// the lane; only a press that stays put selects the card.
let pressed: { x: number; y: number } | null = null;
function press(event: PointerEvent, roundId: number) {
  pressed = { x: event.clientX, y: event.clientY };
  emit("pointer", event, roundId);
}
function choose(event: MouseEvent, id: number) {
  const dragged = pressed && Math.hypot(event.clientX - pressed.x, event.clientY - pressed.y) > 3;
  pressed = null;
  if (!dragged) emit("focus", id);
}

function label(lane: LaneLayout) {
  const count = lane.cards.length;
  return roundCount > 1
    ? t("brainstormingDecisions.laneRound", { number: roundNumbers.get(lane.roundId) ?? "", count })
    : t("brainstormingDecisions.lane", { count });
}
</script>
<template>
  <div
    v-for="lane in lanes"
    :id="`decision-lane-${lane.roundId}`"
    :key="`lane-${lane.roundId}`"
    :data-decision-lane="lane.roundId"
    :data-canvas-chrome="movable(lane.roundId) ? '' : undefined"
    class="absolute left-0 top-0 rounded-xl border border-dashed border-border bg-muted/[0.18]"
    :class="
      movable(lane.roundId)
        ? 'pointer-events-auto cursor-grab active:cursor-grabbing'
        : 'pointer-events-none'
    "
    :style="{
      transform: `translate(${lane.x}px, ${lane.y}px)`,
      width: `${lane.width}px`,
      height: `${lane.height}px`,
    }"
    @pointerdown.stop="emit('pointer', $event, lane.roundId)"
  >
    <span
      class="absolute -top-[9px] left-3.5 inline-flex h-[18px] items-center gap-1.5 rounded-full border border-border bg-background px-2 text-[10.5px] font-semibold tracking-[.06em] text-muted-foreground uppercase"
      ><ListChecks class="size-[11px]" />{{ label(lane) }}</span
    >
  </div>
  <div
    v-for="bounds in outlines"
    :key="`outline-${bounds.x}-${bounds.y}`"
    data-decision-source-outline
    class="pointer-events-none absolute left-0 top-0 rounded-lg border-2 border-primary"
    :style="{
      transform: `translate(${bounds.x - 4}px, ${bounds.y - 4}px)`,
      width: `${bounds.width + 8}px`,
      height: `${bounds.height + 8}px`,
    }"
  />
  <svg
    class="pointer-events-none absolute overflow-visible"
    width="1"
    height="1"
    aria-hidden="true"
  >
    <line
      v-for="link in links"
      :key="link.key"
      :data-decision-link="link.decision"
      v-bind="{ x1: link.x1, y1: link.y1, x2: link.x2, y2: link.y2 }"
      stroke="currentColor"
      :class="
        focusId === link.decision
          ? 'text-primary'
          : focusId === null
            ? 'text-muted-foreground/50'
            : 'text-muted-foreground/25'
      "
      :stroke-width="(focusId === link.decision ? 1.5 : 1) / zoom"
      :stroke-dasharray="focusId === link.decision ? undefined : `${3 / zoom} ${3 / zoom}`"
    />
  </svg>
  <template v-for="lane in lanes" :key="`cards-${lane.roundId}`">
    <div
      v-for="card in lane.cards"
      :id="`decision-lane-card-${card.decision.id}`"
      :key="card.decision.id"
      :ref="(el) => measure(el as Element | null)"
      data-canvas-chrome
      role="button"
      tabindex="0"
      :aria-label="shownRevision(card.decision).title"
      :aria-pressed="focusId === card.decision.id"
      class="pointer-events-auto absolute left-0 top-0 cursor-pointer rounded-xl outline-none select-none focus-visible:ring-2 focus-visible:ring-ring"
      :class="focusId === card.decision.id ? 'z-10' : ''"
      :style="{ transform: `translate(${card.x}px, ${card.y}px)` }"
      @pointerdown.stop="press($event, lane.roundId)"
      @click.stop="choose($event, card.decision.id)"
      @dblclick.stop="emit('open', card.decision.id)"
      @keydown.enter.prevent.stop="emit('open', card.decision.id)"
      @keydown.space.prevent.stop="emit('focus', card.decision.id)"
    >
      <DecisionCard
        size="canvas"
        :decision="card.decision"
        :round-count="roundCount"
        :selected="focusId === card.decision.id"
        :comments="comments[card.decision.id] ?? 0"
      />
    </div>
  </template>
</template>
