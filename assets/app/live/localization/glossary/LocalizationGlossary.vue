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
} from "lucide-vue-next";
import { computed, ref } from "vue";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select";
import { Textarea } from "@components/ui/textarea";
import { useLive } from "@shared/composables/useLive.ts";
import DashboardContent from "@shell/DashboardContent.vue";

interface Language {
  localeCode: string;
  name: string;
}

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
  sourceLanguage: Language;
  targetLanguages?: Language[];
  selectedLocale?: string | null;
  entries?: GlossaryEntry[];
  canEdit?: boolean;
  hasProvider?: boolean;
  synced?: boolean;
  backUrl?: string | null;
}>();

const live = useLive();
const editingId = ref<number | null>(null);
const sourceTerm = ref("");
const targetTerm = ref("");
const context = ref("");
const doNotTranslate = ref(false);
const saving = ref(false);
const syncing = ref(false);
const feedback = ref<"idle" | "saved" | "synced" | "error">("idle");
const errorMessage = ref("");

const selectedLanguage = computed(
  () => targetLanguages.find((language) => language.localeCode === selectedLocale) ?? null,
);

const formReady = computed(
  () => sourceTerm.value.trim() !== "" && (doNotTranslate.value || targetTerm.value.trim() !== ""),
);

function changeLocale(value: string | string[]): void {
  const locale = Array.isArray(value) ? value[0] : value;
  if (locale) live.pushEvent("change_locale", { locale });
}

function saveEntry(): void {
  if (!canEdit || !formReady.value || saving.value) return;
  saving.value = true;
  feedback.value = "idle";

  live.pushEvent(
    "save_entry",
    {
      id: editingId.value,
      source_term: sourceTerm.value,
      target_term: doNotTranslate.value ? sourceTerm.value : targetTerm.value,
      context: context.value,
      do_not_translate: doNotTranslate.value,
    },
    (response: EventResponse) => {
      saving.value = false;
      if (response?.ok) {
        resetForm();
        feedback.value = "saved";
      } else {
        feedback.value = "error";
        errorMessage.value = response?.errors
          ? Object.values(response.errors).join(" · ")
          : response?.error || "save_failed";
      }
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

function deleteEntry(entry: GlossaryEntry): void {
  if (!window.confirm(`Delete “${entry.sourceTerm}”?`)) return;
  live.pushEvent("delete_entry", { id: entry.id });
  if (editingId.value === entry.id) resetForm();
}

function syncGlossary(): void {
  if (!hasProvider || syncing.value) return;
  syncing.value = true;
  feedback.value = "idle";
  live.pushEvent("sync_glossary", {}, (response: EventResponse) => {
    syncing.value = false;
    if (response?.ok) feedback.value = "synced";
    else {
      feedback.value = "error";
      errorMessage.value = response?.error || "sync_failed";
    }
  });
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
  <DashboardContent>
    <div class="mx-auto w-full max-w-6xl space-y-6 py-6">
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
            <p class="mt-1 text-sm text-base-content/55">
              {{ $t("localization.glossary.subtitle") }}
            </p>
          </div>
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <Select :model-value="selectedLocale || undefined" @update:model-value="changeLocale">
            <SelectTrigger class="w-52">
              <SelectValue :placeholder="$t('localization.glossary.select_language')" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem
                v-for="language in targetLanguages"
                :key="language.localeCode"
                :value="language.localeCode"
              >
                {{ language.name }}
              </SelectItem>
            </SelectContent>
          </Select>
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
        <section class="overflow-hidden rounded-xl border border-base-300 bg-base-100 shadow-sm">
          <div class="flex items-center justify-between border-b border-base-300 px-4 py-3">
            <div>
              <h2 class="font-semibold">{{ sourceLanguage.name }} → {{ selectedLanguage.name }}</h2>
              <p class="text-xs text-base-content/50">
                {{ $t("localization.glossary.entry_count", { count: entries.length }) }}
              </p>
            </div>
            <span
              :class="[
                'badge badge-sm',
                !hasProvider ? 'badge-ghost' : synced ? 'badge-success' : 'badge-warning',
              ]"
            >
              {{
                !hasProvider
                  ? $t("localization.glossary.local_only")
                  : synced
                    ? $t("localization.glossary.up_to_date")
                    : $t("localization.glossary.pending_sync")
              }}
            </span>
          </div>

          <div v-if="entries.length" class="divide-y divide-base-300">
            <article
              v-for="entry in entries"
              :key="entry.id"
              class="group grid gap-2 px-4 py-3 transition-colors hover:bg-base-200/50 sm:grid-cols-[minmax(0,1fr)_minmax(0,1fr)_auto] sm:items-center"
            >
              <div class="min-w-0">
                <p class="truncate font-medium">{{ entry.sourceTerm }}</p>
                <p v-if="entry.context" class="truncate text-xs text-base-content/45">
                  {{ entry.context }}
                </p>
              </div>
              <div class="min-w-0 text-sm">
                <span v-if="entry.doNotTranslate" class="badge badge-outline badge-sm">
                  {{ $t("localization.glossary.do_not_translate") }}
                </span>
                <span v-else class="block truncate">{{ entry.targetTerm }}</span>
              </div>
              <div v-if="canEdit" class="flex justify-end gap-1">
                <Button variant="ghost" size="icon-sm" @click="editEntry(entry)">
                  <Pencil class="size-3.5" />
                </Button>
                <Button variant="ghost" size="icon-sm" @click="deleteEntry(entry)">
                  <Trash2 class="size-3.5 text-error" />
                </Button>
              </div>
            </article>
          </div>
          <div v-else class="px-6 py-14 text-center">
            <BookOpenText class="mx-auto size-9 text-base-content/20" />
            <p class="mt-3 font-medium">{{ $t("localization.glossary.empty_title") }}</p>
            <p class="mt-1 text-sm text-base-content/50">
              {{ $t("localization.glossary.empty_description") }}
            </p>
          </div>
        </section>

        <aside v-if="canEdit" class="rounded-xl border border-base-300 bg-base-100 p-4 shadow-sm">
          <div class="flex items-center justify-between">
            <h2 class="font-semibold">
              {{
                editingId
                  ? $t("localization.glossary.edit_entry")
                  : $t("localization.glossary.add_entry")
              }}
            </h2>
            <button v-if="editingId" class="btn btn-ghost btn-xs" type="button" @click="resetForm">
              {{ $t("localization.glossary.cancel_edit") }}
            </button>
          </div>
          <div class="mt-4 space-y-3">
            <label class="form-control gap-1.5">
              <span class="text-xs font-medium text-base-content/60">{{
                sourceLanguage.name
              }}</span>
              <Input v-model="sourceTerm" :disabled="!!editingId" />
            </label>
            <label class="flex cursor-pointer items-center gap-2 text-sm">
              <input v-model="doNotTranslate" type="checkbox" class="checkbox checkbox-sm" />
              {{ $t("localization.glossary.do_not_translate") }}
            </label>
            <label class="form-control gap-1.5">
              <span class="text-xs font-medium text-base-content/60">{{
                selectedLanguage.name
              }}</span>
              <Input v-model="targetTerm" :disabled="doNotTranslate" />
            </label>
            <label class="form-control gap-1.5">
              <span class="text-xs font-medium text-base-content/60">{{
                $t("localization.glossary.context")
              }}</span>
              <Textarea v-model="context" class="min-h-20" />
            </label>
            <Button class="w-full" :disabled="!formReady || saving" @click="saveEntry">
              <LoaderCircle v-if="saving" class="size-4 animate-spin" />
              <Plus v-else-if="!editingId" class="size-4" />
              <Check v-else class="size-4" />
              {{ $t("localization.glossary.save_entry") }}
            </Button>
            <p v-if="feedback === 'error'" class="text-xs text-error" role="alert">
              {{ errorMessage }}
            </p>
            <p v-else-if="feedback === 'synced'" class="text-xs text-success" role="status">
              {{ $t("localization.glossary.sync_success") }}
            </p>
          </div>
        </aside>
      </div>

      <div v-else class="rounded-xl border border-dashed border-base-300 py-16 text-center">
        <BookOpenText class="mx-auto size-10 text-base-content/20" />
        <p class="mt-3 font-medium">{{ $t("localization.glossary.no_target") }}</p>
      </div>
    </div>
  </DashboardContent>
</template>
