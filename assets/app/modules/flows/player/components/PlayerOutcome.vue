<script setup lang="ts">
import { Footprints, MousePointerClick, Variable, RotateCcw, ArrowLeft } from "lucide-vue-next";
import { Button } from "@components/ui/button";
import { Badge } from "@components/ui/badge";

export interface OutcomeData {
  type: "outcome";
  label: string;
  outcome_color: string | null;
  outcome_tags: string[];
  step_count: number;
  choices_made: number;
  variables_changed: number;
}

const { slide, editorUrl } = defineProps<{
  slide: OutcomeData;
  editorUrl: string;
}>();

const emit = defineEmits<{
  restart: [];
}>();
</script>

<template>
  <div class="player-slide player-slide-outcome">
    <div
      class="player-outcome-accent"
      :style="slide.outcome_color ? `background-color: ${slide.outcome_color}` : undefined"
    />

    <h2 class="player-outcome-title">
      {{ slide.label }}
    </h2>

    <div v-if="slide.outcome_tags.length > 0" class="player-outcome-tags">
      <Badge v-for="tag in slide.outcome_tags" :key="tag" variant="outline">
        {{ tag }}
      </Badge>
    </div>

    <div class="player-outcome-stats">
      <div class="player-outcome-stat">
        <Footprints :size="16" />
        <span>{{ $t("flows.player.steps") }} {{ slide.step_count }}</span>
      </div>
      <div class="player-outcome-stat">
        <MousePointerClick :size="16" />
        <span>{{ $t("flows.player.choices") }} {{ slide.choices_made }}</span>
      </div>
      <div class="player-outcome-stat">
        <Variable :size="16" />
        <span>{{ $t("flows.player.variables_changed") }} {{ slide.variables_changed }}</span>
      </div>
    </div>

    <div class="player-outcome-actions">
      <Button size="sm" @click="emit('restart')">
        <RotateCcw :size="16" />
        {{ $t("flows.player.play_again") }}
      </Button>
      <Button
        variant="ghost"
        size="sm"
        as="a"
        :href="editorUrl"
        data-phx-link="redirect"
        data-phx-link-state="push"
      >
        <ArrowLeft :size="16" />
        {{ $t("flows.player.back_to_editor") }}
      </Button>
    </div>
  </div>
</template>
