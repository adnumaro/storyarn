<script setup lang="ts">
import { Search, TriangleAlert, X } from "@lucide/vue";
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { Input } from "@components/ui/input";
import {
  SOURCE_TYPE_I18N,
  SOURCE_TYPE_KEYS,
  STATUS_I18N,
  STATUS_KEYS,
  VO_I18N,
  VO_STATUS_KEYS,
  voTone,
} from "../../domain/status";
import type { SpeakerOption, WorkbenchFilters } from "../../domain/types";
import FilterChipMenu, { type FilterOption } from "./FilterChipMenu.vue";

/**
 * Search plus the four single-choice filters and the Outdated toggle. The
 * search field is uncontrolled here and emitted on input; the page debounces.
 */
const {
  filters,
  speakers = [],
  search,
} = defineProps<{
  filters: WorkbenchFilters;
  speakers?: SpeakerOption[];
  search: string;
}>();

const emit = defineEmits<{
  "update:search": [value: string];
  change: [key: string, value: string];
  clear: [];
}>();

const { t } = useI18n();
const searchInput = ref<InstanceType<typeof Input> | null>(null);

const statusOptions = computed<FilterOption[]>(() =>
  STATUS_KEYS.map((status) => ({ value: status, label: t(STATUS_I18N[status]), tone: status })),
);
const typeOptions = computed<FilterOption[]>(() =>
  SOURCE_TYPE_KEYS.map((type) => ({ value: type, label: t(SOURCE_TYPE_I18N[type]) })),
);
const voOptions = computed<FilterOption[]>(() =>
  VO_STATUS_KEYS.map((status) => ({
    value: status,
    label: t(VO_I18N[status]),
    tone: voTone(status),
  })),
);
const speakerOptions = computed<FilterOption[]>(() =>
  speakers.map((speaker) => ({
    value: String(speaker.id),
    label: speaker.name ?? t("localization.overview.speakers.speaker_id", { id: speaker.id }),
  })),
);

const anyActive = computed(
  () =>
    !!filters.status ||
    !!filters.sourceType ||
    !!filters.voStatus ||
    filters.speaker !== null ||
    filters.stale,
);

function focusSearch(): void {
  const element = searchInput.value?.$el as HTMLInputElement | undefined;
  element?.focus();
  element?.select();
}

defineExpose({ focusSearch });
</script>

<template>
  <div class="flex flex-col gap-2 border-b border-border px-2.5 pt-2.5 pb-2">
    <div class="relative">
      <Search
        class="pointer-events-none absolute top-1/2 left-2.5 size-3.5 -translate-y-1/2 text-muted-foreground"
      />
      <Input
        ref="searchInput"
        :model-value="search"
        type="search"
        :placeholder="$t('localization.workbench.search_placeholder')"
        :aria-label="$t('localization.workbench.search_label')"
        class="h-8.5 pr-9 pl-8 text-[13px]"
        data-testid="localization-search"
        @update:model-value="(value) => emit('update:search', String(value))"
      />
      <kbd
        class="pointer-events-none absolute top-1/2 right-2 -translate-y-1/2 rounded border border-border px-1.5 font-mono text-[11px] leading-4 text-muted-foreground"
        aria-hidden="true"
      >
        /
      </kbd>
    </div>

    <div class="flex flex-wrap items-center gap-1.5">
      <FilterChipMenu
        :label="$t('localization.workbench.filters.status')"
        :model-value="filters.status"
        :options="statusOptions"
        :all-label="$t('localization.workbench.filters.all')"
        @update:model-value="(value) => emit('change', 'status', value)"
      />
      <FilterChipMenu
        :label="$t('localization.workbench.filters.type')"
        :model-value="filters.sourceType"
        :options="typeOptions"
        :all-label="$t('localization.workbench.filters.all')"
        @update:model-value="(value) => emit('change', 'source_type', value)"
      />
      <FilterChipMenu
        :label="$t('localization.workbench.filters.voice_over')"
        :model-value="filters.voStatus"
        :options="voOptions"
        :all-label="$t('localization.workbench.filters.all')"
        @update:model-value="(value) => emit('change', 'vo_status', value)"
      />
      <FilterChipMenu
        v-if="speakerOptions.length > 0"
        :label="$t('localization.workbench.filters.speaker')"
        :model-value="filters.speaker === null ? '' : String(filters.speaker)"
        :options="speakerOptions"
        :all-label="$t('localization.workbench.filters.any_speaker')"
        @update:model-value="(value) => emit('change', 'speaker', value)"
      />
      <button
        type="button"
        :class="[
          'inline-flex items-center gap-1 rounded-full border py-[3px] pr-2.5 pl-2 text-xs transition-colors outline-none focus-visible:ring-2 focus-visible:ring-ring/50',
          filters.stale
            ? 'border-orange-500/60 bg-orange-500/10 text-foreground'
            : 'border-border text-muted-foreground hover:bg-accent hover:text-foreground',
        ]"
        :aria-pressed="filters.stale"
        @click="emit('change', 'stale', filters.stale ? 'false' : 'true')"
      >
        <TriangleAlert class="size-3" />
        {{ $t("localization.workbench.filters.outdated") }}
      </button>
      <button
        v-if="anyActive"
        type="button"
        class="inline-flex items-center gap-1 rounded-full px-2 py-[3px] text-xs text-muted-foreground transition-colors hover:text-foreground"
        @click="emit('clear')"
      >
        <X class="size-3" />
        {{ $t("localization.workbench.filters.clear") }}
      </button>
    </div>
  </div>
</template>
