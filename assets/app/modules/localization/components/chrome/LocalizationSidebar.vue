<script setup lang="ts">
import { Languages, Plus, RefreshCw, Trash2 } from "lucide-vue-next";
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
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import ConfirmDialog from "@components/ConfirmDialog.vue";
import { flagIconUrl } from "@modules/localization/lib/flag-icons.ts";
import { useLive } from "@shared/composables/useLive.ts";

interface Language {
  id: number;
  localeCode: string;
  name: string;
  flagCode: string | null;
  shortLabel: string;
}

interface LanguageOption {
  label: string;
  value: string;
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
const sourceChangeDialogOpen = ref(false);
const pendingSourceLanguage = ref<LanguageOption | null>(null);
const syncing = ref(false);

function textsUrl(localeCode: string): string {
  return `/workspaces/${workspaceSlug}/projects/${projectSlug}/localization/texts/${localeCode}`;
}

function requestSourceLanguage(option: LanguageOption): void {
  sourcePickerOpen.value = false;
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

function flagClasses(dimmed = false): string[] {
  return ["size-5", "shrink-0", "rounded-full", "object-cover", dimmed ? "opacity-90" : ""];
}

function flagUrl(flagCode: string | null): string | null {
  return flagIconUrl(flagCode);
}
</script>

<template>
  <div class="space-y-6">
    <!-- Source language -->
    <section v-if="sourceLanguage" class="space-y-2">
      <h2 class="px-2 text-xs font-medium text-muted-foreground">
        {{ $t("localization.sidebar.source_language") }}
      </h2>
      <div class="flex items-center gap-2 rounded-md px-2 py-1.5 text-sm text-foreground/80">
        <img
          v-if="flagIconUrl(sourceLanguage.flagCode)"
          :src="flagIconUrl(sourceLanguage.flagCode) || ''"
          alt=""
          aria-hidden="true"
          :class="flagClasses()"
        />
        <span
          v-else
          class="inline-flex min-w-7 shrink-0 items-center justify-center text-[0.72rem] font-semibold uppercase leading-none tracking-[0.08em]"
        >
          {{ sourceLanguage.shortLabel }}
        </span>
        <span class="min-w-0 truncate text-sm font-medium">{{ sourceLanguage.name }}</span>
      </div>

      <!-- Change source language picker -->
      <Popover v-if="canEdit && sourceLanguageOptions.length > 0" v-model:open="sourcePickerOpen">
        <PopoverTrigger as-child>
          <Button
            variant="ghost"
            size="sm"
            class="w-full justify-start gap-2 text-xs text-muted-foreground"
          >
            <Languages class="size-3.5" />
            {{ $t("localization.sidebar.change_source") }}
          </Button>
        </PopoverTrigger>
        <PopoverContent align="start" :side-offset="4" class="w-(--reka-popover-trigger-width) p-0">
          <Command class="max-h-72">
            <CommandInput :placeholder="$t('localization.sidebar.search_languages')" />
            <CommandList>
              <CommandEmpty>{{ $t("localization.sidebar.no_matches") }}</CommandEmpty>
              <CommandGroup>
                <CommandItem
                  v-for="opt in sourceLanguageOptions"
                  :key="opt.value"
                  :value="opt.label"
                  class="gap-2"
                  @select="requestSourceLanguage(opt)"
                >
                  <img
                    v-if="flagUrl(opt.flagCode)"
                    :src="flagUrl(opt.flagCode) || ''"
                    alt=""
                    aria-hidden="true"
                    :class="flagClasses()"
                  />
                  <span
                    v-else
                    class="inline-flex size-5 shrink-0 items-center justify-center text-[0.65rem] font-semibold uppercase leading-none tracking-[0.04em]"
                  >
                    {{ opt.shortLabel }}
                  </span>
                  <span class="truncate">{{ opt.label }}</span>
                </CommandItem>
              </CommandGroup>
            </CommandList>
          </Command>
        </PopoverContent>
      </Popover>
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
            <img
              v-if="flagIconUrl(lang.flagCode)"
              :src="flagIconUrl(lang.flagCode) || ''"
              alt=""
              aria-hidden="true"
              :class="flagClasses(lang.localeCode !== selectedLocale)"
            />
            <span
              v-else
              class="inline-flex min-w-7 shrink-0 items-center justify-center text-[0.72rem] font-semibold uppercase leading-none tracking-[0.08em]"
            >
              {{ lang.shortLabel }}
            </span>
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
        <Popover v-if="addLanguageOptions.length > 0" v-model:open="addPickerOpen">
          <PopoverTrigger as-child>
            <Button
              variant="ghost"
              size="sm"
              class="w-full justify-start gap-2 text-xs text-muted-foreground"
            >
              <Plus class="size-3.5" />
              {{ $t("localization.sidebar.add_language") }}
            </Button>
          </PopoverTrigger>
          <PopoverContent
            align="start"
            :side-offset="4"
            class="w-(--reka-popover-trigger-width) p-0"
          >
            <Command class="max-h-72">
              <CommandInput :placeholder="$t('localization.sidebar.search_languages')" />
              <CommandList>
                <CommandEmpty>{{ $t("localization.sidebar.no_matches") }}</CommandEmpty>
                <CommandGroup>
                  <CommandItem
                    v-for="opt in addLanguageOptions"
                    :key="opt.value"
                    :value="opt.label"
                    class="gap-2"
                    @select="addTargetLanguage(opt.value)"
                  >
                    <img
                      v-if="flagUrl(opt.flagCode)"
                      :src="flagUrl(opt.flagCode) || ''"
                      alt=""
                      aria-hidden="true"
                      :class="flagClasses()"
                    />
                    <span
                      v-else
                      class="inline-flex size-5 shrink-0 items-center justify-center text-[0.65rem] font-semibold uppercase leading-none tracking-[0.04em]"
                    >
                      {{ opt.shortLabel }}
                    </span>
                    <span class="truncate">{{ opt.label }}</span>
                  </CommandItem>
                </CommandGroup>
              </CommandList>
            </Command>
          </PopoverContent>
        </Popover>
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
