<script setup lang="ts">
import { computed, onMounted, ref, watch } from "vue";
import { ArrowLeft, ArrowRight, BookOpen, Check, PackageCheck, Sparkles } from "lucide-vue-next";
import { useI18n } from "vue-i18n";
import { Button } from "@components/ui/button";
import { Checkbox } from "@components/ui/checkbox";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog";
import { useLive } from "@shared/composables/useLive";
import {
  isOnboardingGuideKey,
  onboardingGuides,
  sessionKey,
  type OnboardingGuideKey,
} from "./onboardingGuides";

const { guideKey, autoShow = false } = defineProps<{
  guideKey: string;
  autoShow?: boolean;
}>();

const { t } = useI18n();
const live = useLive();
const open = ref(false);
const step = ref(0);
const dontShowAgain = ref(false);
const openSource = ref<"auto" | "manual">("manual");
const closingIntentionally = ref(false);

const guide = computed(() => (isOnboardingGuideKey(guideKey) ? onboardingGuides[guideKey] : null));
const typedGuideKey = computed<OnboardingGuideKey | null>(() =>
  isOnboardingGuideKey(guideKey) ? guideKey : null,
);
const slideKey = computed(() => guide.value?.slides[step.value] ?? "");
const lastStep = computed(() => step.value === (guide.value?.slides.length ?? 1) - 1);
const titleKey = computed(() => `onboarding.guides.${guideKey}.title`);
const summaryKey = computed(() => `onboarding.guides.${guideKey}.summary`);
const slideTitleKey = computed(
  () => `onboarding.guides.${guideKey}.slides.${slideKey.value}.title`,
);
const slideDescriptionKey = computed(
  () => `onboarding.guides.${guideKey}.slides.${slideKey.value}.description`,
);

function tutorialSnoozed(guideKey: OnboardingGuideKey): boolean {
  try {
    return Boolean(window.sessionStorage.getItem(sessionKey(guideKey)));
  } catch {
    return false;
  }
}

function markTutorialSnoozed(guideKey: OnboardingGuideKey): void {
  try {
    window.sessionStorage.setItem(sessionKey(guideKey), "1");
  } catch {
    // Session storage is an optional convenience and must never block the tutorial flow.
  }
}

function track(action: "opened" | "snoozed" | "finished" | "docs_opened"): void {
  if (!typedGuideKey.value) return;

  live.pushEvent("onboarding_tutorial_interaction", {
    tutorial: typedGuideKey.value,
    action,
    source: openSource.value,
  });
}

function show(source: "auto" | "manual"): void {
  if (!guide.value) return;

  step.value = 0;
  dontShowAgain.value = false;
  openSource.value = source;
  open.value = true;
  track("opened");
}

function openTutorial(): void {
  show("manual");
}

function dismiss(action: "snoozed" | "finished"): void {
  if (!typedGuideKey.value) return;

  markTutorialSnoozed(typedGuideKey.value);

  if (dontShowAgain.value) {
    live.pushEvent("complete_onboarding_tutorial", {
      tutorial: typedGuideKey.value,
      source: openSource.value,
    });
  } else {
    track(action);
  }

  closeIntentionally();
}

function snooze(): void {
  dismiss("snoozed");
}

function finish(): void {
  dismiss("finished");
}

function closeIntentionally(): void {
  closingIntentionally.value = true;
  open.value = false;
  window.setTimeout(() => {
    closingIntentionally.value = false;
  }, 0);
}

function handleOpenChange(value: boolean): void {
  if (value) {
    open.value = true;
    return;
  }

  if (closingIntentionally.value) {
    open.value = false;
    return;
  }

  snooze();
}

function previousStep(): void {
  step.value = Math.max(0, step.value - 1);
}

function nextStep(): void {
  step.value = Math.min((guide.value?.slides.length ?? 1) - 1, step.value + 1);
}

function maybeAutoShow(): void {
  if (!autoShow || !typedGuideKey.value) return;
  if (tutorialSnoozed(typedGuideKey.value)) return;

  show("auto");
}

onMounted(maybeAutoShow);
watch([typedGuideKey, () => autoShow], maybeAutoShow);

defineExpose({ openTutorial });
</script>

<template>
  <Dialog :open="open" @update:open="handleOpenChange">
    <DialogContent
      v-if="guide"
      :show-close-button="true"
      class="max-h-[calc(100dvh-2rem)] gap-0 overflow-y-auto border-border/80 p-0 sm:max-w-2xl"
    >
      <div class="relative overflow-hidden border-b border-border/70 bg-muted/40">
        <img
          v-if="guide.imageUrl"
          :src="guide.imageUrl"
          alt=""
          class="h-52 w-full object-cover object-top sm:h-64"
        />
        <div
          v-else
          class="flex h-52 items-center justify-center bg-linear-to-br from-primary/20 via-background to-secondary/30 sm:h-64"
        >
          <div
            class="relative grid size-28 place-items-center rounded-3xl border border-primary/20 bg-background/80 shadow-2xl backdrop-blur"
          >
            <div
              class="absolute -right-3 -top-3 grid size-10 place-items-center rounded-full bg-primary text-primary-foreground shadow-lg"
            >
              <Check class="size-5" />
            </div>
            <PackageCheck class="size-14 text-primary" />
          </div>
        </div>
        <div
          class="absolute inset-x-0 bottom-0 h-24 bg-linear-to-t from-background/90 to-transparent"
        />
        <div
          class="absolute bottom-4 left-5 flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.18em] text-foreground/70"
        >
          <Sparkles class="size-4 text-primary" />
          {{ t("onboarding.common.contextual_guide") }}
        </div>
      </div>

      <div class="space-y-5 p-5 sm:p-6">
        <DialogHeader class="space-y-2 text-left">
          <DialogTitle class="text-xl sm:text-2xl">{{ t(titleKey) }}</DialogTitle>
          <DialogDescription class="text-sm leading-relaxed">
            {{ t(summaryKey) }}
          </DialogDescription>
        </DialogHeader>

        <section class="min-h-28 rounded-xl border border-border/70 bg-surface p-4">
          <p class="mb-2 text-xs font-semibold uppercase tracking-wider text-primary">
            {{ t("onboarding.common.step", { current: step + 1, total: guide.slides.length }) }}
          </p>
          <h3 class="text-base font-semibold text-foreground">{{ t(slideTitleKey) }}</h3>
          <p class="mt-2 text-sm leading-relaxed text-muted-foreground">
            {{ t(slideDescriptionKey) }}
          </p>
        </section>

        <div class="flex gap-1.5" aria-hidden="true">
          <span
            v-for="(_, index) in guide.slides"
            :key="index"
            :class="[
              'h-1 flex-1 rounded-full transition-colors duration-200',
              index <= step ? 'bg-primary' : 'bg-muted',
            ]"
          />
        </div>

        <div class="flex items-start gap-3 rounded-xl border border-border/70 bg-muted/30 p-3">
          <Checkbox
            id="onboarding-dont-show-again"
            v-model="dontShowAgain"
            data-testid="onboarding-dont-show-again"
            class="mt-0.5"
          />
          <div class="space-y-0.5">
            <label
              for="onboarding-dont-show-again"
              class="cursor-pointer text-sm font-medium leading-none text-foreground"
            >
              {{ t("onboarding.common.dont_show_again") }}
            </label>
            <p class="text-xs leading-relaxed text-muted-foreground">
              {{ t("onboarding.common.dont_show_again_hint") }}
            </p>
          </div>
        </div>

        <div class="flex flex-col-reverse gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div class="flex items-center gap-1">
            <Button
              data-testid="onboarding-not-now"
              type="button"
              variant="ghost"
              size="sm"
              @click="snooze"
            >
              {{ t("onboarding.common.not_now") }}
            </Button>
            <Button
              as="a"
              type="button"
              variant="ghost"
              size="sm"
              :href="guide.docsUrl"
              target="_blank"
              rel="noreferrer"
              data-testid="onboarding-full-guide"
              @click="track('docs_opened')"
            >
              <BookOpen class="size-4" />
              {{ t("onboarding.common.full_guide") }}
            </Button>
          </div>

          <div class="flex items-center justify-end gap-2">
            <Button
              v-if="step > 0"
              data-testid="onboarding-back"
              type="button"
              variant="outline"
              size="sm"
              @click="previousStep"
            >
              <ArrowLeft class="size-4" />
              {{ t("onboarding.common.back") }}
            </Button>
            <Button
              v-if="!lastStep"
              data-testid="onboarding-next"
              type="button"
              size="sm"
              @click="nextStep"
            >
              {{ t("onboarding.common.next") }}
              <ArrowRight class="size-4" />
            </Button>
            <Button v-else data-testid="onboarding-finish" type="button" size="sm" @click="finish">
              <Check class="size-4" />
              {{ t("onboarding.common.got_it") }}
            </Button>
          </div>
        </div>
      </div>
    </DialogContent>
  </Dialog>
</template>
