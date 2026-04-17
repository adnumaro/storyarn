<script setup lang="ts">
import { Avatar, AvatarImage, AvatarFallback } from "@components/ui/avatar";

export interface SlideData {
  type: "dialogue" | "slug_line" | "empty" | "outcome";
  // dialogue fields
  speaker_name?: string | null;
  speaker_initials?: string;
  speaker_avatar_url?: string | null;
  speaker_color?: string | null;
  text?: string;
  stage_directions?: string;
  // slug_line fields
  setting?: string;
  location_name?: string;
  sub_location?: string;
  time_of_day?: string;
  description?: string;
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
    <!-- eslint-disable-next-line vue/no-v-html -->
    <div class="player-text" v-html="slide.text" />
    <div v-if="slide.stage_directions" class="player-stage-directions">
      {{ slide.stage_directions }}
    </div>
  </div>

  <!-- Slug line -->
  <div v-else-if="slide.type === 'slug_line'" class="player-slide player-slide-slug-line">
    <div class="player-scene-slug">
      {{ slide.setting }}. {{ slide.location_name }}
      <span v-if="slide.sub_location"> &mdash; {{ slide.sub_location }}</span>
      <span v-if="slide.time_of_day"> &mdash; {{ slide.time_of_day.toUpperCase() }}</span>
    </div>
    <!-- eslint-disable-next-line vue/no-v-html -->
    <div v-if="slide.description" class="player-scene-description" v-html="slide.description" />
  </div>

  <!-- Empty -->
  <div v-else-if="slide.type === 'empty'" class="player-slide player-slide-empty">
    <p class="text-muted-foreground">{{ $t("flows.player.no_content") }}</p>
  </div>

  <!-- Fallback -->
  <div v-else class="player-slide" />
</template>
