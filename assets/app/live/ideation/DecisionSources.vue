<script setup lang="ts">
import { useI18n } from "vue-i18n";
import { Layers, StickyNote, X, EyeOff } from "@lucide/vue";
import { Button } from "@components/ui/button";
import type { DecisionSource, DecisionSourceIdentity } from "./decisionTypes";
defineProps<{ sources: DecisionSource[]; editable?: boolean; pending?: boolean }>();
const emit = defineEmits<{ remove: [source: DecisionSourceIdentity] }>();
const { t } = useI18n();
</script>
<template>
  <ul class="space-y-2">
    <li
      v-for="source in sources"
      :key="source.identity"
      :data-decision-source="source.identity"
      :data-available="source.available"
      class="rounded-lg border border-border bg-background/60 p-3"
    >
      <div class="flex items-start gap-2">
        <EyeOff v-if="!source.available" class="mt-0.5 size-4 shrink-0 text-muted-foreground" />
        <Layers
          v-else-if="source.type === 'group'"
          class="mt-0.5 size-4 shrink-0 text-muted-foreground"
        />
        <StickyNote v-else class="mt-0.5 size-4 shrink-0 text-muted-foreground" />
        <div class="min-w-0 flex-1">
          <p class="break-words text-xs font-medium">
            {{
              source.available
                ? source.title || t("brainstormingDecisions.untitledSource")
                : t("brainstormingDecisions.sourceUnavailable")
            }}
          </p>
          <p v-if="source.available" class="mt-0.5 text-[10px] text-muted-foreground">
            {{ t(`brainstormingDecisions.sourceTypes.${source.type}`) }} ·
            {{ t("brainstormingDecisions.sourceVersion", { version: source.version }) }}
          </p>
        </div>
        <Button
          v-if="editable"
          variant="ghost"
          size="icon-sm"
          class="-my-1 -mr-1 shrink-0"
          :disabled="pending"
          :aria-label="
            source.available
              ? t('brainstormingDecisions.removeSource', { title: source.title })
              : t('brainstormingDecisions.removeUnavailableSources')
          "
          @click="emit('remove', { type: source.type, id: source.id, identity: source.identity })"
          ><X class="size-3.5"
        /></Button>
      </div>
      <p v-if="!source.available" class="mt-2 text-xs text-muted-foreground">
        {{ t("brainstormingDecisions.sourceUnavailableHelp") }}
      </p>
      <template v-else>
        <details v-if="source.preview" class="mt-2 text-xs">
          <summary class="cursor-pointer text-muted-foreground hover:text-foreground">
            {{ t("brainstormingDecisions.viewSource") }}
          </summary>
          <p class="mt-2 max-h-48 overflow-y-auto whitespace-pre-wrap break-words leading-relaxed">
            {{ source.preview }}
          </p>
        </details>
        <p v-if="source.changed" class="mt-2 text-[11px] text-amber-700 dark:text-amber-400">
          {{ t("brainstormingDecisions.sourceChanged") }}
        </p>
      </template>
    </li>
  </ul>
</template>
