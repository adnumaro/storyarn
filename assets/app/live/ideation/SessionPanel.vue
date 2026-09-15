<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from "vue";
import { Settings2, X } from "@lucide/vue";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
import { Textarea } from "@components/ui/textarea";
import Sidebar from "@shell/Sidebar.vue";
import { useLive } from "@shared/composables/useLive";
import { BoardSelect, useBoardText } from "@modules/ideation";
import type { HistoryPage, Member, Session, SessionRevision } from "@modules/ideation";

// The session's details and settings live in the right dock, next to
// decisions and references: title, purpose and context, who facilitates and
// who owns decisions, whether new contributions are open, archiving, history.
const { session, epoch, members, canManage, open } = defineProps<{
  session: Session;
  epoch: string;
  members: Member[];
  canManage: boolean;
  open: boolean;
}>();
const { t, error, member } = useBoardText();
const live = useLive();
const title = ref(session.title);
const objective = ref(session.objective ?? "");
const description = ref(session.context ?? "");
const facilitator = ref(String(session.facilitator_id ?? ""));
const decisionOwner = ref(String(session.decision_owner_id ?? ""));
const pending = ref(false);
const failure = ref<string | null>(null);
const history = ref<SessionRevision[]>([]);
const historyOpen = ref(false);
const historyNext = ref<number | null>(null);
let disposed = false;
onBeforeUnmount(() => {
  disposed = true;
});
// A saved change comes back through the board; the fields follow it.
watch(
  () => session.revision,
  () => {
    title.value = session.title;
    objective.value = session.objective ?? "";
    description.value = session.context ?? "";
    facilitator.value = String(session.facilitator_id ?? "");
    decisionOwner.value = String(session.decision_owner_id ?? "");
  },
);
const people = computed(() =>
  members.map((person) => ({ value: String(person.id), label: person.display_name })),
);
type Reply<T> = { status: "ok"; value: T } | { status: "error"; code: string };
function request<T>(event: string, payload: Record<string, unknown>): Promise<Reply<T>> {
  return new Promise((resolve) => {
    live.pushEvent(
      event,
      { ...payload, epoch, session_id: session.id },
      (reply) =>
        resolve(
          reply?.status === "ok"
            ? { status: "ok", value: reply.value as T }
            : { status: "error", code: String(reply?.code ?? "unavailable") },
        ),
      () => resolve({ status: "error", code: "offline" }),
    );
  });
}
async function mutate(event: string, payload: Record<string, unknown>) {
  if (pending.value) return;
  pending.value = true;
  failure.value = null;
  const reply = await request(event, { revision: session.revision, ...payload });
  if (disposed) return;
  pending.value = false;
  if (reply.status === "error") failure.value = reply.code;
}
function save() {
  void mutate("update_session", {
    title: title.value,
    objective: objective.value,
    context: description.value,
  });
}
function assign() {
  const payload: Record<string, unknown> = {};
  if (facilitator.value !== String(session.facilitator_id ?? ""))
    payload.facilitator_id = facilitator.value;
  if (decisionOwner.value !== String(session.decision_owner_id ?? ""))
    payload.decision_owner_id = decisionOwner.value;
  void mutate("assign_responsibilities", payload);
}
async function loadHistory() {
  if (pending.value) return;
  pending.value = true;
  const reply = await request<HistoryPage<SessionRevision>>("session_history", {
    before_id: historyNext.value,
  });
  if (disposed) return;
  pending.value = false;
  historyOpen.value = true;
  if (reply.status === "ok") {
    history.value.push(...reply.value.entries);
    historyNext.value = reply.value.next;
  } else failure.value = reply.code;
}
function close() {
  live.pushEvent("session_panel", { open: false, epoch, session_id: session.id });
}
</script>

<template>
  <Sidebar side="right" :open="open" @close="close">
    <template #header>
      <div class="flex items-center justify-between gap-2 py-2.5">
        <div class="flex min-w-0 items-center gap-2 text-sm font-medium">
          <Settings2 class="size-4 shrink-0" />
          <span class="truncate">{{ t("ideation.sessionSettings") }}</span>
        </div>
        <Button
          id="brainstorming-session-close"
          variant="ghost"
          size="icon-sm"
          :aria-label="t('ideation.sessionSettingsClose')"
          @click="close"
        >
          <X class="size-4" />
        </Button>
      </div>
    </template>
    <div class="space-y-4 p-3 text-sm">
      <p class="text-xs text-muted-foreground">{{ t("ideation.sessionHelp") }}</p>
      <form id="brainstorming-session-form" class="space-y-4" @submit.prevent="save">
        <fieldset class="space-y-4" :disabled="pending || !canManage">
          <div class="space-y-2">
            <label for="session-title" class="text-sm font-medium">{{
              t("ideation.sessionTitle")
            }}</label
            ><Input
              id="session-title"
              v-model="title"
              required
              maxlength="160"
              :placeholder="t('ideation.sessionPlaceholder')"
            />
          </div>
          <div class="space-y-2">
            <label for="session-objective" class="text-sm font-medium">{{
              t("ideation.objective")
            }}</label
            ><Textarea id="session-objective" v-model="objective" :rows="2" />
          </div>
          <div class="space-y-2">
            <label for="session-context" class="text-sm font-medium">{{
              t("ideation.context")
            }}</label
            ><Textarea id="session-context" v-model="description" :rows="2" />
          </div>
        </fieldset>
        <Button v-if="canManage" type="submit" size="sm" :disabled="pending">{{
          t("ideation.save")
        }}</Button>
      </form>
      <section class="space-y-2 border-t pt-4">
        <p
          class="text-xs"
          :class="session.contributions_open ? 'text-muted-foreground' : 'text-foreground'"
        >
          {{
            t(
              session.contributions_open
                ? "ideation.timer.contributionsOpen"
                : "ideation.timer.contributionsClosed",
            )
          }}
        </p>
        <p v-if="!session.contributions_open" class="text-xs text-muted-foreground">
          {{ t("ideation.timer.closedHelp") }}
        </p>
        <Button
          v-if="canManage"
          id="brainstorming-contributions-toggle"
          type="button"
          size="sm"
          variant="outline"
          :disabled="pending"
          @click="mutate('set_contributions_open', { open: !session.contributions_open })"
          >{{
            t(session.contributions_open ? "ideation.timer.closeNow" : "ideation.timer.reopen")
          }}</Button
        >
      </section>
      <section v-if="canManage" class="space-y-3 border-t pt-4">
        <h3 class="text-sm font-semibold">{{ t("ideation.responsibilities") }}</h3>
        <p class="text-xs text-muted-foreground">{{ t("ideation.responsibilitiesHelp") }}</p>
        <label class="block text-sm">{{ t("ideation.facilitator") }}</label
        ><BoardSelect
          v-model="facilitator"
          :disabled="pending"
          :label="t('ideation.facilitator')"
          :options="people"
        />
        <label class="block text-sm">{{ t("ideation.decisionOwner") }}</label
        ><BoardSelect
          v-model="decisionOwner"
          :disabled="pending"
          :label="t('ideation.decisionOwner')"
          :options="people"
        />
        <Button size="sm" variant="outline" :disabled="pending" @click="assign">{{
          t("ideation.assign")
        }}</Button>
        <div class="border-t pt-3">
          <Button
            id="brainstorming-session-archive"
            size="sm"
            variant="outline"
            :disabled="pending"
            @click="mutate(session.status === 'open' ? 'archive_session' : 'reopen_session', {})"
            >{{ t(session.status === "open" ? "ideation.archive" : "ideation.reopen") }}</Button
          >
        </div>
      </section>
      <section class="space-y-3 border-t pt-4">
        <Button
          size="sm"
          variant="ghost"
          :disabled="pending"
          @click="history.length ? (historyOpen = !historyOpen) : loadHistory()"
          >{{ t("ideation.sessionHistory") }}</Button
        >
        <template v-if="historyOpen">
          <details v-for="entry in history" :key="entry.id" class="rounded-lg border p-3 text-sm">
            <summary class="cursor-pointer">
              {{ t("ideation.revision", { number: entry.number }) }} ·
              {{ member(entry.actor_id, members) }}
            </summary>
            <dl class="mt-2 space-y-2 text-xs">
              <dt>{{ t("ideation.sessionTitle") }}</dt>
              <dd>{{ entry.snapshot.title }}</dd>
              <dt>{{ t("ideation.objective") }}</dt>
              <dd>{{ entry.snapshot.objective }}</dd>
              <dt>{{ t("ideation.context") }}</dt>
              <dd>{{ entry.snapshot.context }}</dd>
              <dt>{{ t("ideation.sessionStatus") }}</dt>
              <dd>{{ t(`ideation.${entry.snapshot.status}`) }}</dd>
            </dl>
          </details>
          <Button
            v-if="historyNext !== null"
            size="sm"
            variant="outline"
            :disabled="pending"
            @click="loadHistory"
            >{{ t("ideation.moreHistory") }}</Button
          >
        </template>
      </section>
      <p v-if="failure" role="alert" class="text-sm text-destructive">{{ error(failure) }}</p>
    </div>
  </Sidebar>
</template>
