<script setup lang="ts">
import { Label } from "@components/ui/label";
import { ToggleGroup, ToggleGroupItem } from "@components/ui/toggle-group";

const POSITIONS = [
  "top-left",
  "top-center",
  "top-right",
  "center-left",
  "center",
  "center-right",
  "bottom-left",
  "bottom-center",
  "bottom-right",
] as const;

type Fit = "cover" | "contain" | "fill";
const FITS: readonly Fit[] = ["cover", "contain", "fill"] as const;

const {
  position = "center",
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

function onPositionChange(v: string | string[]) {
  // ToggleGroup type=single emits "" when clicking the active item — ignore
  // since we don't allow "no position".
  const next = Array.isArray(v) ? v[0] : v;
  if (!next) return;
  emit("position-change", next);
}

function onFitChange(v: string | string[]) {
  const next = Array.isArray(v) ? v[0] : v;
  if (!next) return;
  emit("fit-change", next as Fit);
}
</script>

<template>
  <div class="flex  gap-3">
    <div class="flex flex-col gap-1.5">
      <Label class="text-xs text-muted-foreground">
        {{ positionLabel || $t("common.assets.image.position_label") }}
      </Label>
      <ToggleGroup
        type="single"
        variant="outline"
        size="xs"
        :model-value="position"
        :disabled="!canEdit"
        class="grid grid-cols-3 gap-1 w-fit"
        @update:model-value="onPositionChange"
      >
        <ToggleGroupItem
          v-for="pos in POSITIONS"
          :key="pos"
          :value="pos"
          class="aspect-square px-0"
          :title="pos"
        />
      </ToggleGroup>
    </div>

    <div class="flex flex-col gap-1.5">
      <Label class="text-xs text-muted-foreground">
        {{ fitLabel || $t("common.assets.image.fit_label") }}
      </Label>
      <ToggleGroup
        type="single"
        variant="outline"
        size="sm"
        :model-value="fit"
        :disabled="!canEdit"
        class="w-full"
        @update:model-value="onFitChange"
      >
        <ToggleGroupItem
          v-for="opt in FITS"
          :key="opt"
          :value="opt"
          class="flex-1 text-xs"
        >
          {{ $t(`common.assets.image.fit_${opt}`) }}
        </ToggleGroupItem>
      </ToggleGroup>
    </div>
  </div>
</template>
