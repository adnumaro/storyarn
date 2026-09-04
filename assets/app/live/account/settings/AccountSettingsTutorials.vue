<script setup lang="ts">
import { BookOpen, CircleCheck, Clock3, RefreshCcw, RotateCcw } from "@lucide/vue";
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { SettingsPage, SettingsRow, SettingsSection } from "@components/settings";
import { Button } from "@components/ui/button";
import { useLive } from "@shared/composables/useLive";
import {
  isOnboardingGuideKey,
  localizedPublicUrl,
  onboardingGuides,
  onboardingGuideKeys,
  sessionKey,
} from "@components/onboarding/onboardingGuides";

interface TutorialItem {
  key: string;
  state: "pending" | "completed";
}

const { tutorials = [] } = defineProps<{ tutorials?: TutorialItem[] }>();

const { locale, t } = useI18n();
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
  const path = isOnboardingGuideKey(key) ? onboardingGuides[key].docsUrl : "/docs";
  return localizedPublicUrl(path, locale.value);
}
</script>

<template>
  <SettingsPage :title="t('settings.tutorials.title')">
    <template #actions>
      <Button
        data-testid="restart-all-tutorials"
        type="button"
        variant="outline"
        size="sm"
        @click="restartAll"
      >
        <RefreshCcw class="size-4" />
        {{ t("settings.tutorials.restart_all") }}
      </Button>
    </template>

    <SettingsSection
      :title="t('settings.tutorials.guides')"
      :hint="
        t('settings.tutorials.progress', { completed: completedCount, total: tutorials.length })
      "
    >
      <SettingsRow
        v-for="tutorial in tutorials"
        :key="tutorial.key"
        :label="t(`onboarding.guides.${tutorial.key}.title`)"
        :hint="t(`onboarding.guides.${tutorial.key}.summary`)"
      >
        <template #leading>
          <CircleCheck
            v-if="tutorial.state === 'completed'"
            class="size-[18px] shrink-0 text-primary"
            :aria-label="t('settings.tutorials.states.completed')"
          />
          <Clock3
            v-else
            class="size-[18px] shrink-0 text-muted-foreground"
            :aria-label="t('settings.tutorials.states.pending')"
          />
        </template>

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
      </SettingsRow>
    </SettingsSection>
  </SettingsPage>
</template>
