<script setup lang="ts">
import { useI18n } from "vue-i18n";
import { ChevronRight, EyeOff, Layers, StickyNote, X } from "@lucide/vue";
import { Button } from "@components/ui/button";
import { sourceLabel } from "./decisionStatus";
import type { DecisionSource, DecisionSourceIdentity } from "./decisionTypes";

const {
  sources,
  variant = "detail",
  editable = false,
  pending = false,
} = defineProps<{
  sources: DecisionSource[];
  variant?: "form" | "detail";
  editable?: boolean;
  pending?: boolean;
}>();
const emit = defineEmits<{ remove: [source: DecisionSourceIdentity] }>();
const { t } = useI18n();

function meta(source: DecisionSource) {
  return [
    t(`brainstormingDecisions.sourceKinds.${source.type}`),
    source.authorName,
    source.roundNumber
      ? t("brainstormingDecisions.sourceRound", { number: source.roundNumber })
      : null,
  ]
    .filter(Boolean)
    .join(" · ");
}
</script>
<template>
  <ul class="flex flex-col" :class="variant === 'form' ? 'gap-1.5' : 'gap-2'">
    <li
      v-for="source in sources"
      :key="source.identity"
      :data-decision-source="source.identity"
      :data-available="source.available"
      :class="
        variant === 'form'
          ? 'flex min-h-10 items-center gap-2.5 rounded-[10px] border border-border bg-card/60 py-1.5 pr-2.5 pl-3'
          : 'rounded-xl border border-border bg-card/60 p-3'
      "
    >
      <template v-if="variant === 'form'">
        <EyeOff
          v-if="!source.available"
          class="size-3.5 shrink-0 text-amber-700 dark:text-amber-400"
        />
        <component
          :is="source.type === 'group' ? Layers : StickyNote"
          v-else
          class="size-3.5 shrink-0 text-muted-foreground"
        />
        <div class="min-w-0 flex-1">
          <p class="truncate text-[13px] leading-[18px]">
            {{
              source.available ? sourceLabel(source) : t("brainstormingDecisions.sourceUnavailable")
            }}
          </p>
          <p class="text-[11px] text-muted-foreground">
            {{
              source.available ? meta(source) : t("brainstormingDecisions.sourceUnavailableHelp")
            }}
          </p>
          <p v-if="source.changed" class="text-[11px] text-amber-700 dark:text-amber-400">
            {{ t("brainstormingDecisions.sourceChanged") }}
          </p>
        </div>
        <Button
          v-if="editable"
          variant="ghost"
          size="icon-sm"
          class="-my-1 shrink-0"
          :disabled="pending"
          :aria-label="
            source.available
              ? t('brainstormingDecisions.removeSource', { title: sourceLabel(source) })
              : t('brainstormingDecisions.removeUnavailableSources')
          "
          @click="emit('remove', { type: source.type, id: source.id, identity: source.identity })"
          ><X class="size-3.5"
        /></Button>
      </template>
      <template v-else>
        <div class="flex items-start gap-2.5">
          <EyeOff
            v-if="!source.available"
            class="mt-0.5 size-[15px] shrink-0 text-amber-700 dark:text-amber-400"
          />
          <component
            :is="source.type === 'group' ? Layers : StickyNote"
            v-else
            class="mt-0.5 size-[15px] shrink-0 text-muted-foreground"
          />
          <div class="min-w-0 flex-1">
            <p class="text-[13px] leading-[18px] font-medium text-pretty break-words">
              {{
                source.available
                  ? sourceLabel(source)
                  : t("brainstormingDecisions.sourceUnavailable")
              }}
            </p>
            <p class="mt-0.5 text-[11px] text-muted-foreground">
              {{ t(`brainstormingDecisions.sourceTypes.${source.type}`) }} ·
              {{ t("brainstormingDecisions.sourceVersion", { version: source.version }) }}
            </p>
          </div>
        </div>
        <p
          v-if="!source.available"
          class="mt-2 flex items-center gap-1.5 text-xs text-amber-700 dark:text-amber-400"
        >
          {{ t("brainstormingDecisions.sourceUnavailableHelp") }}
        </p>
        <template v-else>
          <details v-if="source.preview" class="group mt-2 text-xs">
            <summary
              class="flex cursor-pointer list-none items-center gap-1.5 text-muted-foreground hover:text-foreground"
            >
              <ChevronRight class="size-[11px] transition-transform group-open:rotate-90" />{{
                t("brainstormingDecisions.viewSource")
              }}
            </summary>
            <p
              class="mt-2 max-h-48 overflow-y-auto leading-relaxed break-words whitespace-pre-wrap"
            >
              {{ source.preview }}
            </p>
          </details>
          <p v-if="source.changed" class="mt-2 text-xs text-amber-700 dark:text-amber-400">
            {{ t("brainstormingDecisions.sourceChanged") }}
          </p>
        </template>
      </template>
    </li>
  </ul>
</template>
