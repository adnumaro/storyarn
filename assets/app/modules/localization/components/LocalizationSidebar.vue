<script setup lang="ts">
import { RefreshCw, Trash2, X } from "lucide-vue-next";
import { ref } from "vue";
import { Button } from "@components/ui/button";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@components/ui/command";
import ConfirmDialog from "@components/ConfirmDialog.vue";
import { useLive } from "@composables/useLive";

interface Language {
  id: number;
  localeCode: string;
  name: string;
  flagUrl: string | null;
  shortLabel: string;
}

interface LanguageOption {
  label: string;
  value: string;
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
  sourceLanguageOptions?: LanguageOption[];
  addLanguageOptions?: LanguageOption[];
  workspaceSlug?: string;
  projectSlug?: string;
}>();

const live = useLive();

const sourcePickerOpen = ref(false);
const addPickerOpen = ref(false);
const deleteDialogOpen = ref(false);
const pendingDeleteLanguage = ref<Language | null>(null);
const syncing = ref(false);

function textsUrl(localeCode: string): string {
  return `/workspaces/${workspaceSlug}/projects/${projectSlug}/localization/texts/${localeCode}`;
}

function changeSourceLanguage(localeCode: string): void {
  sourcePickerOpen.value = false;
  live.pushEvent("change_source_language", { locale_code: localeCode });
}

function addTargetLanguage(localeCode: string): void {
  addPickerOpen.value = false;
  live.pushEvent("add_target_language", { locale_code: localeCode });
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
      <p class="px-1 text-[11px] font-semibold uppercase tracking-[0.18em] text-muted-foreground">
        {{ $t("localization.sidebar.source_language") }}
      </p>
      <div class="flex items-center gap-3 rounded-xl border border-primary/30 bg-primary/10 p-2">
        <img
          v-if="sourceLanguage.flagUrl"
          :src="sourceLanguage.flagUrl"
          alt=""
          class="size-5 shrink-0 rounded-full object-cover"
        />
        <span
          v-else
          class="inline-flex min-w-[1.75rem] shrink-0 items-center justify-center text-[0.72rem] font-semibold uppercase leading-none tracking-[0.08em]"
        >
          {{ sourceLanguage.shortLabel }}
        </span>
        <span class="min-w-0 truncate text-sm font-medium">{{ sourceLanguage.name }}</span>
      </div>

      <!-- Change source language picker -->
      <div v-if="canEdit && sourceLanguageOptions.length > 0" class="relative">
        <Button
          variant="outline"
          size="sm"
          class="w-full justify-between font-normal"
          @click="sourcePickerOpen = !sourcePickerOpen"
        >
          <span class="text-muted-foreground">{{ $t("localization.sidebar.change_source") }}</span>
        </Button>
        <div
          v-if="sourcePickerOpen"
          class="absolute left-0 right-0 top-full z-50 mt-1 rounded-md border bg-popover shadow-md"
        >
          <Command>
            <CommandInput :placeholder="$t('localization.sidebar.search_languages')" />
            <CommandList>
              <CommandEmpty>{{ $t("localization.sidebar.no_matches") }}</CommandEmpty>
              <CommandGroup>
                <CommandItem
                  v-for="opt in sourceLanguageOptions"
                  :key="opt.value"
                  :value="opt.label"
                  @select="changeSourceLanguage(opt.value)"
                >
                  {{ opt.label }}
                </CommandItem>
              </CommandGroup>
            </CommandList>
          </Command>
        </div>
      </div>
    </section>

    <!-- Target languages -->
    <section class="space-y-2">
      <div class="flex items-center justify-between px-1">
        <p class="text-[11px] font-semibold uppercase tracking-[0.18em] text-muted-foreground">
          {{ $t("localization.sidebar.target_languages") }}
        </p>
        <span v-if="targetLanguages.length > 0" class="text-xs text-muted-foreground">
          {{ targetLanguages.length }}
        </span>
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
            'flex items-center gap-2 rounded-xl border p-2 transition-colors',
            lang.localeCode === selectedLocale
              ? 'border-primary/30 bg-primary/10'
              : 'border-border bg-background hover:bg-accent/50',
          ]"
        >
          <a
            :href="textsUrl(lang.localeCode)"
            data-phx-link="patch"
            data-phx-link-state="push"
            class="flex min-w-0 flex-1 items-center gap-3 text-left"
          >
            <img
              v-if="lang.flagUrl"
              :src="lang.flagUrl"
              alt=""
              :class="[
                'size-5 shrink-0 rounded-full object-cover',
                lang.localeCode !== selectedLocale && 'opacity-90',
              ]"
            />
            <span
              v-else
              class="inline-flex min-w-[1.75rem] shrink-0 items-center justify-center text-[0.72rem] font-semibold uppercase leading-none tracking-[0.08em]"
            >
              {{ lang.shortLabel }}
            </span>
            <span class="min-w-0 truncate text-sm font-medium">{{ lang.name }}</span>
          </a>

          <button
            v-if="canEdit"
            type="button"
            class="inline-flex items-center justify-center size-6 rounded-md text-muted-foreground hover:text-destructive hover:bg-accent transition-colors"
            :title="$t('localization.sidebar.remove_language')"
            @click="requestRemove(lang)"
          >
            <X class="size-3.5" />
          </button>
        </div>
      </div>

      <!-- Add language picker -->
      <div v-if="canEdit">
        <div v-if="addLanguageOptions.length > 0" class="relative">
          <Button
            variant="outline"
            size="sm"
            class="w-full justify-between font-normal"
            @click="addPickerOpen = !addPickerOpen"
          >
            <span class="text-muted-foreground">{{ $t("localization.sidebar.add_language") }}</span>
          </Button>
          <div
            v-if="addPickerOpen"
            class="absolute left-0 right-0 top-full z-50 mt-1 rounded-md border bg-popover shadow-md"
          >
            <Command>
              <CommandInput :placeholder="$t('localization.sidebar.search_languages')" />
              <CommandList>
                <CommandEmpty>{{ $t("localization.sidebar.no_matches") }}</CommandEmpty>
                <CommandGroup>
                  <CommandItem
                    v-for="opt in addLanguageOptions"
                    :key="opt.value"
                    :value="opt.label"
                    @select="addTargetLanguage(opt.value)"
                  >
                    {{ opt.label }}
                  </CommandItem>
                </CommandGroup>
              </CommandList>
            </Command>
          </div>
        </div>
        <div
          v-else
          class="rounded-xl border border-dashed border-border bg-muted/40 px-3 py-2 text-sm text-muted-foreground"
        >
          {{ $t("localization.sidebar.all_added") }}
        </div>
      </div>

      <!-- Sync button -->
      <Button
        v-if="canEdit && targetLanguages.length > 0"
        variant="ghost"
        size="sm"
        class="w-full justify-start gap-2"
        :disabled="syncing"
        :title="$t('localization.sidebar.sync_title')"
        @click="syncTexts"
      >
        <RefreshCw class="size-4" :class="{ 'animate-spin': syncing }" />
        {{ syncing ? $t("localization.sidebar.syncing") : $t("localization.sidebar.sync") }}
      </Button>
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
  </div>
</template>
