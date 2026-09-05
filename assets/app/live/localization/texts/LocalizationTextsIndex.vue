<script setup lang="ts">
import { Globe } from "@lucide/vue";
import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import type { LanguagePickerOption } from "@components/language/types";
import LiveLink from "@components/navigation/LiveLink.vue";
import EditorEmptyPane from "@modules/localization/components/workbench/EditorEmptyPane.vue";
import FilterBar from "@modules/localization/components/workbench/FilterBar.vue";
import StringEditor from "@modules/localization/components/workbench/StringEditor.vue";
import StringList from "@modules/localization/components/workbench/StringList.vue";
import WorkbenchHeader from "@modules/localization/components/workbench/WorkbenchHeader.vue";
import WorkbenchSummary from "@modules/localization/components/workbench/WorkbenchSummary.vue";
import { useTranslationEditor } from "@modules/localization/composables/useTranslationEditor";
import type {
  SelectedText,
  SpeakerOption,
  TextRow,
  WorkbenchFilters,
  WorkbenchLanguage,
  WorkbenchProgress,
} from "@modules/localization/domain/types";
import { useLive } from "@shared/composables/useLive.ts";

interface WorkbenchLanguages {
  current: WorkbenchLanguage | null;
  targets: LanguagePickerOption[];
}

interface Pagination {
  page: number;
  pageSize: number;
  hasMore: boolean;
}

interface Capabilities {
  canEdit: boolean;
  hasProvider: boolean;
  hasTargetLanguages: boolean;
}

const SEARCH_DEBOUNCE_MS = 300;

const {
  texts = [],
  progress = null,
  totalCount = 0,
  pagination = { page: 1, pageSize: 50, hasMore: false },
  filters = { status: "", sourceType: "", voStatus: "", speaker: null, stale: false, search: "" },
  capabilities = { canEdit: false, hasProvider: false, hasTargetLanguages: false },
  selectedText = null,
  languages = { current: null, targets: [] },
  speakers = [],
  overviewUrl = "",
} = defineProps<{
  texts?: TextRow[];
  progress?: WorkbenchProgress | null;
  totalCount?: number;
  pagination?: Pagination;
  filters?: WorkbenchFilters;
  capabilities?: Capabilities;
  selectedText?: SelectedText | null;
  languages?: WorkbenchLanguages;
  speakers?: SpeakerOption[];
  overviewUrl?: string;
}>();

const live = useLive();
const { t } = useI18n();

const canEdit = computed(() => capabilities.canEdit);
const hasProvider = computed(() => capabilities.hasProvider);
const hasTargetLanguages = computed(() => capabilities.hasTargetLanguages);
const canTranslateRows = computed(() => canEdit.value && hasProvider.value);
const sourceName = computed(() => languages.current?.sourceName ?? "");

// ── Filters and search (the LiveView owns them through the URL) ─────────────
const localSearch = ref(filters.search);
let searchTimeout: ReturnType<typeof setTimeout> | null = null;
const filterBar = ref<InstanceType<typeof FilterBar> | null>(null);

watch(
  () => filters.search,
  (value) => {
    localSearch.value = value;
  },
);

function onSearchInput(value: string): void {
  localSearch.value = value;
  if (searchTimeout) clearTimeout(searchTimeout);
  searchTimeout = setTimeout(() => {
    live.pushEvent("search", { search: value });
  }, SEARCH_DEBOUNCE_MS);
}

function changeFilter(key: string, value: string): void {
  live.pushEvent("change_filter", { [key]: value });
}

function clearFilters(): void {
  live.pushEvent("change_filter", {
    status: "",
    source_type: "",
    vo_status: "",
    speaker: "",
    stale: "false",
  });
}

function toggleTile(kind: "pending" | "review" | "stale"): void {
  if (kind === "stale") {
    changeFilter("stale", filters.stale ? "false" : "true");
    return;
  }
  const active = filters.status === kind && !filters.stale;
  live.pushEvent("change_filter", { status: active ? "" : kind, stale: "false" });
}

// ── Rows ────────────────────────────────────────────────────────────────────
const loadingMore = ref(false);

function loadMore(): void {
  if (loadingMore.value || !pagination.hasMore) return;
  loadingMore.value = true;
  const done = () => {
    loadingMore.value = false;
  };
  live.pushEvent("load_more", {}, done, done);
}

function selectNext(kind: "pending" | "review" | "stale"): void {
  live.pushEvent("select_next", { kind });
}

// ── Editor ──────────────────────────────────────────────────────────────────
const editor = useTranslationEditor({
  live,
  selectedText: () => selectedText,
  texts: () => texts,
  canEdit: () => canEdit.value,
  hasMore: () => pagination.hasMore,
  onSelect: (id) => live.pushEvent("select_text", { id }),
  onClose: () => live.pushEvent("close_editor", {}),
  onLoadMore: loadMore,
});

const selectedPosition = computed(() =>
  editor.currentIndex.value >= 0 ? editor.currentIndex.value + 1 : null,
);

const navigation = computed(() => ({
  positionLabel:
    selectedPosition.value === null
      ? null
      : t("localization.workbench.position", { index: selectedPosition.value, total: totalCount }),
  hasPrevious: editor.previousText.value !== null,
  hasNext: editor.canAdvance.value,
}));

const editorState = computed(() => ({
  saveState: editor.saveState.value,
  saveError: editor.saveError.value,
  translating: editor.translating.value,
  placeholderIssue: editor.placeholderIssue.value,
  finalUnavailable: editor.finalUnavailable.value,
}));

// ── Keyboard: "/" focuses search, Esc closes the editor ─────────────────────
function isTypingTarget(target: EventTarget | null): boolean {
  return (
    target instanceof HTMLElement &&
    (target.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName))
  );
}

function hasModifier(event: KeyboardEvent): boolean {
  return event.metaKey || event.ctrlKey || event.altKey;
}

function onWindowKeydown(event: KeyboardEvent): void {
  if (event.defaultPrevented || hasModifier(event)) return;

  if (event.key === "/") focusSearchShortcut(event);
  else if (event.key === "Escape") closeEditorShortcut(event);
}

function focusSearchShortcut(event: KeyboardEvent): void {
  if (isTypingTarget(event.target)) return;
  event.preventDefault();
  filterBar.value?.focusSearch();
}

function closeEditorShortcut(event: KeyboardEvent): void {
  if (!selectedText || !escapeTarget(event.target)) return;
  event.preventDefault();
  editor.closeEditor();
}

function escapeTarget(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  return target === document.body || target.matches("textarea, [data-row-id]");
}

onMounted(() => window.addEventListener("keydown", onWindowKeydown));
onBeforeUnmount(() => {
  window.removeEventListener("keydown", onWindowKeydown);
  if (searchTimeout) clearTimeout(searchTimeout);
});
</script>

<template>
  <div class="flex h-full min-h-0 flex-col gap-4">
    <div
      v-if="!hasTargetLanguages || !languages.current"
      class="flex flex-1 flex-col items-center justify-center gap-3 py-16 text-center"
      data-testid="localization-no-languages"
    >
      <Globe class="size-12 text-muted-foreground/30" />
      <h1 class="text-base font-semibold">{{ $t("localization.workbench.no_languages.title") }}</h1>
      <p class="max-w-sm text-sm text-pretty text-muted-foreground">
        {{ $t("localization.workbench.no_languages.description") }}
      </p>
      <LiveLink :to="overviewUrl" class="text-sm font-medium text-primary hover:text-primary/80">
        {{ $t("localization.workbench.no_languages.open_overview") }}
      </LiveLink>
    </div>

    <template v-else>
      <WorkbenchHeader
        :language="languages.current"
        :target-languages="languages.targets"
        :total-count="progress?.total ?? totalCount"
        :class="selectedText && 'hidden lg:flex'"
      />

      <WorkbenchSummary
        v-if="progress"
        :progress="progress"
        :filters="filters"
        :class="selectedText && 'hidden lg:flex'"
        @toggle="toggleTile"
      />

      <div
        class="grid min-h-0 flex-1 grid-cols-1 gap-4 lg:grid-cols-[minmax(19rem,25rem)_minmax(0,1fr)]"
      >
        <StringList
          :class="selectedText ? 'hidden lg:flex' : 'flex'"
          :texts="texts"
          :selected-id="selectedText?.id ?? null"
          :total-count="totalCount"
          :has-more="pagination.hasMore"
          :loading-more="loadingMore"
          :can-translate="canTranslateRows"
          :translating="editor.translating.value"
          :selected-position="selectedPosition"
          @select="editor.requestSelection"
          @translate="editor.translateText"
          @load-more="loadMore"
        >
          <template #filters>
            <FilterBar
              ref="filterBar"
              :filters="filters"
              :speakers="speakers"
              :search="localSearch"
              @update:search="onSearchInput"
              @change="changeFilter"
              @clear="clearFilters"
            />
          </template>
        </StringList>

        <StringEditor
          v-if="selectedText"
          v-model:translated-text="editor.translatedText.value"
          v-model:status="editor.status.value"
          v-model:translator-notes="editor.translatorNotes.value"
          v-model:vo-status="editor.voStatus.value"
          :text="selectedText"
          :source-name="sourceName"
          :can-edit="canEdit"
          :has-provider="hasProvider"
          :navigation="navigation"
          :editor-state="editorState"
          @save="editor.saveTranslation(false)"
          @save-next="editor.saveTranslation(true)"
          @translate="editor.translateText(selectedText.id)"
          @confirm-current="editor.confirmStillCorrect"
          @retry-conflict="editor.retryAfterConflict"
          @reload-conflict="editor.reloadAfterConflict"
          @previous="editor.selectRelative('previous')"
          @next="editor.selectRelative('next')"
          @close="editor.closeEditor"
        />

        <EditorEmptyPane
          v-else-if="progress"
          class="hidden lg:flex"
          :progress="progress"
          :can-edit="canEdit"
          @next="selectNext"
        />
      </div>
    </template>
  </div>
</template>
