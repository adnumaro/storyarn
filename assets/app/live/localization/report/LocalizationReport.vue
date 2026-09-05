<script setup lang="ts">
import { computed, ref } from "vue";
import type { LanguagePickerOption } from "@components/language/types";
import { Tabs, TabsList, TabsTrigger } from "@components/ui/tabs";
import ContentCard from "@modules/localization/components/overview/ContentCard.vue";
import EmptyOverview from "@modules/localization/components/overview/EmptyOverview.vue";
import LanguageCard from "@modules/localization/components/overview/LanguageCard.vue";
import SpeakerTable from "@modules/localization/components/overview/SpeakerTable.vue";
import VoiceOverCard from "@modules/localization/components/overview/VoiceOverCard.vue";
import StatusLegend from "@modules/localization/components/progress/StatusLegend.vue";
import type {
  LanguageProgress,
  SourceLanguage,
  SpeakerStat,
  VoProgress,
} from "@modules/localization/domain/types";
import { useLive } from "@shared/composables/useLive.ts";

interface Capabilities {
  canEdit: boolean;
  hasProvider: boolean;
}

/** What the empty overview needs to add the first language in place. */
interface EmptyState {
  addLanguageOptions: LanguagePickerOption[];
  runtimeWordCount: number | null;
  settingsUrl: string;
}

const {
  projectName = "",
  sourceLanguage = null,
  languageProgress = [],
  targetLanguages = [],
  selectedLocale = null,
  speakerStats = [],
  voProgress = { none: 0, needed: 0, recorded: 0, approved: 0 },
  typeCounts = {},
  capabilities = { canEdit: false, hasProvider: false },
  emptyState = { addLanguageOptions: [], runtimeWordCount: null, settingsUrl: "" },
} = defineProps<{
  projectName?: string;
  sourceLanguage?: SourceLanguage | null;
  languageProgress?: LanguageProgress[];
  targetLanguages?: LanguagePickerOption[];
  selectedLocale?: string | null;
  speakerStats?: SpeakerStat[];
  voProgress?: VoProgress;
  typeCounts?: Record<string, number>;
  capabilities?: Capabilities;
  emptyState?: EmptyState;
}>();

const live = useLive();
const adding = ref(false);

const sourceName = computed(() => sourceLanguage?.name ?? "");
const hasLanguages = computed(() => languageProgress.length > 0);
const canEdit = computed(() => capabilities.canEdit);
const hasProvider = computed(() => capabilities.hasProvider);

const selectedLanguage = computed(
  () => languageProgress.find((language) => language.localeCode === selectedLocale) ?? null,
);

function changeLocale(value: string | number): void {
  const locale = String(value);
  if (locale && locale !== selectedLocale) live.pushEvent("change_locale", { locale });
}

function addLanguage(localeCode: string): void {
  adding.value = true;
  live.pushEvent(
    "add_target_language",
    { locale_code: localeCode },
    () => {
      adding.value = false;
    },
    () => {
      adding.value = false;
    },
  );
}
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1040px] flex-col gap-7 py-2">
    <header class="min-w-0">
      <h1 class="text-2xl leading-tight font-semibold tracking-[-0.01em]">
        {{ $t("localization.overview.title") }}
      </h1>
      <p class="mt-1.5 text-sm text-pretty text-muted-foreground">
        {{ $t("localization.overview.description", { project: projectName, source: sourceName }) }}
      </p>
    </header>

    <EmptyOverview
      v-if="!hasLanguages"
      :source-name="sourceName"
      :runtime-word-count="emptyState.runtimeWordCount"
      :can-edit="canEdit"
      :has-provider="hasProvider"
      :add-language-options="emptyState.addLanguageOptions"
      :settings-url="emptyState.settingsUrl"
      :adding="adding"
      @add="addLanguage"
    />

    <template v-else>
      <section class="flex flex-col gap-3">
        <div class="flex flex-wrap items-baseline justify-between gap-2">
          <h2 class="text-[15px] font-medium">{{ $t("localization.overview.languages") }}</h2>
          <StatusLegend />
        </div>
        <div class="grid grid-cols-1 gap-3.5 lg:grid-cols-2">
          <LanguageCard
            v-for="language in languageProgress"
            :key="language.localeCode"
            :language="language"
          />
        </div>
      </section>

      <section class="flex flex-col gap-3.5">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h2 class="text-[15px] font-medium">{{ $t("localization.overview.detail") }}</h2>
          <Tabs :model-value="selectedLocale ?? undefined" @update:model-value="changeLocale">
            <TabsList
              class="h-auto flex-wrap justify-start"
              :aria-label="$t('localization.overview.language_tabs')"
            >
              <TabsTrigger
                v-for="language in targetLanguages"
                :key="language.value"
                :value="language.value"
                class="flex-none"
              >
                {{ language.label }}
              </TabsTrigger>
            </TabsList>
          </Tabs>
        </div>

        <div
          v-if="selectedLanguage"
          class="grid grid-cols-1 items-start gap-3.5 lg:grid-cols-[minmax(0,1.3fr)_minmax(0,1fr)]"
        >
          <SpeakerTable :speakers="speakerStats" :workbench-base="selectedLanguage.workbenchUrl" />
          <div class="flex flex-col gap-3.5">
            <VoiceOverCard
              :vo-progress="voProgress"
              :workbench-base="selectedLanguage.workbenchUrl"
            />
            <ContentCard
              :type-counts="typeCounts"
              :workbench-base="selectedLanguage.workbenchUrl"
            />
          </div>
        </div>
      </section>
    </template>
  </div>
</template>
