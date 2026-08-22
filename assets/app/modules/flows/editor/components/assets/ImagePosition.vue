<script setup lang="ts">
import { computed } from "vue";
import { Label } from "@components/ui/label";
import { ToggleGroup, ToggleGroupItem } from "@components/ui/toggle-group";
import ImageFit from "./ImageFit.vue";

const POSITIONS = [
  "top-left",
  "top-center",
  "top-right",
  "middle-left",
  "middle-center",
  "middle-right",
  "bottom-left",
  "bottom-center",
  "bottom-right",
] as const;

type Position = (typeof POSITIONS)[number];

type Fit = "cover" | "contain" | "fill";

const {
  position = "middle-center",
  fit = "cover",
  canEdit = false,
  positionLabel,
  fitLabel,
} = defineProps<{
  position?: string;
  fit?: Fit;
  canEdit?: boolean;
  positionLabel?: string;
  fitLabel?: string;
}>();

const emit = defineEmits<{
  "position-change": [value: string];
  "fit-change": [value: Fit];
}>();

const normalizedPosition = computed(() => normalizePosition(position));

function onPositionChange(v: string | string[]) {
  // ToggleGroup type=single emits "" when clicking the active item — ignore
  // since we don't allow "no position".
  const next = Array.isArray(v) ? v[0] : v;
  if (!next) return;
  emit("position-change", next);
}

function normalizePosition(value: string): Position {
  if (value === "center-left") return "middle-left";
  if (value === "center") return "middle-center";
  if (value === "center-right") return "middle-right";
  if ((POSITIONS as readonly string[]).includes(value)) return value as Position;
  return "middle-center";
}

function positionTitle(pos: Position): string {
  return pos
    .split("-")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function anchorDotClass(pos: Position): string {
  const [row, col] = pos.split("-");
  const xClasses: Record<string, string> = {
    left: "left-0",
    center: "left-1/2 -translate-x-1/2",
    right: "right-0",
  };
  const yClasses: Record<string, string> = {
    top: "top-0",
    middle: "top-1/2 -translate-y-1/2",
    bottom: "bottom-0",
  };

  return `${xClasses[col]} ${yClasses[row]}`;
}
</script>

<template>
  <div class="flex gap-3">
    <div class="flex flex-col gap-1.5">
      <Label class="text-xs text-muted-foreground">
        {{ positionLabel || $t("common.assets.image.position_label") }}
      </Label>
      <ToggleGroup
        type="single"
        variant="outline"
        size="xs"
        :model-value="normalizedPosition"
        :disabled="!canEdit"
        class="grid grid-cols-3 gap-1 w-fit"
        @update:model-value="onPositionChange"
      >
        <ToggleGroupItem
          v-for="pos in POSITIONS"
          :key="pos"
          :value="pos"
          class="aspect-square px-0 grid place-items-center"
          :title="positionTitle(pos)"
          :aria-label="positionTitle(pos)"
        >
          <span class="relative block size-4 rounded border border-current/25">
            <span
              :class="[
                'absolute size-1.5 rounded-full bg-current transition-all',
                anchorDotClass(pos),
                normalizedPosition === pos ? 'opacity-100 scale-110' : 'opacity-50 scale-90',
              ]"
            />
          </span>
        </ToggleGroupItem>
      </ToggleGroup>
    </div>

    <ImageFit
      :fit="fit"
      :can-edit="canEdit"
      :fit-label="fitLabel"
      @fit-change="emit('fit-change', $event)"
    />
  </div>
</template>
