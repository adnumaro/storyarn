<script setup lang="ts">
import { BookOpen, CheckCircle2, Clock3, RefreshCcw, RotateCcw } from "lucide-vue-next";
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { Badge } from "@components/ui/badge";
import { Button } from "@components/ui/button";
import { useLive } from "@shared/composables/useLive";
import {
  isOnboardingGuideKey,
  onboardingGuides,
  onboardingGuideKeys,
  sessionKey,
} from "@components/onboarding/onboardingGuides";

interface TutorialItem {
  key: string;
  state: "inactive" | "pending" | "completed";
}

const { tutorials = [] } = defineProps<{ tutorials?: TutorialItem[] }>();

const { t } = useI18n();
const live = useLive();

const completedCount = computed(
  () => tutorials.filter((tutorial) => tutorial.state === "completed").length,
);

function restart(tutorial: TutorialItem): void {
  if (!isOnboardingGuideKey(tutorial.key)) return;

  window.sessionStorage.removeItem(sessionKey(tutorial.key));
  live.pushEvent("restart_tutorial", { tutorial: tutorial.key });
}

function restartAll(): void {
  for (const tutorial of onboardingGuideKeys) {
    window.sessionStorage.removeItem(sessionKey(tutorial));
  }
  live.pushEvent("restart_all_tutorials", {});
}

function docsUrl(key: string): string {
  return isOnboardingGuideKey(key) ? onboardingGuides[key].docsUrl : "/docs";
}

function stateIcon(state: TutorialItem["state"]) {
  if (state === "completed") return CheckCircle2;
  if (state === "pending") return Clock3;
  return BookOpen;
}
</script>

<template>
  <div class="space-y-8">
    <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
      <div class="space-y-1.5">
        <h1 class="text-2xl font-bold tracking-tight text-foreground">
          {{ t("settings.tutorials.title") }}
        </h1>
        <p class="max-w-2xl text-base text-muted-foreground">
          {{ t("settings.tutorials.subtitle") }}
        </p>
      </div>
      <Button
        data-testid="restart-all-tutorials"
        type="button"
        variant="outline"
        class="shrink-0"
        @click="restartAll"
      >
        <RefreshCcw class="size-4" />
        {{ t("settings.tutorials.restart_all") }}
      </Button>
    </div>

    <div class="rounded-xl border border-border bg-muted/30 p-4 text-sm text-muted-foreground">
      {{ t("settings.tutorials.progress", { completed: completedCount, total: tutorials.length }) }}
    </div>

    <div class="grid gap-3">
      <article
        v-for="tutorial in tutorials"
        :key="tutorial.key"
        class="flex flex-col gap-4 rounded-xl border border-border bg-surface p-4 transition-colors hover:border-primary/30 sm:flex-row sm:items-center"
      >
        <div class="grid size-10 shrink-0 place-items-center rounded-lg bg-primary/10 text-primary">
          <component :is="stateIcon(tutorial.state)" class="size-5" />
        </div>

        <div class="min-w-0 flex-1">
          <div class="flex flex-wrap items-center gap-2">
            <h2 class="font-semibold">{{ t(`onboarding.guides.${tutorial.key}.title`) }}</h2>
            <Badge variant="outline">
              {{ t(`settings.tutorials.states.${tutorial.state}`) }}
            </Badge>
          </div>
          <p class="mt-1 text-sm text-muted-foreground">
            {{ t(`onboarding.guides.${tutorial.key}.summary`) }}
          </p>
        </div>

        <div class="flex shrink-0 items-center gap-2 sm:justify-end">
          <Button as="a" variant="ghost" size="sm" :href="docsUrl(tutorial.key)" target="_blank">
            <BookOpen class="size-4" />
            {{ t("settings.tutorials.read_guide") }}
          </Button>
          <Button
            type="button"
            :data-testid="`restart-tutorial-${tutorial.key}`"
            :aria-label="
              t('settings.tutorials.show_again_for', {
                tutorial: t(`onboarding.guides.${tutorial.key}.title`),
              })
            "
            variant="outline"
            size="sm"
            @click="restart(tutorial)"
          >
            <RotateCcw class="size-4" />
            {{ t("settings.tutorials.show_again") }}
          </Button>
        </div>
      </article>
    </div>
  </div>
</template>
