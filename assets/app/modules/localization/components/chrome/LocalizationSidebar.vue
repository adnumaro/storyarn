<script setup lang="ts">
import { Languages, Plus, RefreshCw, Trash2 } from "lucide-vue-next";
import { computed, ref } from "vue";
import { Button } from "@components/ui/button";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import ConfirmDialog from "@components/ConfirmDialog.vue";
import LanguageFlag from "@components/language/LanguageFlag.vue";
import LanguagePicker from "@components/language/LanguagePicker.vue";
import type { LanguagePickerOption } from "@components/language/types";
import { useLive } from "@shared/composables/useLive.ts";

interface Language {
  id: number;
  localeCode: string;
  name: string;
  flagCode: string | null;
  shortLabel: string;
}

const {
  sourceLanguage = null,
  targetLanguages = [],
  selectedLocale = null,
  canEdit = false,
  sourceLanguageOptions = [],
  addLanguageOptions = [],
  workspaceSlug = "",
  projectSlug = "",
} = defineProps<{
  sourceLanguage?: Language | null;
  targetLanguages?: Language[];
  selectedLocale?: string | null;
  canEdit?: boolean;
  sourceLanguageOptions?: LanguagePickerOption[];
  addLanguageOptions?: LanguagePickerOption[];
  workspaceSlug?: string;
  projectSlug?: string;
}>();

const live = useLive();

const deleteDialogOpen = ref(false);
const pendingDeleteLanguage = ref<Language | null>(null);
const sourceChangeDialogOpen = ref(false);
const pendingSourceLanguage = ref<LanguagePickerOption | null>(null);
const syncing = ref(false);

const selectedSourceOption = computed<LanguagePickerOption | null>(() => {
  if (!sourceLanguage) return null;

  return {
    value: sourceLanguage.localeCode,
    label: sourceLanguage.name,
    languageTag: sourceLanguage.localeCode,
    flagCode: sourceLanguage.flagCode,
    shortLabel: sourceLanguage.shortLabel,
  };
});

function textsUrl(localeCode: string): string {
  return `/workspaces/${workspaceSlug}/projects/${projectSlug}/localization/texts/${localeCode}`;
}

function requestSourceLanguage(option: LanguagePickerOption): void {
  pendingSourceLanguage.value = option;
  sourceChangeDialogOpen.value = true;
}

function confirmSourceLanguage(): void {
  if (pendingSourceLanguage.value) {
    live.pushEvent("change_source_language", {
      locale_code: pendingSourceLanguage.value.value,
      reset_translations: true,
    });
  }
  pendingSourceLanguage.value = null;
}

function addTargetLanguage(option: LanguagePickerOption): void {
  live.pushEvent("add_target_language", { locale_code: option.value });
}

function requestRemove(lang: Language): void {
  pendingDeleteLanguage.value = lang;
  deleteDialogOpen.value = true;
}

function confirmRemove(): void {
  if (pendingDeleteLanguage.value) {
    live.pushEvent("remove_language", { id: pendingDeleteLanguage.value.id });
  }
  pendingDeleteLanguage.value = null;
}

function syncTexts(): void {
  syncing.value = true;
  live.pushEvent("sync_texts", {}, () => {
    syncing.value = false;
  });
}
</script>

<template>
  <div class="space-y-6">
    <!-- Source language -->
    <section v-if="sourceLanguage" class="space-y-2">
      <h2 class="px-2 text-xs font-medium text-muted-foreground">
        {{ $t("localization.sidebar.source_language") }}
      </h2>
      <LanguagePicker
        v-if="canEdit && sourceLanguageOptions.length > 0"
        id="localization-source-language-picker"
        :model-value="sourceLanguage.localeCode"
        :selected-option="selectedSourceOption"
        :options="sourceLanguageOptions"
        :label="$t('localization.sidebar.change_source')"
        :text="{
          searchPlaceholder: $t('localization.sidebar.search_languages'),
          emptyLabel: $t('localization.sidebar.no_matches'),
        }"
        :appearance="{
          triggerVariant: 'outline',
          triggerSize: 'sm',
          triggerClass: 'w-full',
        }"
        @select="requestSourceLanguage"
      />
      <div
        v-else
        class="flex min-h-9 items-center gap-2 rounded-md border border-border px-3 py-1.5 text-sm text-foreground/80"
      >
        <LanguageFlag
          :flag-code="sourceLanguage.flagCode"
          :short-label="sourceLanguage.shortLabel"
        />
        <span class="min-w-0 truncate font-medium">{{ sourceLanguage.name }}</span>
      </div>
    </section>

    <!-- Target languages -->
    <section class="space-y-2">
      <div class="flex items-center justify-between px-2">
        <h2 class="text-xs font-medium text-muted-foreground">
          {{ $t("localization.sidebar.target_languages") }}
        </h2>
        <div class="flex items-center gap-1.5">
          <span v-if="targetLanguages.length > 0" class="text-xs text-muted-foreground">
            {{ targetLanguages.length }}
          </span>
          <ToolbarTooltip
            v-if="canEdit && targetLanguages.length > 0"
            :label="$t('localization.sidebar.sync_title')"
            side="right"
          >
            <Button
              variant="ghost"
              size="icon-xs"
              class="text-muted-foreground hover:text-foreground"
              :disabled="syncing"
              :aria-label="$t('localization.sidebar.sync_title')"
              @click="syncTexts"
            >
              <RefreshCw class="size-3.5" :class="{ 'animate-spin': syncing }" />
              <span class="sr-only">
                {{ syncing ? $t("localization.sidebar.syncing") : $t("localization.sidebar.sync") }}
              </span>
            </Button>
          </ToolbarTooltip>
        </div>
      </div>

      <div
        v-if="targetLanguages.length === 0"
        class="rounded-xl border border-dashed border-border bg-muted/40 p-3 text-sm text-muted-foreground"
      >
        {{ $t("localization.sidebar.no_targets") }}
      </div>

      <div v-else class="space-y-1.5">
        <div
          v-for="lang in targetLanguages"
          :key="lang.id"
          :class="[
            'group flex items-center gap-1 rounded-md pr-1 text-sm transition-colors',
            lang.localeCode === selectedLocale
              ? 'bg-accent text-accent-foreground font-medium'
              : 'text-foreground/80 hover:bg-accent/50',
          ]"
        >
          <a
            :href="textsUrl(lang.localeCode)"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="flex min-w-0 flex-1 items-center gap-2 py-1.5 pl-2 text-left"
          >
            <LanguageFlag
              :flag-code="lang.flagCode"
              :short-label="lang.shortLabel"
              :dimmed="lang.localeCode !== selectedLocale"
            />
            <span class="min-w-0 truncate text-sm font-medium">{{ lang.name }}</span>
          </a>

          <button
            v-if="canEdit"
            type="button"
            class="inline-flex size-5 shrink-0 items-center justify-center rounded text-muted-foreground opacity-0 transition-opacity hover:bg-destructive/10 hover:text-destructive group-hover:opacity-100 focus-visible:opacity-100"
            :title="$t('localization.sidebar.remove_language')"
            @click.stop.prevent="requestRemove(lang)"
          >
            <Trash2 class="size-3" />
          </button>
        </div>
      </div>

      <!-- Add language picker -->
      <div v-if="canEdit">
        <LanguagePicker
          v-if="addLanguageOptions.length > 0"
          id="localization-add-language-picker"
          :options="addLanguageOptions"
          :label="$t('localization.sidebar.add_language')"
          :text="{
            placeholder: $t('localization.sidebar.add_language'),
            searchPlaceholder: $t('localization.sidebar.search_languages'),
            emptyLabel: $t('localization.sidebar.no_matches'),
          }"
          :appearance="{
            triggerVariant: 'ghost',
            triggerSize: 'sm',
            triggerClass: 'w-full justify-between text-xs',
          }"
          @select="addTargetLanguage"
        >
          <template #placeholder-icon><Plus class="size-3.5" /></template>
        </LanguagePicker>
        <div
          v-else
          class="rounded-xl border border-dashed border-border bg-muted/40 px-3 py-2 text-sm text-muted-foreground"
        >
          {{ $t("localization.sidebar.all_added") }}
        </div>
      </div>
    </section>

    <!-- Remove language confirmation -->
    <ConfirmDialog
      v-model:open="deleteDialogOpen"
      :title="$t('localization.sidebar.remove_confirm_title')"
      :description="
        $t('localization.sidebar.remove_confirm_description', {
          name: pendingDeleteLanguage?.name ?? '',
        })
      "
      :confirm-text="$t('localization.sidebar.remove_confirm_button')"
      variant="destructive"
      :icon="Trash2"
      @confirm="confirmRemove"
    />

    <ConfirmDialog
      v-model:open="sourceChangeDialogOpen"
      :title="$t('localization.sidebar.source_change_confirm_title')"
      :description="
        $t('localization.sidebar.source_change_confirm_description', {
          name: pendingSourceLanguage?.label ?? '',
        })
      "
      :confirm-text="$t('localization.sidebar.source_change_confirm_button')"
      variant="destructive"
      :icon="Languages"
      @confirm="confirmSourceLanguage"
    />
  </div>
</template>
