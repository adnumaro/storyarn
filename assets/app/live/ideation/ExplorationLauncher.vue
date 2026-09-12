<script setup lang="ts">
import { computed, nextTick, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import {
  ArrowUpRight,
  Archive,
  Check,
  Lightbulb,
  Link2,
  Loader2,
  Plus,
  Search,
  X,
} from "@lucide/vue";
import { Button } from "@components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog";
import { Input } from "@components/ui/input";
import { Textarea } from "@components/ui/textarea";
import ReferenceOverview from "./ReferenceOverview.vue";
import type { ExplorationLauncherState, ExplorationSession } from "./explorationTypes";
import { useExplorationRequests } from "./useExplorationRequests";

const {
  state,
  sourceKey,
  enabled = true,
  compact = false,
} = defineProps<{
  state: ExplorationLauncherState;
  sourceKey: string;
  enabled?: boolean;
  compact?: boolean;
}>();

const { t } = useI18n();
const mode = ref<"create" | "link">("create");
const title = ref("");
const objective = ref("");
const query = ref("");
const launcherButton = ref<InstanceType<typeof Button> | null>(null);
const { pending, failure, request } = useExplorationRequests({
  state: () => state,
  sourceKey: () => sourceKey,
  enabled: () => enabled,
});
const notice = computed(() => failure.value ?? state.error);
const canCreate = computed(() => state.canEdit && !!state.target && !!title.value.trim());
const launchLabel = computed(() =>
  t(state.canEdit ? "brainstormingExplorations.launch" : "brainstormingExplorations.title"),
);

function resetForm() {
  mode.value = "create";
  title.value = state.target
    ? t("brainstormingExplorations.defaultTitle", { name: state.target.name }).slice(0, 160)
    : "";
  objective.value = "";
  query.value = "";
}

watch([() => sourceKey, () => state.open, () => enabled], resetForm, { immediate: true });

function errorText(code: string) {
  if (code === "offline") return t("brainstormingExplorations.offline");
  if (code.startsWith("stale")) return t("brainstormingExplorations.stale");
  if (code === "reference_limit") return t("brainstormingReferences.referenceLimit");
  if (code === "session_archived") return t("brainstormingExplorations.archivedHelp");
  return t("brainstormingExplorations.error");
}

function setOpen(open: boolean) {
  request(open ? "open" : "close");
}

async function restoreLauncherFocus(event: Event) {
  event.preventDefault();
  await nextTick();
  const element = launcherButton.value?.$el;
  if (element instanceof HTMLButtonElement && element.isConnected) element.focus();
}

function create() {
  if (!canCreate.value) return;
  const content = { title: title.value.trim(), objective: objective.value.trim() };
  request("create", content, `create:${JSON.stringify(content)}`);
}

function linked(session: ExplorationSession) {
  return state.linked.some((item) => item.id === session.id);
}

function link(session: ExplorationSession) {
  if (!state.canEdit || !state.target || session.status !== "open" || linked(session)) return;
  request("link", { session_id: session.id }, `link:${session.id}`);
}
</script>

<template>
  <template v-if="enabled">
    <Button
      ref="launcherButton"
      id="explore-changes"
      :variant="compact ? 'ghost' : 'outline'"
      :size="compact ? 'icon-sm' : 'sm'"
      class="shrink-0 gap-1.5 text-xs"
      :disabled="!!pending"
      :aria-label="launchLabel"
      :title="launchLabel"
      aria-haspopup="dialog"
      :aria-expanded="state.open"
      @click="setOpen(true)"
    >
      <Loader2 v-if="pending === 'open'" class="size-3.5 animate-spin" />
      <Lightbulb v-else class="size-3.5" />
      <span :class="compact ? 'sr-only' : ''">{{ launchLabel }}</span>
    </Button>
    <p v-if="notice && !state.open" role="alert" class="text-xs text-destructive">
      {{ errorText(notice) }}
    </p>
    <Dialog :open="state.open" @update:open="setOpen">
      <DialogContent
        id="exploration-dialog"
        class="max-h-[85dvh] overflow-y-auto sm:max-w-3xl"
        @escape-key-down="pending && $event.preventDefault()"
        @interact-outside="pending && $event.preventDefault()"
        @close-auto-focus="restoreLauncherFocus"
      >
        <DialogHeader class="pr-7">
          <DialogTitle class="flex items-center gap-2">
            <Lightbulb class="size-5 text-primary" />
            {{ t("brainstormingExplorations.title") }}
          </DialogTitle>
          <DialogDescription>{{ t("brainstormingExplorations.description") }}</DialogDescription>
        </DialogHeader>
        <Button
          id="exploration-close"
          variant="ghost"
          size="icon-sm"
          class="absolute right-4 top-4"
          :aria-label="t('brainstormingExplorations.close')"
          :disabled="!!pending"
          @click="setOpen(false)"
          ><X class="size-4"
        /></Button>

        <p
          v-if="notice"
          role="alert"
          class="rounded-md bg-destructive/10 p-3 text-sm text-destructive"
        >
          {{ errorText(notice) }}
        </p>
        <div
          class="grid gap-5 sm:grid-cols-[minmax(0,0.8fr)_minmax(0,1.2fr)]"
          :aria-busy="!!pending"
        >
          <aside class="min-w-0 space-y-3 rounded-lg border border-border bg-muted/30 p-4">
            <h3 class="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
              {{ t("brainstormingExplorations.context") }}
            </h3>
            <template v-if="state.target">
              <span
                class="inline-flex rounded-md border border-border bg-background px-2 py-0.5 text-[10px] text-muted-foreground"
              >
                {{ t(`brainstormingReferences.types.${state.target.type}`) }}
              </span>
              <ReferenceOverview id="exploration-context-preview" :overview="state.target" />
              <p class="border-t border-border pt-3 text-xs leading-relaxed text-muted-foreground">
                {{ t("brainstormingExplorations.contextHelp") }}
              </p>
            </template>
            <p v-else class="text-sm text-muted-foreground">
              {{ t("brainstormingExplorations.unavailable") }}
            </p>
          </aside>

          <div class="min-w-0 space-y-5">
            <section aria-labelledby="exploration-linked-heading" class="space-y-2">
              <h3 id="exploration-linked-heading" class="text-sm font-medium">
                {{ t("brainstormingExplorations.linkedTitle") }}
              </h3>
              <ul v-if="state.linked.length" class="max-h-52 space-y-1 overflow-y-auto">
                <li
                  v-for="session in state.linked"
                  :key="session.id"
                  class="flex items-center gap-2 rounded-lg border border-border px-3 py-2"
                >
                  <div class="min-w-0 flex-1 space-y-1">
                    <p class="break-words text-sm font-medium">{{ session.title }}</p>
                    <p
                      v-if="session.status === 'archived'"
                      class="flex items-center gap-1 text-xs text-muted-foreground"
                    >
                      <Archive class="size-3" />{{ t("brainstormingExplorations.archived") }}
                    </p>
                    <p
                      v-if="session.contextStatus && session.contextStatus !== 'current'"
                      class="text-xs text-muted-foreground"
                    >
                      {{ t(`brainstormingExplorations.contextStatus.${session.contextStatus}`) }}
                    </p>
                  </div>
                  <Button
                    :id="`exploration-resume-${session.id}`"
                    size="sm"
                    variant="ghost"
                    :disabled="!!pending"
                    @click="request('resume', { session_id: session.id })"
                  >
                    {{
                      t(
                        session.status === "archived"
                          ? "brainstormingExplorations.view"
                          : "brainstormingExplorations.resume",
                      )
                    }}<ArrowUpRight class="size-3.5" />
                  </Button>
                </li>
              </ul>
              <p
                v-else
                class="rounded-lg border border-dashed border-border px-3 py-4 text-sm text-muted-foreground"
              >
                {{ t("brainstormingExplorations.empty") }}
              </p>
              <div
                v-if="state.linkedPrevious || state.linkedNext !== null"
                class="flex justify-between gap-2"
              >
                <Button
                  v-if="state.linkedPrevious"
                  id="exploration-linked-previous"
                  variant="ghost"
                  size="sm"
                  :disabled="!!pending"
                  @click="request('load_previous', { list: 'linked', cursor: state.linkedCursor })"
                  >{{ t("brainstormingExplorations.previous") }}</Button
                >
                <Button
                  v-if="state.linkedNext !== null"
                  id="exploration-linked-more"
                  variant="ghost"
                  size="sm"
                  class="ml-auto"
                  :disabled="!!pending"
                  @click="request('load_more', { list: 'linked', cursor: state.linkedNext })"
                  >{{ t("brainstormingExplorations.next") }}</Button
                >
              </div>
            </section>

            <section
              v-if="state.canEdit && state.target"
              class="space-y-4 border-t border-border pt-4"
            >
              <div
                class="flex gap-1 rounded-lg bg-muted p-1"
                :aria-label="t('brainstormingExplorations.chooseAction')"
                role="group"
              >
                <Button
                  id="exploration-new"
                  size="sm"
                  :variant="mode === 'create' ? 'secondary' : 'ghost'"
                  class="flex-1"
                  :aria-pressed="mode === 'create'"
                  :disabled="!!pending"
                  @click="mode = 'create'"
                  ><Plus class="size-3.5" />{{ t("brainstormingExplorations.new") }}</Button
                >
                <Button
                  id="exploration-link-existing"
                  size="sm"
                  :variant="mode === 'link' ? 'secondary' : 'ghost'"
                  class="flex-1"
                  :aria-pressed="mode === 'link'"
                  :disabled="!!pending"
                  @click="mode = 'link'"
                  ><Link2 class="size-3.5" />{{ t("brainstormingExplorations.existing") }}</Button
                >
              </div>

              <form
                v-if="mode === 'create'"
                id="exploration-create-form"
                class="space-y-3"
                @submit.prevent="create"
              >
                <div class="space-y-1.5">
                  <label for="exploration-title" class="text-xs font-medium">{{
                    t("brainstormingExplorations.name")
                  }}</label>
                  <Input
                    id="exploration-title"
                    v-model="title"
                    :maxlength="160"
                    required
                    :disabled="!!pending"
                  />
                </div>
                <div class="space-y-1.5">
                  <label for="exploration-objective" class="text-xs font-medium"
                    >{{ t("brainstormingExplorations.objective") }}
                    <span class="font-normal text-muted-foreground">{{
                      t("brainstormingExplorations.optional")
                    }}</span></label
                  >
                  <Textarea
                    id="exploration-objective"
                    v-model="objective"
                    :placeholder="t('brainstormingExplorations.objectivePlaceholder')"
                    :maxlength="4000"
                    :rows="3"
                    :disabled="!!pending"
                  />
                </div>
                <Button
                  id="exploration-create"
                  type="submit"
                  class="w-full"
                  :disabled="!!pending || !canCreate"
                  ><Loader2
                    v-if="pending?.startsWith('create:')"
                    class="size-4 animate-spin"
                  /><Plus v-else class="size-4" />{{
                    t("brainstormingExplorations.create")
                  }}</Button
                >
              </form>

              <div v-else class="space-y-3">
                <form
                  id="exploration-search-form"
                  class="flex gap-2"
                  @submit.prevent="request('search', { search: query })"
                >
                  <label for="exploration-search-query" class="sr-only">{{
                    t("brainstormingExplorations.search")
                  }}</label>
                  <Input
                    id="exploration-search-query"
                    v-model="query"
                    :maxlength="200"
                    :placeholder="t('brainstormingExplorations.searchPlaceholder')"
                    :disabled="!!pending"
                  />
                  <Button
                    id="exploration-search"
                    type="submit"
                    size="icon"
                    variant="outline"
                    :disabled="!!pending"
                    :aria-label="t('brainstormingExplorations.search')"
                    ><Loader2 v-if="pending === 'search'" class="size-4 animate-spin" /><Search
                      v-else
                      class="size-4"
                  /></Button>
                </form>
                <p class="text-xs leading-relaxed text-muted-foreground">
                  {{ t("brainstormingExplorations.linkHelp") }}
                </p>
                <ul v-if="state.available.length" class="max-h-52 space-y-1 overflow-y-auto">
                  <li
                    v-for="session in state.available"
                    :key="session.id"
                    class="flex items-center gap-2 rounded-lg border border-border px-3 py-2"
                  >
                    <span class="min-w-0 flex-1 break-words text-sm">{{ session.title }}</span>
                    <Button
                      :id="`exploration-link-${session.id}`"
                      size="sm"
                      variant="ghost"
                      :disabled="!!pending || linked(session) || session.status !== 'open'"
                      @click="link(session)"
                      ><Check v-if="linked(session)" class="size-3.5" /><Link2
                        v-else
                        class="size-3.5"
                      />{{
                        t(
                          linked(session)
                            ? "brainstormingExplorations.linked"
                            : "brainstormingExplorations.link",
                        )
                      }}</Button
                    >
                  </li>
                </ul>
                <p v-else class="py-2 text-sm text-muted-foreground">
                  {{ t("brainstormingExplorations.noResults") }}
                </p>
                <div
                  v-if="state.availablePrevious || state.availableNext !== null"
                  class="flex justify-between gap-2"
                >
                  <Button
                    v-if="state.availablePrevious"
                    id="exploration-available-previous"
                    size="sm"
                    variant="ghost"
                    :disabled="!!pending"
                    @click="
                      request('load_previous', { list: 'available', cursor: state.availableCursor })
                    "
                    >{{ t("brainstormingExplorations.previous") }}</Button
                  >
                  <Button
                    v-if="state.availableNext !== null"
                    id="exploration-available-more"
                    size="sm"
                    variant="ghost"
                    class="ml-auto"
                    :disabled="!!pending"
                    @click="
                      request('load_more', { list: 'available', cursor: state.availableNext })
                    "
                    >{{ t("brainstormingExplorations.next") }}</Button
                  >
                </div>
              </div>
            </section>
            <p v-else-if="!state.canEdit" class="text-xs text-muted-foreground">
              {{ t("brainstormingExplorations.readOnly") }}
            </p>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  </template>
</template>
