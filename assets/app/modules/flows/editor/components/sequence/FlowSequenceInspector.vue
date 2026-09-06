<script setup lang="ts">
import { computed } from "vue";
import { RotateCcw, Trash2 } from "@lucide/vue";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
import ImageAsset from "../assets/ImageAsset.vue";
import ImageFit from "../assets/ImageFit.vue";
import type { SequenceAssetEntry, SequenceVisualLayerRecord } from "@modules/flows/sequence/types";

export interface SequenceLayerPatch {
  asset_id?: string | number;
  label?: string;
  x?: number;
  y?: number;
  width?: number;
  height?: number;
  fit?: "cover" | "contain" | "fill";
  opacity?: number;
  visible?: boolean;
}

const {
  layer,
  imageAssets,
  canEdit,
  locked = false,
} = defineProps<{
  layer: SequenceVisualLayerRecord | null;
  imageAssets: SequenceAssetEntry[];
  canEdit: boolean;
  locked?: boolean;
}>();
const emit = defineEmits<{
  update: [patch: SequenceLayerPatch];
  remove: [];
  revert: [fields: string[]];
}>();
const fields = ["x", "y", "width", "height"] as const;
const overrides = computed(() => layer?.overridden_fields ?? layer?.overriddenFields ?? []);
const assets = computed(() => {
  const id = layer?.assetId ?? layer?.asset_id;
  if (!layer?.url || id == null || imageAssets.some((a) => String(a.id) === String(id)))
    return imageAssets;
  return [{ id, filename: layer.label ?? "", url: layer.url }, ...imageAssets];
});

function numeric(field: (typeof fields)[number], event: Event) {
  const value = Number((event.target as HTMLInputElement).value) / 100;
  if (!Number.isFinite(value) || !canEdit || locked) return;
  emit("update", { [field]: value });
}

function opacity(event: Event) {
  const value = Number((event.target as HTMLInputElement).value) / 100;
  if (Number.isFinite(value) && canEdit) emit("update", { opacity: value });
}
</script>

<template>
  <section class="border-t border-border pt-3" data-sequence-inspector>
    <p v-if="!layer" class="py-3 text-center text-xs text-muted-foreground">
      {{ $t("flows.sequence_workspace.select_layer") }}
    </p>
    <div v-else class="flex min-w-0 flex-col gap-3" :data-inspected-layer="layer.key ?? layer.id">
      <div class="flex items-center gap-2">
        <Input
          :model-value="layer.label ?? ''"
          :disabled="!canEdit"
          size="sm"
          :aria-label="$t('flows.sequence_workspace.layer_name')"
          @change="emit('update', { label: ($event.target as HTMLInputElement).value })"
        />
        <Button
          variant="ghost"
          size="icon-sm"
          :disabled="!canEdit"
          :aria-label="$t('flows.sequences.visual_layers.delete')"
          data-remove-layer
          @click="emit('remove')"
          ><Trash2 class="size-3.5"
        /></Button>
      </div>
      <ImageAsset
        :label="$t('flows.sequence_workspace.image')"
        :asset-id="layer.assetId ?? layer.asset_id"
        :image-assets="assets"
        :can-edit="canEdit"
        preview-fit="contain"
        search-event="picker_search"
        :search-payload="{ resource: 'asset', kind: 'image' }"
        @select="emit('update', { asset_id: $event.id })"
        @clear="emit('remove')"
      />
      <div class="grid grid-cols-2 gap-2">
        <label
          v-for="field in fields"
          :key="field"
          class="grid gap-1 text-[11px] text-muted-foreground"
        >
          {{ $t(`flows.sequences.config_panel.fields.${field}`) }} %
          <Input
            type="number"
            size="sm"
            :model-value="
              Math.round(
                Number(layer[field] ?? (field === 'width' || field === 'height' ? 1 : 0)) * 10000,
              ) / 100
            "
            :min="field === 'x' || field === 'y' ? -1000 : 0.01"
            :max="field === 'x' || field === 'y' ? 1000 : 2000"
            step="1"
            :disabled="!canEdit || locked"
            :data-layer-field="field"
            @change="numeric(field, $event)"
          />
        </label>
      </div>
      <p v-if="locked" class="text-[11px] text-muted-foreground">
        {{ $t("flows.sequence_workspace.position_locked") }}
      </p>
      <ImageFit
        :fit="layer.fit ?? 'contain'"
        :can-edit="canEdit"
        @fit-change="emit('update', { fit: $event })"
      />
      <label class="grid gap-2 text-xs">
        <span
          >{{ $t("flows.sequences.config_panel.fields.opacity") }} ·
          {{ Math.round((layer.opacity ?? 1) * 100) }}%</span
        >
        <input
          type="range"
          min="0"
          max="100"
          step="1"
          class="w-full accent-primary"
          :value="Math.round((layer.opacity ?? 1) * 100)"
          :disabled="!canEdit"
          @change="opacity"
        />
      </label>
      <div
        v-if="layer.origin?.inherited"
        class="rounded-md bg-muted/40 p-2 text-[11px] text-muted-foreground"
      >
        <p>{{ $t("flows.sequence_workspace.inherited_from", { id: layer.origin.nodeId }) }}</p>
        <Button
          v-if="overrides.length"
          variant="ghost"
          size="xs"
          class="mt-1 gap-1"
          :disabled="!canEdit"
          data-revert-layer
          @click="emit('revert', overrides)"
          ><RotateCcw class="size-3" />{{ $t("flows.sequence_workspace.reset_changes") }}</Button
        >
      </div>
    </div>
  </section>
</template>
