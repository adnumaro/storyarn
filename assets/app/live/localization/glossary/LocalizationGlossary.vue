<script setup lang="ts">
import {
  ArrowLeft,
  BookOpenText,
  Check,
  LoaderCircle,
  Pencil,
  Plus,
  RefreshCw,
  Trash2,
} from "@lucide/vue";
import { computed, ref, useId } from "vue";
import { useI18n } from "vue-i18n";
import ConfirmDialog from "@components/ConfirmDialog.vue";
import LanguagePicker from "@components/language/LanguagePicker.vue";
import type { LanguagePickerOption } from "@components/language/types";
import { Badge } from "@components/ui/badge";
import { Button } from "@components/ui/button";
import { Checkbox } from "@components/ui/checkbox";
import { Input } from "@components/ui/input";
import { Label } from "@components/ui/label";
import { Textarea } from "@components/ui/textarea";
import { useLive } from "@shared/composables/useLive.ts";
import DashboardContent from "@shell/DashboardContent.vue";
import PageContainer from "@shell/PageContainer.vue";
import { useLiveAction } from "@shared/composables/useLiveAction";

interface GlossaryEntry {
  id: number;
  sourceTerm: string;
  targetTerm: string;
  context: string;
  doNotTranslate: boolean;
}

interface EventResponse {
  ok?: boolean;
  error?: string;
  errors?: Record<string, string>;
}

const {
  sourceLanguage,
  targetLanguages = [],
  selectedLocale = null,
  entries = [],
  canEdit = false,
  hasProvider = false,
  synced = false,
  backUrl = null,
} = defineProps<{
  sourceLanguage: LanguagePickerOption;
  targetLanguages?: LanguagePickerOption[];
  selectedLocale?: string | null;
  entries?: GlossaryEntry[];
  canEdit?: boolean;
  hasProvider?: boolean;
  synced?: boolean;
  backUrl?: string | null;
}>();

const live = useLive();
const { t } = useI18n();
const sourceTermId = useId();
const targetTermId = useId();
const contextId = useId();
const doNotTranslateId = useId();
const editingId = ref<number | null>(null);
const sourceTerm = ref("");
const targetTerm = ref("");
const context = ref("");
const doNotTranslate = ref(false);
const saveAction = useLiveAction(live);
const syncAction = useLiveAction(live);
const saving = saveAction.pending;
const syncing = syncAction.pending;
const feedback = ref<"idle" | "saved" | "synced" | "error">("idle");
const errorMessage = ref("");
const pendingDelete = ref<GlossaryEntry | null>(null);
const deleteDialogOpen = computed({
  get: () => pendingDelete.value !== null,
  set: (open: boolean) => {
    if (!open) pendingDelete.value = null;
  },
});

const syncBadgeClass = computed(() => {
  if (!hasProvider) return "";
  return synced
    ? "border-success/30 bg-success/10 text-success"
    : "border-warning/30 bg-warning/10 text-warning";
});

const selectedLanguage = computed(
  () => targetLanguages.find((language) => language.value === selectedLocale) ?? null,
);

const formReady = computed(
  () => sourceTerm.value.trim() !== "" && (doNotTranslate.value || targetTerm.value.trim() !== ""),
);

function changeLocale(language: LanguagePickerOption): void {
  live.pushEvent("change_locale", { locale: language.value });
}

function saveEntry(): void {
  if (!canEdit || !formReady.value || saving.value) return;
  feedback.value = "idle";

  saveAction.push(
    "save_entry",
    {
      id: editingId.value,
      source_term: sourceTerm.value,
      target_term: doNotTranslate.value ? sourceTerm.value : targetTerm.value,
      context: context.value,
      do_not_translate: doNotTranslate.value,
    },
    {
      onReply: (reply) => {
        const response = reply as EventResponse;
        if (response.ok) {
          resetForm();
          feedback.value = "saved";
        } else {
          feedback.value = "error";
          errorMessage.value = response.errors
            ? Object.values(response.errors).join(" · ")
            : t("localization.glossary.save_failed");
        }
      },
      onError: () => {
        feedback.value = "error";
        errorMessage.value = t("localization.glossary.save_failed");
      },
    },
  );
}

function editEntry(entry: GlossaryEntry): void {
  editingId.value = entry.id;
  sourceTerm.value = entry.sourceTerm;
  targetTerm.value = entry.targetTerm;
  context.value = entry.context;
  doNotTranslate.value = entry.doNotTranslate;
  feedback.value = "idle";
}

function requestDelete(entry: GlossaryEntry): void {
  pendingDelete.value = entry;
}

function confirmDelete(): void {
  const entry = pendingDelete.value;
  if (!entry) return;
  live.pushEvent("delete_entry", { id: entry.id });
  if (editingId.value === entry.id) resetForm();
}

function syncGlossary(): void {
  if (!hasProvider || syncing.value) return;
  feedback.value = "idle";
  const failed = () => {
    feedback.value = "error";
    errorMessage.value = t("localization.glossary.sync_failed");
  };
  syncAction.push(
    "sync_glossary",
    {},
    {
      onReply: (reply) => ((reply as EventResponse).ok ? (feedback.value = "synced") : failed()),
      onError: failed,
    },
  );
}

function resetForm(): void {
  editingId.value = null;
  sourceTerm.value = "";
  targetTerm.value = "";
  context.value = "";
  doNotTranslate.value = false;
}
</script>

<template>
  <PageContainer>
    <DashboardContent>
      <header class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div class="flex items-start gap-3">
          <Button v-if="backUrl" variant="ghost" size="icon-sm" as-child>
            <a :href="backUrl" data-phx-link="patch" data-phx-link-state="push">
              <ArrowLeft class="size-4" />
            </a>
          </Button>
          <div>
            <div class="flex items-center gap-2">
              <BookOpenText class="size-5 text-primary" />
              <h1 class="text-xl font-semibold">{{ $t("localization.glossary.title") }}</h1>
            </div>
            <p class="mt-1 text-sm text-muted-foreground">
              {{ $t("localization.glossary.subtitle") }}
            </p>
          </div>
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <LanguagePicker
            id="localization-glossary-language-picker"
            :model-value="selectedLocale"
            :options="targetLanguages"
            :label="$t('localization.glossary.select_language')"
            :text="{
              placeholder: $t('localization.glossary.select_language'),
              searchPlaceholder: $t('localization.sidebar.search_languages'),
              emptyLabel: $t('localization.sidebar.no_matches'),
            }"
            :appearance="{
              align: 'end',
              triggerClass: 'w-52',
            }"
            @select="changeLocale"
          />
          <Button
            v-if="canEdit && hasProvider && selectedLocale"
            variant="outline"
            :disabled="syncing"
            @click="syncGlossary"
          >
            <LoaderCircle v-if="syncing" class="size-4 animate-spin" />
            <RefreshCw v-else class="size-4" />
            {{
              synced ? $t("localization.glossary.synced") : $t("localization.glossary.sync_deepl")
            }}
          </Button>
        </div>
      </header>

      <div
        v-if="selectedLanguage"
        class="grid items-start gap-5 lg:grid-cols-[minmax(0,1fr)_22rem]"
      >
        <section class="overflow-hidden rounded-xl border bg-card shadow-sm">
          <div class="flex items-center justify-between border-b px-4 py-3">
            <div>
              <h2 class="font-semibold">
                {{ sourceLanguage.label }} → {{ selectedLanguage.label }}
              </h2>
              <p class="text-xs text-muted-foreground">
                {{ $t("localization.glossary.entry_count", { count: entries.length }) }}
              </p>
            </div>
            <Badge :variant="hasProvider ? 'outline' : 'secondary'" :class="syncBadgeClass">
              {{
                !hasProvider
                  ? $t("localization.glossary.local_only")
                  : synced
                    ? $t("localization.glossary.up_to_date")
                    : $t("localization.glossary.pending_sync")
              }}
            </Badge>
          </div>

          <div v-if="entries.length" class="divide-y">
            <article
              v-for="entry in entries"
              :key="entry.id"
              class="group grid gap-2 px-4 py-3 transition-colors hover:bg-muted/50 sm:grid-cols-[minmax(0,1fr)_minmax(0,1fr)_auto] sm:items-center"
            >
              <div class="min-w-0">
                <p class="truncate font-medium">{{ entry.sourceTerm }}</p>
                <p v-if="entry.context" class="truncate text-xs text-muted-foreground">
                  {{ entry.context }}
                </p>
              </div>
              <div class="min-w-0 text-sm">
                <Badge v-if="entry.doNotTranslate" variant="outline">
                  {{ $t("localization.glossary.do_not_translate") }}
                </Badge>
                <span v-else class="block truncate">{{ entry.targetTerm }}</span>
              </div>
              <div v-if="canEdit" class="flex justify-end gap-1">
                <Button
                  variant="ghost"
                  size="icon-sm"
                  :aria-label="$t('localization.glossary.edit_action')"
                  @click="editEntry(entry)"
                >
                  <Pencil class="size-3.5" />
                </Button>
                <Button
                  variant="ghost"
                  size="icon-sm"
                  :aria-label="$t('localization.glossary.delete_action')"
                  @click="requestDelete(entry)"
                >
                  <Trash2 class="size-3.5 text-destructive" />
                </Button>
              </div>
            </article>
          </div>
          <div v-else class="px-6 py-14 text-center">
            <BookOpenText class="mx-auto size-9 text-muted-foreground/40" />
            <p class="mt-3 font-medium">{{ $t("localization.glossary.empty_title") }}</p>
            <p class="mt-1 text-sm text-muted-foreground">
              {{ $t("localization.glossary.empty_description") }}
            </p>
          </div>
        </section>

        <aside v-if="canEdit" class="rounded-xl border bg-card p-4 shadow-sm">
          <div class="flex items-center justify-between">
            <h2 class="font-semibold">
              {{
                editingId
                  ? $t("localization.glossary.edit_entry")
                  : $t("localization.glossary.add_entry")
              }}
            </h2>
            <Button v-if="editingId" variant="ghost" size="xs" @click="resetForm">
              {{ $t("localization.glossary.cancel_edit") }}
            </Button>
          </div>
          <div class="mt-4 space-y-3">
            <div class="flex flex-col gap-1.5">
              <Label :for="sourceTermId" class="text-xs text-muted-foreground">
                {{ sourceLanguage.label }}
              </Label>
              <Input :id="sourceTermId" v-model="sourceTerm" :disabled="!!editingId" />
            </div>
            <div class="flex items-center gap-2">
              <Checkbox :id="doNotTranslateId" v-model="doNotTranslate" />
              <Label :for="doNotTranslateId" class="cursor-pointer font-normal">
                {{ $t("localization.glossary.do_not_translate") }}
              </Label>
            </div>
            <div class="flex flex-col gap-1.5">
              <Label :for="targetTermId" class="text-xs text-muted-foreground">
                {{ selectedLanguage.label }}
              </Label>
              <Input :id="targetTermId" v-model="targetTerm" :disabled="doNotTranslate" />
            </div>
            <div class="flex flex-col gap-1.5">
              <Label :for="contextId" class="text-xs text-muted-foreground">
                {{ $t("localization.glossary.context") }}
              </Label>
              <Textarea :id="contextId" v-model="context" class="min-h-20" />
            </div>
            <Button class="w-full" :disabled="!formReady || saving" @click="saveEntry">
              <LoaderCircle v-if="saving" class="size-4 animate-spin" />
              <Plus v-else-if="!editingId" class="size-4" />
              <Check v-else class="size-4" />
              {{ $t("localization.glossary.save_entry") }}
            </Button>
            <p v-if="feedback === 'error'" class="text-xs text-destructive" role="alert">
              {{ errorMessage }}
            </p>
            <p v-else-if="feedback === 'synced'" class="text-xs text-success" role="status">
              {{ $t("localization.glossary.sync_success") }}
            </p>
          </div>
        </aside>
      </div>

      <div v-else class="rounded-xl border border-dashed py-16 text-center">
        <BookOpenText class="mx-auto size-10 text-muted-foreground/40" />
        <p class="mt-3 font-medium">{{ $t("localization.glossary.no_target") }}</p>
      </div>

      <ConfirmDialog
        v-model:open="deleteDialogOpen"
        :title="
          $t('localization.glossary.delete_confirm_title', {
            term: pendingDelete?.sourceTerm ?? '',
          })
        "
        :description="$t('localization.glossary.delete_confirm_description')"
        :confirm-text="$t('localization.glossary.delete_action')"
        :cancel-text="$t('localization.glossary.cancel_edit')"
        variant="destructive"
        :icon="Trash2"
        @confirm="confirmDelete"
      />
    </DashboardContent>
  </PageContainer>
</template>
