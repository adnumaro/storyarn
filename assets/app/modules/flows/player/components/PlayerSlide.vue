<script setup lang="ts">
import { Avatar, AvatarImage, AvatarFallback } from "@components/ui/avatar";

export interface SlideData {
  type: "dialogue" | "empty" | "outcome";
  // dialogue fields
  speaker_name?: string | null;
  speaker_initials?: string;
  speaker_avatar_url?: string | null;
  speaker_color?: string | null;
  text?: string;
  stage_directions?: string;
}

const { slide } = defineProps<{
  slide: SlideData;
}>();
</script>

<template>
  <!-- Dialogue -->
  <div v-if="slide.type === 'dialogue'" class="player-slide player-slide-dialogue">
    <div class="player-speaker">
      <Avatar class="size-12">
        <AvatarImage v-if="slide.speaker_avatar_url" :src="slide.speaker_avatar_url" />
        <AvatarFallback
          :style="slide.speaker_color ? `background-color: ${slide.speaker_color}` : undefined"
          class="text-sm font-bold text-white"
        >
          {{ slide.speaker_initials }}
        </AvatarFallback>
      </Avatar>
      <div v-if="slide.speaker_name" class="player-speaker-name">
        {{ slide.speaker_name }}
      </div>
    </div>

    <div class="player-dialogue-body">
      <!-- eslint-disable-next-line vue/no-v-html -->
      <div class="player-text" v-html="slide.text" />
      <div v-if="slide.stage_directions" class="player-stage-directions">
        {{ slide.stage_directions }}
      </div>
    </div>
  </div>

  <!-- Empty -->
  <div v-else-if="slide.type === 'empty'" class="player-slide player-slide-empty">
    <p class="text-muted-foreground">{{ $t("flows.player.no_content") }}</p>
  </div>

  <!-- Fallback -->
  <div v-else class="player-slide" />
</template>
