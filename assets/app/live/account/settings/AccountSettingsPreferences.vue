<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from "vue";
import { useI18n } from "vue-i18n";
import LanguagePicker from "@components/language/LanguagePicker.vue";
import type { LanguagePickerOption } from "@components/language/types";
import SaveIndicator from "@components/SaveIndicator.vue";
import { SettingsPage, SettingsRow, SettingsSection } from "@components/settings";
import { ToggleGroup, ToggleGroupItem } from "@components/ui/toggle-group";
import { useLive } from "@shared/composables/useLive";

type ThemePreference = "system" | "light" | "dark";

const {
  locale: localeProp,
  localeOptions: localeOptionsProp = [],
  saveStatus = "idle",
} = defineProps<{
  locale: string;
  localeOptions?: LanguagePickerOption[];
  saveStatus?: "idle" | "saving" | "saved";
}>();

const { availableLocales, t } = useI18n({ useScope: "global" });
const live = useLive();

function fallbackFlagCode(locale: string): string | null {
  if (locale === "en") return "gb";
  if (locale === "es") return "es";
  return null;
}

const localeOptions = computed<LanguagePickerOption[]>(() => {
  const metadata = new Map(localeOptionsProp.map((option) => [option.value, option]));

  return availableLocales.map((value) => {
    const option = metadata.get(value);

    return {
      value,
      label: t(`settings.profile.languages.${value}`),
      languageTag: option?.languageTag ?? value.replace("_", "-"),
      flagCode: option?.flagCode ?? fallbackFlagCode(value),
      shortLabel: option?.shortLabel ?? value.slice(0, 2).toUpperCase(),
    };
  });
});

const selectedLocale = computed({
  get: () =>
    localeOptions.value.some((option) => option.value === localeProp)
      ? localeProp
      : (localeOptions.value[0]?.value ?? "en"),
  set: (value: string) => {
    if (value === localeProp) return;
    live.pushEvent("update_locale", { locale: value });
  },
});

const themes: ThemePreference[] = ["system", "light", "dark"];
const currentTheme = ref<ThemePreference>("system");

function readTheme(): ThemePreference {
  const value = localStorage.getItem("phx:theme");
  if (value === "light" || value === "dark") return value;
  return "system";
}

function syncTheme(): void {
  currentTheme.value = readTheme();
}

// A single toggle group reports `undefined` when the active item is clicked
// again; the theme is never "none", so that click keeps the current value.
function setTheme(value: string | string[] | undefined): void {
  if (typeof value !== "string" || !themes.includes(value as ThemePreference)) return;

  const theme = value as ThemePreference;
  if (theme === "system") {
    localStorage.removeItem("phx:theme");
  } else {
    localStorage.setItem("phx:theme", theme);
  }

  currentTheme.value = theme;
  window.dispatchEvent(new CustomEvent("phx:set-theme"));
}

onMounted(() => {
  syncTheme();
  window.addEventListener("storage", syncTheme);
  window.addEventListener("phx:set-theme", syncTheme);
});

onUnmounted(() => {
  window.removeEventListener("storage", syncTheme);
  window.removeEventListener("phx:set-theme", syncTheme);
});
</script>

<template>
  <SettingsPage :title="t('settings.preferences.title')">
    <template #actions>
      <SaveIndicator :status="saveStatus" />
    </template>

    <SettingsSection :title="t('settings.preferences.general')">
      <SettingsRow
        :label="t('settings.preferences.language')"
        :hint="t('settings.preferences.language_hint')"
      >
        <LanguagePicker
          id="preferences-locale"
          v-model="selectedLocale"
          :options="localeOptions"
          :label="t('settings.preferences.language')"
          :appearance="{ searchable: false, triggerClass: 'w-40' }"
        />
      </SettingsRow>
    </SettingsSection>

    <SettingsSection :title="t('settings.preferences.appearance')">
      <SettingsRow
        :label="t('settings.preferences.theme')"
        :hint="t('settings.preferences.theme_hint')"
      >
        <ToggleGroup
          type="single"
          variant="outline"
          size="sm"
          :model-value="currentTheme"
          :aria-label="t('settings.preferences.theme')"
          @update:model-value="setTheme"
        >
          <ToggleGroupItem
            v-for="theme in themes"
            :key="theme"
            :value="theme"
            :data-testid="`preferences-theme-${theme}`"
          >
            {{ t(`settings.preferences.themes.${theme}`) }}
          </ToggleGroupItem>
        </ToggleGroup>
      </SettingsRow>
    </SettingsSection>
  </SettingsPage>
</template>
