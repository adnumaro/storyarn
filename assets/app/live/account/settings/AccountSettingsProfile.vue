<script setup lang="ts">
import { useLiveForm, type Form } from "live_vue";
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
import { Label } from "@components/ui/label";
import {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select";

interface ProfileFormValues {
  display_name: string;
  locale: string | null;
}

const { profileForm: profileFormProp } = defineProps<{
  profileForm: Form<ProfileFormValues>;
}>();

const { availableLocales, locale: currentLocale, t } = useI18n({ useScope: "global" });

const localeOptions = computed(() =>
  availableLocales.map((value) => ({
    value,
    label: t(`settings.profile.languages.${value}`),
  })),
);

const fallbackLocale = computed(() =>
  localeOptions.value.some((option) => option.value === currentLocale.value)
    ? currentLocale.value
    : (localeOptions.value[0]?.value ?? "en"),
);

function normalizeLocale(value: string | null | undefined): string {
  return localeOptions.value.some((option) => option.value === value)
    ? (value as string)
    : fallbackLocale.value;
}

function prepareProfileData(data: ProfileFormValues): ProfileFormValues {
  return { ...data, locale: normalizeLocale(data.locale) };
}

const profileForm = useLiveForm(() => profileFormProp, {
  changeEvent: "validate_profile",
  submitEvent: "update_profile",
  debounceInMiliseconds: 300,
  prepareData: prepareProfileData,
});

const displayName = profileForm.field("display_name");
const locale = profileForm.field("locale");

const displayNameValue = computed({
  get: () => displayName.value.value ?? "",
  set: (value: string) => {
    displayName.value.value = value;
  },
});

const displayNameInputAttrs = computed(() => {
  const { value: _value, onInput: _onInput, ...attrs } = displayName.inputAttrs.value;
  return attrs;
});

function updateDisplayName(value: string | number): void {
  displayNameValue.value = String(value);
}

const selectedLocale = computed({
  get: () => normalizeLocale(locale.value.value),
  set: (value: string) => {
    locale.value.value = normalizeLocale(value);
  },
});

function updateLocale(value: string | string[]): void {
  const nextValue = Array.isArray(value) ? value[0] : value;
  selectedLocale.value = normalizeLocale(nextValue);
}
</script>

<template>
  <div class="space-y-8">
    <div class="space-y-1.5">
      <h1 class="text-2xl font-bold tracking-tight text-foreground">
        {{ $t("settings.profile.title") }}
      </h1>
      <p class="text-base text-muted-foreground">
        {{ $t("settings.profile.subtitle") }}
      </p>
    </div>

    <!-- Profile Section -->
    <section>
      <h3 class="text-lg font-semibold mb-4">{{ $t("settings.profile.personal_info") }}</h3>

      <div class="space-y-4">
        <div class="space-y-1.5">
          <Label for="profile-display-name">{{ $t("settings.profile.display_name") }}</Label>
          <Input
            v-bind="displayNameInputAttrs"
            id="profile-display-name"
            :model-value="displayNameValue"
            :placeholder="$t('settings.profile.display_name_placeholder')"
            @update:model-value="updateDisplayName"
          />
          <p v-if="displayName.errorMessage.value" class="text-sm text-destructive mt-1">
            {{ displayName.errorMessage.value }}
          </p>
        </div>

        <div class="space-y-1.5">
          <Label for="profile-locale">{{ $t("settings.profile.language") }}</Label>
          <Select
            :model-value="selectedLocale"
            :name="locale.inputAttrs.value.name"
            @update:model-value="updateLocale"
          >
            <SelectTrigger id="profile-locale" class="w-full">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectGroup>
                <SelectItem
                  v-for="option in localeOptions"
                  :key="option.value"
                  :value="option.value"
                >
                  {{ option.label }}
                </SelectItem>
              </SelectGroup>
            </SelectContent>
          </Select>
          <p v-if="locale.errorMessage.value" class="text-sm text-destructive mt-1">
            {{ locale.errorMessage.value }}
          </p>
        </div>

        <div class="flex justify-end gap-3">
          <Button @click="profileForm.submit()"> {{ $t("settings.profile.save_profile") }} </Button>
        </div>
      </div>
    </section>
  </div>
</template>
