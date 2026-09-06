<script setup lang="ts">
import { computed, ref } from "vue";
import { ArrowDown, ArrowUp, Eye, EyeOff, GripVertical, Lock, Unlock } from "@lucide/vue";
import { Button } from "@components/ui/button";
import { compareSequenceLayers, sequenceLayerKey } from "@modules/flows/sequence/layerOrder";
import type { SequenceVisualLayerRecord } from "@modules/flows/sequence/types";

const { layers, selectedKey, lockedKeys, canEdit } = defineProps<{
  layers: SequenceVisualLayerRecord[];
  selectedKey: string | null;
  lockedKeys: string[];
  canEdit: boolean;
}>();
const emit = defineEmits<{
  select: [key: string];
  visibility: [layer: SequenceVisualLayerRecord, visible: boolean];
  lock: [key: string];
  reorder: [keys: string[]];
}>();
const frontToBack = computed(() => [...layers].sort(compareSequenceLayers).reverse());
const draggedKey = ref<string | null>(null);
const selectedIndex = computed(() =>
  frontToBack.value.findIndex((l) => sequenceLayerKey(l) === selectedKey),
);

function move(key: string, target: number) {
  if (!canEdit) return;
  const keys = frontToBack.value.map(sequenceLayerKey);
  const current = keys.indexOf(key);
  if (current < 0 || target < 0 || target >= keys.length || current === target) return;
  keys.splice(current, 1);
  keys.splice(target, 0, key);
  emit("reorder", keys.reverse());
}

function dragStart(event: DragEvent, key: string) {
  if (!canEdit) {
    event.preventDefault();
    return;
  }
  draggedKey.value = key;
  event.dataTransfer?.setData("application/x-storyarn-sequence-layer", key);
  if (event.dataTransfer) event.dataTransfer.effectAllowed = "move";
}

function drop(target: number) {
  if (draggedKey.value) move(draggedKey.value, target);
  draggedKey.value = null;
}
</script>

<template>
  <section :aria-label="$t('flows.sequence_workspace.layers')" data-sequence-layer-list>
    <div class="mb-2 flex items-center justify-between gap-2">
      <span class="text-xs font-medium">{{ $t("flows.sequence_workspace.layers") }}</span>
      <span class="text-[11px] text-muted-foreground">{{
        $t("flows.sequence_workspace.front_to_back")
      }}</span>
    </div>
    <div class="space-y-1">
      <div
        v-for="(layer, index) in frontToBack"
        :key="sequenceLayerKey(layer)"
        :data-layer-row="sequenceLayerKey(layer)"
        :draggable="canEdit"
        class="group flex min-w-0 items-center gap-1 rounded-md border p-1 transition-colors"
        :class="
          selectedKey === sequenceLayerKey(layer)
            ? 'border-primary/60 bg-primary/10'
            : 'border-transparent hover:bg-muted/60'
        "
        @dragstart="dragStart($event, sequenceLayerKey(layer))"
        @dragend="draggedKey = null"
        @dragover.prevent
        @drop.prevent="drop(index)"
      >
        <GripVertical class="size-3 shrink-0 text-muted-foreground" aria-hidden="true" />
        <button
          type="button"
          class="flex min-w-0 flex-1 items-center gap-2 rounded text-left focus-visible:outline-2 focus-visible:outline-ring"
          :aria-pressed="selectedKey === sequenceLayerKey(layer)"
          :data-select-layer="sequenceLayerKey(layer)"
          @click="emit('select', sequenceLayerKey(layer))"
        >
          <img
            v-if="layer.url"
            :src="layer.url"
            alt=""
            class="size-8 shrink-0 rounded bg-muted object-contain"
            draggable="false"
          />
          <span class="min-w-0 flex-1">
            <span class="block truncate text-xs">{{
              layer.label || $t(`flows.sequences.visual_layers.kinds.${layer.kind}`)
            }}</span>
            <span
              v-if="layer.origin?.inherited"
              class="block truncate text-[10px] text-muted-foreground"
              >{{ $t("flows.sequences.config_panel.inherited") }}</span
            >
          </span>
        </button>
        <Button
          variant="ghost"
          size="icon-xs"
          :disabled="!canEdit"
          :aria-pressed="layer.visible !== false"
          :aria-label="`${$t(
            layer.visible === false
              ? 'flows.sequence_workspace.show_layer'
              : 'flows.sequence_workspace.hide_layer',
          )}: ${layer.label?.trim() || sequenceLayerKey(layer)}`"
          @click="emit('visibility', layer, layer.visible === false)"
        >
          <EyeOff v-if="layer.visible === false" class="size-3.5" /><Eye v-else class="size-3.5" />
        </Button>
        <Button
          variant="ghost"
          size="icon-xs"
          :disabled="!canEdit"
          :aria-pressed="lockedKeys.includes(sequenceLayerKey(layer))"
          :aria-label="`${$t('flows.sequence_workspace.lock_layer')}: ${layer.label?.trim() || sequenceLayerKey(layer)}`"
          @click="emit('lock', sequenceLayerKey(layer))"
        >
          <Lock v-if="lockedKeys.includes(sequenceLayerKey(layer))" class="size-3.5" /><Unlock
            v-else
            class="size-3.5 text-muted-foreground"
          />
        </Button>
      </div>
      <p v-if="!layers.length" class="py-4 text-center text-xs text-muted-foreground">
        {{ $t("flows.sequence_workspace.no_layers") }}
      </p>
    </div>
    <div v-if="layers.length" class="mt-2 flex gap-1">
      <Button
        variant="outline"
        size="icon-xs"
        :disabled="!canEdit || selectedIndex <= 0"
        :aria-label="$t('flows.sequence_workspace.bring_forward')"
        data-layer-forward
        @click="selectedKey && move(selectedKey, selectedIndex - 1)"
        ><ArrowUp class="size-3.5"
      /></Button>
      <Button
        variant="outline"
        size="icon-xs"
        :disabled="!canEdit || selectedIndex < 0 || selectedIndex >= layers.length - 1"
        :aria-label="$t('flows.sequence_workspace.send_backward')"
        data-layer-backward
        @click="selectedKey && move(selectedKey, selectedIndex + 1)"
        ><ArrowDown class="size-3.5"
      /></Button>
    </div>
  </section>
</template>
