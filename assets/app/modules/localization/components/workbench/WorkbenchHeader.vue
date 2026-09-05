<script setup lang="ts">
import { ChevronDown } from "@lucide/vue";
import LanguageFlag from "@components/language/LanguageFlag.vue";
import type { LanguagePickerOption } from "@components/language/types";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@components/ui/dropdown-menu";
import type { WorkbenchLanguage } from "../../domain/types";

/** The language being translated, with a switcher to the other targets. */
const {
  language,
  targetLanguages = [],
  totalCount,
} = defineProps<{
  language: WorkbenchLanguage;
  targetLanguages?: LanguagePickerOption[];
  totalCount: number;
}>();
</script>

<template>
  <div class="flex items-center gap-3">
    <LanguageFlag :flag-code="language.flagCode" :short-label="language.shortLabel" size="lg" />
    <div class="min-w-0">
      <DropdownMenu>
        <DropdownMenuTrigger as-child>
          <button
            type="button"
            class="inline-flex max-w-full items-center gap-1.5 rounded-md text-[22px] leading-tight font-semibold tracking-tight outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
            :aria-label="$t('localization.workbench.switch_language')"
          >
            <span class="truncate">{{ language.name }}</span>
            <ChevronDown class="size-4 shrink-0 text-muted-foreground" />
          </button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="start" class="min-w-52">
          <DropdownMenuItem
            v-for="target in targetLanguages"
            :key="target.value"
            :disabled="target.value === language.code"
            as-child
          >
            <a
              :href="target.href"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="flex items-center gap-2"
            >
              <LanguageFlag
                :flag-code="target.flagCode"
                :short-label="target.shortLabel"
                size="sm"
              />
              {{ target.label }}
            </a>
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
      <p class="text-[13px] text-muted-foreground">
        {{ $t("localization.workbench.from_source", { source: language.sourceName }) }}
        · {{ $t("localization.workbench.count", totalCount) }} ·
        {{ $t("localization.overview.words", language.wordCount) }}
      </p>
    </div>
  </div>
</template>
