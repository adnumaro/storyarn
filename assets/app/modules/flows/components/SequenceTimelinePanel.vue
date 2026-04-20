<script setup lang="ts">
/**
 * Sequence timeline panel — bottom-docked stub.
 *
 * P-3 scope: renders 3 fixed-track rows (background / music / ambient) with
 * placeholder content. Clip authoring ships in Premiere v1.
 *
 * Props:
 *   open     — panel visibility
 *   sequence — the active Sequence (nullable when closed)
 */

import { X } from "lucide-vue-next";
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { useLive } from "@composables/useLive";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";

interface SequencePayload {
  id: number;
  name: string;
  tracks: Record<string, unknown[]>;
}

const { open = false, sequence = null } = defineProps<{
  open: boolean;
  sequence: SequencePayload | null;
}>();

const { t } = useI18n();
const live = useLive();

const TRACK_ORDER = ["background", "music", "ambient"] as const;

const nameInput = ref<string>(sequence?.name ?? "");

watch(
  () => sequence?.name,
  (incoming) => {
    nameInput.value = incoming ?? "";
  },
);

const trackLabel = computed(
  () => (key: (typeof TRACK_ORDER)[number]) => t(`flows.sequences.tracks.${key}`),
);

function onClose() {
  live.pushEvent("close_sequence_panel", {});
}

function onNameBlur() {
  const trimmed = nameInput.value.trim();
  if (!sequence || trimmed === "" || trimmed === sequence.name) return;
  live.pushEvent("update_sequence_name", { name: trimmed });
}

function onNameKeydown(e: KeyboardEvent) {
  if (e.key === "Enter") {
    (e.target as HTMLInputElement).blur();
  } else if (e.key === "Escape") {
    nameInput.value = sequence?.name ?? "";
    (e.target as HTMLInputElement).blur();
  }
}
</script>

<template>
  <div v-if="open && sequence" class="sequence-panel">
    <header class="sequence-panel-header">
      <div class="flex items-center gap-2 min-w-0 flex-1">
        <span class="text-xs uppercase tracking-wide text-muted-foreground">
          {{ $t("flows.sequences.panel_title") }}
        </span>
        <Input
          v-model="nameInput"
          :placeholder="$t('flows.sequences.name_placeholder')"
          class="h-7 w-64 text-sm"
          @blur="onNameBlur"
          @keydown="onNameKeydown"
        />
      </div>
      <Button variant="ghost" size="icon" :title="$t('flows.sequences.close')" @click="onClose">
        <X class="size-4" />
      </Button>
    </header>

    <div class="sequence-panel-body">
      <div v-for="key in TRACK_ORDER" :key="key" class="sequence-panel-track">
        <div class="sequence-panel-track-label">
          {{ trackLabel(key) }}
        </div>
        <div class="sequence-panel-track-area">
          <span class="text-xs text-muted-foreground italic">
            {{ $t("flows.sequences.placeholder_clips") }}
          </span>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.sequence-panel {
  position: fixed;
  bottom: 0;
  left: 0;
  right: 0;
  z-index: 40;
  height: 240px;
  background: hsl(var(--background));
  border-top: 1px solid hsl(var(--border));
  box-shadow: 0 -4px 12px rgba(0, 0, 0, 0.08);
  display: flex;
  flex-direction: column;
}

.sequence-panel-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0.5rem 0.75rem;
  border-bottom: 1px solid hsl(var(--border));
}

.sequence-panel-body {
  flex: 1;
  display: flex;
  flex-direction: column;
  overflow-y: auto;
  padding: 0.5rem 0;
}

.sequence-panel-track {
  display: flex;
  align-items: stretch;
  min-height: 52px;
  border-bottom: 1px solid hsl(var(--border) / 0.5);
}

.sequence-panel-track:last-child {
  border-bottom: none;
}

.sequence-panel-track-label {
  width: 120px;
  padding: 0.5rem 0.75rem;
  font-size: 0.75rem;
  font-weight: 500;
  color: hsl(var(--muted-foreground));
  border-right: 1px solid hsl(var(--border) / 0.5);
  display: flex;
  align-items: center;
}

.sequence-panel-track-area {
  flex: 1;
  padding: 0.5rem 0.75rem;
  display: flex;
  align-items: center;
}
</style>
