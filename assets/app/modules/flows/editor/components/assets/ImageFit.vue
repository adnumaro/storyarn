<script setup lang="ts">
import { Label } from "@components/ui/label";
import { ToggleGroup, ToggleGroupItem } from "@components/ui/toggle-group";

type Fit = "cover" | "contain" | "fill";
const FITS: readonly Fit[] = ["cover", "contain", "fill"] as const;

const {
  fit = "cover",
  canEdit = false,
  fitLabel,
} = defineProps<{
  fit?: Fit;
  canEdit?: boolean;
  fitLabel?: string;
}>();

const emit = defineEmits<{
  "fit-change": [value: Fit];
}>();

function onFitChange(v: string | string[]) {
  const next = Array.isArray(v) ? v[0] : v;
  if (!next) return;
  emit("fit-change", next as Fit);
}
</script>

<template>
  <div class="flex w-60 max-w-full flex-none flex-col gap-1.5">
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
      <ToggleGroupItem v-for="opt in FITS" :key="opt" :value="opt" class="flex-1 text-xs">
        {{ $t(`common.assets.image.fit_${opt}`) }}
      </ToggleGroupItem>
    </ToggleGroup>
  </div>
</template>
