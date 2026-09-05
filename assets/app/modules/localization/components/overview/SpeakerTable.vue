<script setup lang="ts">
import LiveLink from "@components/navigation/LiveLink.vue";
import UserAvatar from "@components/UserAvatar.vue";
import type { SpeakerStat } from "../../domain/types";
import { workbenchUrl } from "../../navigation/workbenchUrl";

/**
 * Voice lines and words per speaker. A named speaker opens the workbench
 * filtered to its lines; lines without a speaker cannot be filtered.
 */
const { speakers, workbenchBase } = defineProps<{
  speakers: SpeakerStat[];
  workbenchBase: string;
}>();

const rowClass =
  "grid grid-cols-[minmax(0,1fr)_4.5rem_4.5rem] items-center gap-2 border-b border-border/60 px-4 py-2.5 text-[13px] tabular-nums last:border-b-0";
</script>

<template>
  <div class="overflow-hidden rounded-lg border border-border bg-card">
    <div
      class="grid grid-cols-[minmax(0,1fr)_4.5rem_4.5rem] gap-2 border-b border-border px-4 py-2.5 text-xs text-muted-foreground"
    >
      <span>{{ $t("localization.overview.speakers.speaker") }}</span>
      <span class="text-right">{{ $t("localization.overview.speakers.lines") }}</span>
      <span class="text-right">{{ $t("localization.overview.speakers.words") }}</span>
    </div>

    <p v-if="speakers.length === 0" class="px-4 py-6 text-center text-sm text-muted-foreground">
      {{ $t("localization.overview.speakers.empty") }}
    </p>

    <template v-for="speaker in speakers" :key="speaker.speakerSheetId ?? 'none'">
      <LiveLink
        v-if="speaker.speakerSheetId"
        :to="workbenchUrl(workbenchBase, { speaker: speaker.speakerSheetId })"
        :class="[rowClass, 'text-foreground transition-colors hover:bg-accent/60']"
      >
        <span class="flex min-w-0 items-center gap-2.5">
          <UserAvatar :display-name="speaker.speakerName ?? ''" size="xs" />
          <span class="truncate">
            {{
              speaker.speakerName ??
              $t("localization.overview.speakers.speaker_id", { id: speaker.speakerSheetId })
            }}
          </span>
        </span>
        <span class="text-right">{{ speaker.lineCount }}</span>
        <span class="text-right">{{ speaker.wordCount }}</span>
      </LiveLink>
      <div v-else :class="[rowClass, 'text-muted-foreground']">
        <span class="italic">{{ $t("localization.overview.speakers.no_speaker") }}</span>
        <span class="text-right">{{ speaker.lineCount }}</span>
        <span class="text-right">{{ speaker.wordCount }}</span>
      </div>
    </template>
  </div>
</template>
