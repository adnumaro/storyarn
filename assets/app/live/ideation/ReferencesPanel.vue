<script setup lang="ts">
import { computed, onUnmounted, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import {
  ArrowUpRight,
  Check,
  History,
  Link2,
  Loader2,
  RefreshCw,
  Search,
  Unlink,
  X,
} from "@lucide/vue";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select";
import ConfirmDialog from "@components/ConfirmDialog.vue";
import LiveLink from "@components/navigation/LiveLink.vue";
import Sidebar from "@shell/Sidebar.vue";
import { useLive } from "@shared/composables/useLive";
import ReferenceOverview from "./ReferenceOverview.vue";
import type {
  BrainstormingReference,
  ReferenceRelation,
  ReferenceTarget,
  ReferenceTargetType,
  ReferencesPanelState,
} from "./referenceTypes";

const { state, epoch, sessionId } = defineProps<{
  state: ReferencesPanelState;
  epoch: string;
  sessionId: number;
}>();

const { t, locale } = useI18n();
const live = useLive();
const query = ref("");
const type = ref<ReferenceTargetType>("sheet");
const relation = ref<ReferenceRelation>("reference");
const pending = ref<string | null>(null);
const failure = ref<string | null>(null);
const confirmation = ref<{
  action: "refresh" | "remove";
  reference: BrainstormingReference;
} | null>(null);
const confirmationOpen = computed({
  get: () => confirmation.value !== null,
  set: (open) => {
    if (!open) confirmation.value = null;
  },
});
const targetTypes: ReferenceTargetType[] = ["sheet", "flow", "scene", "asset", "localization"];
const relations: ReferenceRelation[] = ["origin", "reference", "affects", "result", "work"];
const results = computed(() => state.results.filter((target) => target.type === type.value));
const notice = computed(() => failure.value ?? state.error);
let token: symbol | null = null;
const requestKeys = new Map<string, string>();

function reset() {
  token = null;
  pending.value = null;
  failure.value = null;
  confirmation.value = null;
  query.value = "";
  requestKeys.clear();
}

watch(() => `${epoch}:${sessionId}:${state.context}:${state.open}`, reset);
onUnmounted(() => {
  token = null;
});

function errorText(code: string) {
  if (code === "offline") return t("brainstormingReferences.offline");
  if (code === "reference_history_limit") return t("brainstormingReferences.historyLimit");
  if (code === "reference_limit") return t("brainstormingReferences.referenceLimit");
  if (code === "reference_exists") return t("brainstormingReferences.alreadyLinked");
  if (code.startsWith("stale")) return t("brainstormingReferences.stale");
  return t("brainstormingReferences.error");
}

function date(value: string) {
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime())
    ? value
    : new Intl.DateTimeFormat(locale.value, {
        dateStyle: "medium",
        timeStyle: "short",
      }).format(parsed);
}

function request(action: string, payload: Record<string, unknown> = {}, key?: string) {
  if (pending.value) return;
  const at = Symbol();
  const context = `${epoch}:${sessionId}:${state.context}`;
  token = at;
  pending.value = key ?? action;
  failure.value = null;
  if (key && !requestKeys.has(key)) requestKeys.set(key, crypto.randomUUID());
  const finish = (code: string | null) => {
    if (token !== at || context !== `${epoch}:${sessionId}:${state.context}`) return;
    token = null;
    pending.value = null;
    failure.value = code;
    if (!code) {
      if (key) requestKeys.delete(key);
      confirmation.value = null;
    }
  };
  live.pushEvent(
    `references_${action}`,
    {
      ...payload,
      epoch,
      session_id: sessionId,
      reference_context: state.context,
      ...(key ? { request_key: requestKeys.get(key) } : {}),
    },
    (reply) => finish(reply?.status === "ok" ? null : String(reply?.code ?? "unavailable")),
    () => finish("offline"),
  );
}

function search() {
  request("search", { type: type.value, search: query.value });
}

function linked(target: ReferenceTarget) {
  return state.items.some(
    (item) =>
      item.targetType === target.type &&
      item.targetId === target.id &&
      item.relation === relation.value,
  );
}

function add(target: ReferenceTarget) {
  if (!state.canEdit || linked(target)) return;
  request(
    "add",
    {
      target_type: target.type,
      target_id: target.id,
      relation: relation.value,
    },
    `add:${target.type}:${target.id}:${relation.value}`,
  );
}

function confirm() {
  const selected = confirmation.value;
  if (!selected || !state.canEdit) return;
  request(
    selected.action,
    {
      reference_id: selected.reference.id,
      version: selected.reference.version,
    },
    `${selected.action}:${selected.reference.id}:${selected.reference.version}`,
  );
}
</script>

<template>
  <Sidebar
    v-if="state.open"
    side="right"
    :open="state.open"
    @close="!confirmation && request('close')"
  >
    <template #header>
      <div class="flex items-center justify-between gap-2 py-2.5">
        <div class="flex min-w-0 items-center gap-2 text-sm font-medium">
          <Link2 class="size-4 shrink-0" />
          <span>{{
            t(
              state.ideaId
                ? "brainstormingReferences.ideaReferences"
                : "brainstormingReferences.sessionReferences",
            )
          }}</span>
        </div>
        <Button
          id="brainstorming-references-close"
          variant="ghost"
          size="icon-sm"
          :aria-label="t('brainstormingReferences.close')"
          :disabled="!!pending"
          @click="request('close')"
          ><X class="size-4"
        /></Button>
      </div>
    </template>
    <div class="space-y-4" :aria-busy="!!pending">
      <p class="text-xs text-muted-foreground">{{ t("brainstormingReferences.help") }}</p>
      <p class="rounded-md border border-border bg-muted/40 p-2 text-xs text-muted-foreground">
        {{ t("brainstormingReferences.overviewHelp") }}
      </p>
      <p v-if="notice" role="alert" class="text-xs text-destructive">{{ errorText(notice) }}</p>
      <p v-if="!state.canEdit" class="text-xs text-muted-foreground">
        {{ t("brainstormingReferences.readOnly") }}
      </p>
      <form
        v-if="state.canEdit"
        id="brainstorming-reference-search-form"
        class="space-y-2"
        @submit.prevent="search"
      >
        <div class="grid grid-cols-2 gap-2">
          <div class="space-y-1">
            <label for="brainstorming-reference-type" class="text-xs font-medium">{{
              t("brainstormingReferences.type")
            }}</label>
            <Select v-model="type" :disabled="!!pending">
              <SelectTrigger id="brainstorming-reference-type" class="w-full"
                ><SelectValue
              /></SelectTrigger>
              <SelectContent
                ><SelectItem v-for="item in targetTypes" :key="item" :value="item">{{
                  t(`brainstormingReferences.types.${item}`)
                }}</SelectItem></SelectContent
              >
            </Select>
          </div>
          <div class="space-y-1">
            <label for="brainstorming-reference-relation" class="text-xs font-medium">{{
              t("brainstormingReferences.relation")
            }}</label>
            <Select v-model="relation" :disabled="!!pending">
              <SelectTrigger id="brainstorming-reference-relation" class="w-full"
                ><SelectValue
              /></SelectTrigger>
              <SelectContent
                ><SelectItem v-for="item in relations" :key="item" :value="item">{{
                  t(`brainstormingReferences.relations.${item}`)
                }}</SelectItem></SelectContent
              >
            </Select>
          </div>
        </div>
        <label for="brainstorming-reference-query" class="sr-only">{{
          t("brainstormingReferences.search")
        }}</label>
        <div class="flex gap-1.5">
          <Input
            id="brainstorming-reference-query"
            v-model="query"
            :placeholder="t('brainstormingReferences.searchPlaceholder')"
            :maxlength="200"
            :disabled="!!pending"
          />
          <Button
            id="brainstorming-reference-search"
            type="submit"
            variant="outline"
            size="icon"
            :disabled="!!pending"
            :aria-label="t('brainstormingReferences.find')"
            ><Loader2 v-if="pending === 'search'" class="size-4 animate-spin" /><Search
              v-else
              class="size-4"
          /></Button>
        </div>
        <ul
          v-if="results.length"
          class="max-h-56 space-y-1 overflow-y-auto rounded-lg border border-border p-1"
        >
          <li
            v-for="target in results"
            :key="`${target.type}:${target.id}`"
            class="flex items-center gap-2 rounded-md p-2 hover:bg-muted/50"
          >
            <span class="min-w-0 flex-1 break-words text-xs">{{ target.name }}</span>
            <Button
              :id="`brainstorming-reference-add-${target.type}-${target.id}`"
              size="sm"
              variant="ghost"
              :disabled="!!pending || linked(target)"
              @click="add(target)"
            >
              <Check v-if="linked(target)" class="size-3.5" /><Link2 v-else class="size-3.5" />{{
                t(linked(target) ? "brainstormingReferences.linked" : "brainstormingReferences.add")
              }}
            </Button>
          </li>
        </ul>
        <p v-else-if="state.searched" class="text-xs text-muted-foreground">
          {{ t("brainstormingReferences.noResults") }}
        </p>
      </form>
      <div class="flex items-center justify-between gap-2 border-t border-border pt-3">
        <span class="text-xs font-medium">{{ t("brainstormingReferences.title") }}</span>
        <Button
          id="brainstorming-references-reload"
          variant="ghost"
          size="icon-sm"
          :disabled="!!pending"
          :aria-label="t('brainstormingReferences.reload')"
          @click="request('reload')"
          ><RefreshCw class="size-3.5"
        /></Button>
      </div>
      <div
        v-if="!state.items.length"
        class="space-y-1 rounded-lg border border-dashed border-border px-3 py-5 text-center"
      >
        <p class="text-sm">{{ t("brainstormingReferences.empty") }}</p>
        <p class="text-xs text-muted-foreground">{{ t("brainstormingReferences.emptyHelp") }}</p>
      </div>
      <article
        v-for="reference in state.items"
        :id="`brainstorming-reference-${reference.id}`"
        :key="reference.id"
        class="space-y-3 rounded-lg border border-border p-3"
      >
        <div class="space-y-1">
          <div class="flex flex-wrap gap-x-2 text-[10px] text-muted-foreground">
            <span>{{ t(`brainstormingReferences.types.${reference.targetType}`) }}</span>
            <span>{{ t(`brainstormingReferences.relations.${reference.relation}`) }}</span>
          </div>
          <h3 class="break-words text-sm font-medium">
            {{ reference.current?.name ?? t("brainstormingReferences.unavailable") }}
          </h3>
          <p
            class="text-xs"
            :class="
              reference.status === 'changed'
                ? 'text-amber-700 dark:text-amber-400'
                : 'text-muted-foreground'
            "
          >
            {{
              t(
                `brainstormingReferences.${reference.status === "current" ? "unchanged" : reference.status}`,
              )
            }}
          </p>
        </div>
        <p v-if="reference.status === 'unavailable'" class="text-xs text-muted-foreground">
          {{ t("brainstormingReferences.unavailableHelp") }}
        </p>
        <template v-else>
          <details v-if="reference.base" class="rounded-md bg-muted/40 p-2">
            <summary class="cursor-pointer text-xs font-medium">
              {{ t("brainstormingReferences.base") }}
            </summary>
            <ReferenceOverview :overview="reference.base" class="mt-2" />
            <p v-if="reference.capturedAt" class="mt-2 text-[10px] text-muted-foreground">
              {{ t("brainstormingReferences.capturedAt", { date: date(reference.capturedAt) }) }}
            </p>
          </details>
          <details v-if="reference.current" class="rounded-md border border-border p-2">
            <summary class="cursor-pointer text-xs font-medium">
              {{ t("brainstormingReferences.current") }}
            </summary>
            <ReferenceOverview :overview="reference.current" class="mt-2" />
          </details>
          <LiveLink
            v-if="reference.current?.href"
            :to="reference.current.href"
            class="inline-flex items-center gap-1 text-xs text-primary hover:underline"
            ><ArrowUpRight class="size-3.5" />{{ t("brainstormingReferences.open") }}</LiveLink
          >
        </template>
        <div class="flex flex-wrap items-center gap-1 border-t border-border pt-2">
          <Button
            v-if="state.canEdit && reference.status === 'changed'"
            :id="`brainstorming-reference-refresh-${reference.id}`"
            variant="ghost"
            size="sm"
            :disabled="!!pending"
            @click="confirmation = { action: 'refresh', reference }"
            ><RefreshCw class="size-3.5" />{{ t("brainstormingReferences.refresh") }}</Button
          >
          <Button
            v-if="reference.status !== 'unavailable'"
            :id="`brainstorming-reference-history-${reference.id}`"
            variant="ghost"
            size="icon-sm"
            :disabled="!!pending"
            :aria-label="t('brainstormingReferences.history')"
            @click="request('history', { reference_id: reference.id })"
            ><History class="size-3.5"
          /></Button>
          <Button
            v-if="state.canEdit"
            :id="`brainstorming-reference-remove-${reference.id}`"
            variant="ghost"
            size="icon-sm"
            class="ml-auto text-muted-foreground hover:text-destructive"
            :disabled="!!pending"
            :aria-label="t('brainstormingReferences.remove')"
            @click="confirmation = { action: 'remove', reference }"
            ><Unlink class="size-3.5"
          /></Button>
        </div>
        <div
          v-if="state.historyReferenceId === reference.id && reference.status !== 'unavailable'"
          class="space-y-2 border-t border-border pt-2"
        >
          <p class="text-xs font-medium">{{ t("brainstormingReferences.history") }}</p>
          <p class="text-[10px] text-muted-foreground">
            {{ t("brainstormingReferences.historyHelp") }}
          </p>
          <details
            v-for="entry in state.history"
            :key="entry.number"
            class="rounded-md bg-muted/40 p-2"
          >
            <summary class="cursor-pointer text-xs">
              {{ t("brainstormingReferences.version", { number: entry.number }) }} ·
              {{ date(entry.insertedAt) }}
            </summary>
            <ReferenceOverview v-if="entry.context" :overview="entry.context" class="mt-2" />
          </details>
        </div>
      </article>
      <Button
        v-if="state.nextCursor"
        id="brainstorming-reference-load-more"
        variant="outline"
        size="sm"
        class="w-full"
        :disabled="!!pending"
        @click="request('load_more')"
        >{{ t("brainstormingReferences.loadMore") }}</Button
      >
    </div>
  </Sidebar>
  <ConfirmDialog
    v-model:open="confirmationOpen"
    :title="
      t(
        `brainstormingReferences.${confirmation?.action === 'remove' ? 'removeTitle' : 'refreshTitle'}`,
      )
    "
    :description="
      t(
        `brainstormingReferences.${confirmation?.action === 'remove' ? 'removeHelp' : 'refreshHelp'}`,
      )
    "
    :confirm-text="
      t(`brainstormingReferences.${confirmation?.action === 'remove' ? 'remove' : 'refresh'}`)
    "
    :cancel-text="t('brainstormingReferences.cancel')"
    :variant="confirmation?.action === 'remove' ? 'destructive' : 'default'"
    :pending="!!pending"
    :close-on-confirm="false"
    :error="failure ? errorText(failure) : undefined"
    @confirm="confirm"
  />
</template>
