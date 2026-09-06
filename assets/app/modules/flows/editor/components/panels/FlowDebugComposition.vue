<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { CircleX, Layers, Music, Volume2 } from "@lucide/vue";
import { Badge } from "@components/ui/badge";
import { stripHtml } from "../../lib/debug-format";
interface DebugCompositionOverride {
  field: string;
  nodeId: string | number | null;
}

interface DebugCompositionOrigin {
  nodeId: string | number | null;
  sequenceId?: string | number | null;
  inherited?: boolean;
}

interface DebugCompositionItem {
  id: string | number;
  key?: string | number;
  trackKey?: string | number;
  kind: string;
  label?: string | null;
  filename?: string | null;
  sequenceId?: string | number | null;
  origin?: DebugCompositionOrigin;
  lastChangedByNodeId?: string | number | null;
  removedByNodeId?: string | number | null;
  overriddenProperties?: DebugCompositionOverride[];
  removed?: boolean;
}

interface DebugCompositionDiagnostic {
  code: string;
  nodeId?: string | number | null;
  severity?: string;
}

export interface DebugComposition {
  presentationNodeId?: string | number | null;
  visualLayers: DebugCompositionItem[];
  removedVisualLayers: DebugCompositionItem[];
  audioTracks: DebugCompositionItem[];
  removedAudioTracks: DebugCompositionItem[];
  diagnostics: DebugCompositionDiagnostic[];
}

const {
  composition = null,
  nodes,
  currentNodeId = null,
} = defineProps<{
  composition?: DebugComposition | null;
  currentNodeId?: number | string | null;
  nodes: Record<string, { sequence_config?: { name?: string } | null; data?: { text?: unknown } }>;
}>();
const { t } = useI18n();
const debugComposition = computed(() => composition);
const compositionNodeId = computed(() => composition?.presentationNodeId ?? currentNodeId);
function sameEntityId(
  left: string | number | null | undefined,
  right: string | number | null | undefined,
) {
  if (left == null || right == null) return false;
  return String(left) === String(right);
}

function debugNodeLabel(nodeId: string | number | null | undefined): string {
  if (nodeId == null) return t("flows.debug.composition_unknown_origin");

  const node = nodes[String(nodeId)];
  const name = node?.sequence_config?.name || stripHtml(node?.data?.text, 28);
  return name || `#${nodeId}`;
}

function visualLayerLabel(layer: DebugCompositionItem): string {
  return layer.label || t(`flows.sequences.visual_layers.kinds.${layer.kind}`);
}

function audioTrackLabel(track: DebugCompositionItem): string {
  return track.filename || t(`flows.sequences.tracks.${track.kind}`);
}

function debugPropertyLabel(field: string): string {
  const key = `flows.sequences.config_panel.fields.${field}`;
  const translated = t(key);
  return translated === key ? field.replaceAll("_", " ") : translated;
}

function debugDiagnosticLabel(code: string): string {
  const key = `flows.sequences.config_panel.diagnostic_messages.${code}`;
  const translated = t(key);

  return translated === key
    ? t("flows.sequences.config_panel.diagnostic_messages.fallback")
    : translated;
}

function compositionOriginKey(item: DebugCompositionItem): string {
  return sameEntityId(item.origin?.nodeId, compositionNodeId.value)
    ? "flows.debug.composition_local"
    : "flows.debug.composition_inherited";
}
</script>
<template>
  <div v-if="debugComposition" class="space-y-3 p-3">
    <div class="flex items-center gap-2">
      <Layers class="size-3.5 text-muted-foreground" aria-hidden="true" />
      <p class="font-medium">
        {{ $t("flows.debug.composition_for", { node: debugNodeLabel(compositionNodeId) }) }}
      </p>
    </div>

    <div
      v-if="debugComposition.diagnostics.length > 0"
      class="space-y-1 rounded-md border border-amber-500/30 bg-amber-500/10 p-2"
      data-debug-composition-diagnostics
    >
      <p
        v-for="diagnostic in debugComposition.diagnostics"
        :key="`${diagnostic.code}:${diagnostic.nodeId ?? ''}`"
        class="text-amber-700 dark:text-amber-300"
      >
        {{ debugDiagnosticLabel(diagnostic.code) }}
        <span v-if="diagnostic.nodeId"> · #{{ diagnostic.nodeId }}</span>
      </p>
    </div>

    <div class="grid grid-cols-1 gap-3 lg:grid-cols-2">
      <section class="min-w-0 space-y-1.5" data-debug-composition-visuals>
        <div class="flex items-center gap-1.5 text-muted-foreground">
          <Layers class="size-3.5" aria-hidden="true" />
          <h3 class="font-medium text-foreground">
            {{ $t("flows.debug.composition_visual_layers") }}
          </h3>
          <span class="tabular-nums">
            {{ debugComposition.visualLayers.length + debugComposition.removedVisualLayers.length }}
          </span>
        </div>

        <article
          v-for="layer in debugComposition.visualLayers"
          :key="String(layer.key ?? layer.id)"
          class="rounded-md border border-border bg-muted/20 px-2.5 py-2"
          :data-debug-layer-key="layer.key ?? layer.id"
        >
          <div class="flex min-w-0 items-center gap-2">
            <Badge variant="outline" class="shrink-0 px-1.5 py-0 text-[9px]">
              {{ $t(`flows.sequences.visual_layers.kinds.${layer.kind}`) }}
            </Badge>
            <span class="min-w-0 flex-1 truncate font-medium">
              {{ visualLayerLabel(layer) }}
            </span>
            <Badge variant="secondary" class="shrink-0 px-1.5 py-0 text-[9px]">
              {{ $t(compositionOriginKey(layer)) }}
            </Badge>
          </div>
          <p class="mt-1 truncate text-[10px] text-muted-foreground">
            {{
              $t("flows.debug.composition_from", {
                origin: debugNodeLabel(layer.origin?.nodeId),
              })
            }}
          </p>
          <div
            v-if="layer.overriddenProperties?.length"
            class="mt-1.5 flex flex-wrap gap-1"
            data-debug-overrides
          >
            <span
              v-for="property in layer.overriddenProperties"
              :key="`${property.field}:${property.nodeId}`"
              class="rounded bg-primary/10 px-1.5 py-0.5 text-[9px] text-primary"
              :data-debug-property="property.field"
            >
              {{ debugPropertyLabel(property.field) }} · {{ debugNodeLabel(property.nodeId) }}
            </span>
          </div>
        </article>

        <article
          v-for="layer in debugComposition.removedVisualLayers"
          :key="`removed:${String(layer.key ?? layer.id)}`"
          class="rounded-md border border-dashed border-destructive/30 bg-destructive/5 px-2.5 py-2"
          :data-debug-removed-layer-key="layer.key ?? layer.id"
        >
          <div class="flex min-w-0 items-center gap-2">
            <CircleX class="size-3.5 shrink-0 text-destructive" aria-hidden="true" />
            <span class="min-w-0 flex-1 truncate font-medium">
              {{ visualLayerLabel(layer) }}
            </span>
            <Badge variant="outline" class="shrink-0 px-1.5 py-0 text-[9px] text-destructive">
              {{ $t("flows.debug.composition_removed") }}
            </Badge>
          </div>
          <p class="mt-1 truncate text-[10px] text-muted-foreground">
            {{
              $t("flows.debug.composition_from", {
                origin: debugNodeLabel(layer.origin?.nodeId),
              })
            }}
            ·
            {{
              $t("flows.debug.composition_removed_by", {
                origin: debugNodeLabel(layer.removedByNodeId),
              })
            }}
          </p>
        </article>

        <p
          v-if="
            debugComposition.visualLayers.length === 0 &&
            debugComposition.removedVisualLayers.length === 0
          "
          class="rounded-md border border-dashed border-border px-3 py-4 text-center text-muted-foreground"
        >
          {{ $t("flows.debug.composition_no_visual_layers") }}
        </p>
      </section>

      <section class="min-w-0 space-y-1.5" data-debug-composition-audio>
        <div class="flex items-center gap-1.5 text-muted-foreground">
          <Music class="size-3.5" aria-hidden="true" />
          <h3 class="font-medium text-foreground">
            {{ $t("flows.debug.composition_audio_tracks") }}
          </h3>
          <span class="tabular-nums">
            {{ debugComposition.audioTracks.length + debugComposition.removedAudioTracks.length }}
          </span>
        </div>

        <article
          v-for="track in debugComposition.audioTracks"
          :key="String(track.trackKey ?? track.id)"
          class="rounded-md border border-border bg-muted/20 px-2.5 py-2"
          :data-debug-track-key="track.trackKey ?? track.id"
        >
          <div class="flex min-w-0 items-center gap-2">
            <Volume2 class="size-3.5 shrink-0 text-muted-foreground" aria-hidden="true" />
            <span class="min-w-0 flex-1 truncate font-medium">
              {{ audioTrackLabel(track) }}
            </span>
            <Badge variant="secondary" class="shrink-0 px-1.5 py-0 text-[9px]">
              {{ $t(compositionOriginKey(track)) }}
            </Badge>
          </div>
          <p class="mt-1 truncate text-[10px] text-muted-foreground">
            {{
              $t("flows.debug.composition_from", {
                origin: debugNodeLabel(track.origin?.nodeId),
              })
            }}
          </p>
          <div
            v-if="track.overriddenProperties?.length"
            class="mt-1.5 flex flex-wrap gap-1"
            data-debug-overrides
          >
            <span
              v-for="property in track.overriddenProperties"
              :key="`${property.field}:${property.nodeId}`"
              class="rounded bg-primary/10 px-1.5 py-0.5 text-[9px] text-primary"
              :data-debug-property="property.field"
            >
              {{ debugPropertyLabel(property.field) }} · {{ debugNodeLabel(property.nodeId) }}
            </span>
          </div>
        </article>

        <article
          v-for="track in debugComposition.removedAudioTracks"
          :key="`removed:${String(track.trackKey ?? track.id)}`"
          class="rounded-md border border-dashed border-destructive/30 bg-destructive/5 px-2.5 py-2"
          :data-debug-removed-track-key="track.trackKey ?? track.id"
        >
          <div class="flex min-w-0 items-center gap-2">
            <CircleX class="size-3.5 shrink-0 text-destructive" aria-hidden="true" />
            <span class="min-w-0 flex-1 truncate font-medium">
              {{ audioTrackLabel(track) }}
            </span>
            <Badge variant="outline" class="shrink-0 px-1.5 py-0 text-[9px] text-destructive">
              {{ $t("flows.debug.composition_removed") }}
            </Badge>
          </div>
          <p class="mt-1 truncate text-[10px] text-muted-foreground">
            {{
              $t("flows.debug.composition_from", {
                origin: debugNodeLabel(track.origin?.nodeId),
              })
            }}
            ·
            {{
              $t("flows.debug.composition_removed_by", {
                origin: debugNodeLabel(track.removedByNodeId),
              })
            }}
          </p>
        </article>

        <p
          v-if="
            debugComposition.audioTracks.length === 0 &&
            debugComposition.removedAudioTracks.length === 0
          "
          class="rounded-md border border-dashed border-border px-3 py-4 text-center text-muted-foreground"
        >
          {{ $t("flows.debug.composition_no_audio_tracks") }}
        </p>
      </section>
    </div>
  </div>

  <div
    v-else
    class="flex h-24 items-center justify-center px-4 text-center text-muted-foreground/70"
    data-debug-composition-unavailable
  >
    {{ $t("flows.debug.composition_unavailable") }}
  </div>
</template>
