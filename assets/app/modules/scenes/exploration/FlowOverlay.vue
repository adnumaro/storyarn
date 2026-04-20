<script setup lang="ts">
import { ChevronRight, CornerDownLeft, MapIcon } from "lucide-vue-next";
import { computed } from "vue";
import { useLive } from "@composables/useLive";
import type { FlowSlide } from "./composables/useExplorationKeyboard";

const {
  slide = null,
  flowName = null,
  showContinue = false,
} = defineProps<{
  slide?: FlowSlide | null;
  flowName?: string | null;
  showContinue?: boolean;
}>();

const live = useLive();

const slideType = computed(() => slide?.type);
const visibleResponses = computed(() => (slide?.responses || []).filter((r) => r.valid));

function flowContinue() {
  live.pushEvent("flow_continue", {});
}

function chooseResponse(id: number | string) {
  live.pushEvent("choose_response", { id });
}

function goBack() {
  live.pushEvent("go_back", {});
}

function flowFinish() {
  live.pushEvent("flow_finish", {});
}
</script>

<template>
  <div
    class="absolute bottom-0 inset-x-0 z-30 border-t border-border bg-background/95 backdrop-blur-sm"
  >
    <div class="px-5 py-4 max-w-4xl mx-auto">
      <!-- Dialogue -->
      <template v-if="slideType === 'dialogue' && slide">
        <div class="flex gap-4">
          <div class="shrink-0">
            <img
              v-if="slide.speakerAvatarUrl"
              :src="slide.speakerAvatarUrl"
              :alt="slide.speakerName || ''"
              class="size-14 rounded object-cover border border-border"
            />
            <div
              v-else-if="slide.speakerInitials"
              class="size-14 rounded flex items-center justify-center text-base font-bold text-white border border-border"
              :style="{ backgroundColor: slide.speakerColor || '#6b7280' }"
            >
              {{ slide.speakerInitials }}
            </div>
          </div>

          <div class="flex-1 min-w-0">
            <div v-if="slide.speakerName" class="text-sm font-semibold text-primary mb-1">
              {{ slide.speakerName }}
            </div>
            <div
              class="text-sm leading-relaxed text-foreground [&_p]:mb-1 [&_p:last-child]:mb-0"
              v-html="slide.text"
            />
            <div
              v-if="slide.stageDirections"
              class="mt-1.5 text-xs italic text-muted-foreground border-l-2 border-border pl-2"
            >
              {{ slide.stageDirections }}
            </div>

            <div v-if="visibleResponses.length > 0" class="mt-3 space-y-1">
              <button
                v-for="resp in visibleResponses"
                :key="resp.id"
                class="flex items-center gap-2 text-sm text-foreground/80 hover:text-primary transition-colors"
                @click="chooseResponse(resp.id)"
              >
                <span class="text-xs font-bold text-primary/70">{{ resp.number }}.</span>
                <span>{{ resp.text }}</span>
              </button>
            </div>
          </div>
        </div>
      </template>

      <!-- Outcome -->
      <template v-else-if="slideType === 'outcome' && slide">
        <div v-if="slide.text" class="text-sm text-foreground" v-html="slide.text" />
      </template>

      <!-- Actions -->
      <div class="flex items-center justify-between mt-3 pt-2 border-t border-border">
        <button
          class="flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground transition-colors"
          @click="goBack"
        >
          <CornerDownLeft class="size-3" />
          {{ $t("scenes.exploration.back") }}
        </button>

        <button
          v-if="showContinue && visibleResponses.length === 0"
          class="flex items-center gap-1 text-sm font-medium text-primary hover:text-primary/80 transition-colors"
          @click="flowContinue"
        >
          {{ $t("scenes.exploration.continue") }}
          <ChevronRight class="size-4" />
        </button>
        <button
          v-else-if="slideType === 'outcome'"
          class="flex items-center gap-1 text-sm font-medium text-primary hover:text-primary/80 transition-colors"
          @click="flowFinish"
        >
          <MapIcon class="size-3.5" />
          {{ $t("scenes.exploration.return_to_map") }}
        </button>
      </div>
    </div>
  </div>
</template>
