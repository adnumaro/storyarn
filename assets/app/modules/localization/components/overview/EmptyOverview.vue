<script setup lang="ts">
import { Globe, LoaderCircle, Plus } from "@lucide/vue";
import { ref } from "vue";
import LanguagePicker from "@components/language/LanguagePicker.vue";
import type { LanguagePickerOption } from "@components/language/types";
import LiveLink from "@components/navigation/LiveLink.vue";
import { Button } from "@components/ui/button";

/**
 * The overview with no target language: add the first one right here instead
 * of pointing at the sidebar.
 */
const {
  sourceName,
  runtimeWordCount = null,
  canEdit = false,
  hasProvider = false,
  addLanguageOptions = [],
  settingsUrl,
  adding = false,
} = defineProps<{
  sourceName: string;
  runtimeWordCount?: number | null;
  canEdit?: boolean;
  hasProvider?: boolean;
  addLanguageOptions?: LanguagePickerOption[];
  settingsUrl: string;
  adding?: boolean;
}>();

const emit = defineEmits<{ add: [localeCode: string] }>();

const pending = ref<LanguagePickerOption | null>(null);

function choose(option: LanguagePickerOption): void {
  pending.value = option;
}

function submit(): void {
  if (!pending.value || adding) return;
  emit("add", pending.value.value);
}
</script>

<template>
  <div class="flex flex-col items-center gap-7 px-0 pt-10 pb-6">
    <div
      class="flex w-full max-w-[560px] flex-col gap-5 rounded-xl border border-border bg-card p-6 sm:p-9"
      data-testid="localization-empty-overview"
    >
      <div class="flex flex-col items-start gap-3">
        <div class="flex size-11 items-center justify-center rounded-xl bg-primary/12 text-primary">
          <Globe class="size-[22px]" />
        </div>
        <div>
          <h2 class="text-lg font-semibold tracking-tight">
            {{ $t("localization.overview.empty.title") }}
          </h2>
          <p class="mt-1.5 text-sm text-pretty text-muted-foreground">
            {{ $t("localization.overview.empty.description", { source: sourceName }) }}
          </p>
        </div>
      </div>

      <form
        v-if="canEdit"
        class="grid grid-cols-1 items-center gap-2.5 sm:grid-cols-[minmax(0,1fr)_auto]"
        @submit.prevent="submit"
      >
        <LanguagePicker
          id="localization-overview-add-language"
          :model-value="pending?.value ?? null"
          :options="addLanguageOptions"
          :label="$t('localization.overview.empty.add')"
          :disabled="adding || addLanguageOptions.length === 0"
          :text="{
            placeholder: $t('localization.overview.empty.choose'),
            searchPlaceholder: $t('localization.sidebar.search_languages'),
            emptyLabel: $t('localization.sidebar.no_matches'),
          }"
          :appearance="{ triggerSize: 'lg', triggerClass: 'w-full' }"
          @select="choose"
        />
        <Button
          type="submit"
          size="lg"
          :disabled="!pending || adding"
          data-testid="localization-overview-add-language-submit"
        >
          <LoaderCircle v-if="adding" class="size-4 animate-spin" />
          <Plus v-else class="size-4" />
          {{ $t("localization.overview.empty.add") }}
        </Button>
      </form>
      <p v-else class="text-sm text-muted-foreground">
        {{ $t("localization.overview.empty.read_only") }}
      </p>

      <p
        v-if="runtimeWordCount !== null"
        class="border-t border-border pt-4 text-xs text-muted-foreground"
      >
        {{ $t("localization.overview.empty.inventory", runtimeWordCount) }}
      </p>
    </div>

    <div
      class="flex flex-col items-center gap-2 text-center text-[13px] text-pretty text-muted-foreground"
    >
      <p>
        {{ $t("localization.overview.empty.machine_prompt") }}
        <LiveLink v-if="!hasProvider" :to="settingsUrl" class="text-primary hover:text-primary/80">
          {{ $t("localization.overview.empty.machine_link") }}
        </LiveLink>
        <span v-else>{{ $t("localization.overview.empty.machine_ready") }}</span>
      </p>
      <p>
        {{ $t("localization.overview.empty.source_prompt") }}
        {{ $t("localization.overview.empty.source_hint") }}
      </p>
    </div>
  </div>
</template>
