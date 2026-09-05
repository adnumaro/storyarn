<script setup lang="ts">
import { Sparkles } from "@lucide/vue";
import { computed } from "vue";
import { Button } from "@components/ui/button";
import { TONES } from "../../domain/status";
import type { TextRow } from "../../domain/types";
import StatusBadge from "../status/StatusBadge.vue";
import TextFlag from "../status/TextFlag.vue";

/** One string of the list: status, flags, context, source and translation. */
const {
  text,
  selected = false,
  canTranslate = false,
  translating = false,
} = defineProps<{
  text: TextRow;
  selected?: boolean;
  canTranslate?: boolean;
  translating?: boolean;
}>();

const emit = defineEmits<{ select: []; translate: [] }>();

const voNeeded = computed(() => text.voEligible && text.voStatus === "needed");
const voDot = TONES.vo_needed.dot;
</script>

<template>
  <article class="group relative border-b border-border/60 last:border-b-0">
    <button
      type="button"
      :class="[
        'flex w-full flex-col gap-1 border-l-2 py-2.5 pr-4 pl-3.5 text-left outline-none transition-colors focus-visible:bg-accent/70',
        selected ? 'border-primary bg-accent' : 'border-transparent hover:bg-accent/50',
        canTranslate && 'pr-10',
      ]"
      :data-row-id="text.id"
      :aria-current="selected ? 'true' : undefined"
      @click="emit('select')"
    >
      <span class="flex w-full items-center gap-2 text-[11px] text-muted-foreground">
        <StatusBadge :status="text.status" />
        <TextFlag v-if="text.stale" kind="outdated" />
        <TextFlag v-if="text.machineTranslated" kind="machine" />
        <span class="flex-1" />
        <span v-if="text.speakerName" class="truncate">{{ text.speakerName }}</span>
        <span v-if="text.speakerName" aria-hidden="true">·</span>
        <span class="shrink-0">{{ text.contentRoleLabel }}</span>
        <span
          v-if="voNeeded"
          :class="['size-[7px] shrink-0 rounded-full', voDot]"
          :title="$t('localization.workbench.vo_needed')"
          role="img"
          :aria-label="$t('localization.workbench.vo_needed')"
        />
        <span class="shrink-0 tabular-nums">
          {{ $t("localization.workbench.words_short", { n: text.wordCount }) }}
        </span>
      </span>
      <span class="line-clamp-2 text-[13px] leading-snug text-foreground">
        {{ text.sourceText }}
      </span>
      <span
        :class="[
          'w-full truncate text-xs leading-snug text-muted-foreground',
          !text.translatedText && 'italic',
        ]"
      >
        {{ text.translatedText || $t("localization.workbench.not_translated") }}
      </span>
    </button>

    <Button
      v-if="canTranslate"
      variant="ghost"
      size="icon-xs"
      class="absolute top-1/2 right-2 -translate-y-1/2 opacity-0 transition-opacity group-hover:opacity-100 focus-visible:opacity-100"
      :data-testid="`localization-translate-${text.id}`"
      :aria-label="$t('localization.workbench.translate_deepl')"
      :disabled="translating"
      @click="emit('translate')"
    >
      <Sparkles class="size-3.5" />
    </Button>
  </article>
</template>
