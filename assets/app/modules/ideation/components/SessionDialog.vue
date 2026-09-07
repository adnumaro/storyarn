<script setup lang="ts">
import { onBeforeUnmount, ref } from "vue";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
import { Textarea } from "@components/ui/textarea";
import BoardSelect from "./BoardSelect.vue";
import { useBoardText } from "../composables/useBoardText";
import type {
  BoardContext,
  Member,
  Request,
  Session,
  SessionRevision,
  HistoryPage,
} from "../types";

const { session, context, request, members, canManage } = defineProps<{
  session?: Session;
  context: BoardContext;
  request: Request;
  members: Member[];
  canManage: boolean;
}>();
const emit = defineEmits<{ close: []; created: [id: number]; changed: [] }>();
const { t, error, options, member } = useBoardText();
const initial = session;
const at = { ...context };
const title = ref(initial?.title ?? "");
const objective = ref(initial?.objective ?? "");
const description = ref(initial?.context ?? "");
const preset = ref("free");
const visibility = ref<string>(initial?.configuration.default_visibility ?? "private");
const policy = ref<string>(initial?.configuration.publication_policy ?? "author_only");
const facilitator = ref(String(initial?.facilitator_id ?? ""));
const decisionOwner = ref(String(initial?.decision_owner_id ?? ""));
const pending = ref(false);
const failure = ref<string | null>(null);
const history = ref<SessionRevision[]>([]);
const historyOpen = ref(false);
const historyNext = ref<number | null>(null);
let disposed = false;
onBeforeUnmount(() => {
  disposed = true;
});

async function mutate(event: string, payload: Record<string, unknown>) {
  if (pending.value || failure.value === "session_creation_unknown") return;
  pending.value = true;
  const reply = await request<{ id: number }>(
    event,
    { revision: initial?.revision, ...payload },
    at,
  );
  if (disposed) return;
  pending.value = false;
  if (reply.status === "ok") {
    if (!initial) emit("created", reply.value.id);
    else emit("changed");
  } else failure.value = reply.status === "error" ? reply.code : "unavailable";
  if (!initial && failure.value === "offline") failure.value = "session_creation_unknown";
}
function save() {
  const payload = { title: title.value, objective: objective.value, context: description.value };
  void mutate(initial ? "update_session" : "create_session", {
    ...payload,
    preset: preset.value,
    configuration: { default_visibility: visibility.value, publication_policy: policy.value },
  });
}
function assign() {
  const payload: Record<string, unknown> = {};
  if (facilitator.value !== String(initial?.facilitator_id ?? ""))
    payload.facilitator_id = facilitator.value;
  if (decisionOwner.value !== String(initial?.decision_owner_id ?? ""))
    payload.decision_owner_id = decisionOwner.value;
  void mutate("assign_responsibilities", payload);
}
async function loadHistory() {
  if (pending.value) return;
  pending.value = true;
  const reply = await request<HistoryPage<SessionRevision>>(
    "session_history",
    { before_id: historyNext.value },
    at,
  );
  if (disposed) return;
  pending.value = false;
  historyOpen.value = true;
  if (reply.status === "ok") {
    history.value.push(...reply.value.entries);
    historyNext.value = reply.value.next;
  } else failure.value = reply.status === "error" ? reply.code : "unavailable";
}
</script>
<template>
  <Dialog :open="true" @update:open="!$event && !pending && emit('close')">
    <DialogContent class="max-h-[90dvh] overflow-y-auto sm:max-w-xl" @interact-outside.prevent>
      <DialogHeader
        ><DialogTitle>{{
          t(initial ? "ideation.sessionSettings" : "ideation.newSession")
        }}</DialogTitle
        ><DialogDescription>{{ t("ideation.sessionHelp") }}</DialogDescription></DialogHeader
      >
      <form id="brainstorming-session-form" class="space-y-4" @submit.prevent="save">
        <fieldset
          class="space-y-4"
          :disabled="pending || !canManage || failure === 'session_creation_unknown'"
        >
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
          <template v-if="!initial"
            ><BoardSelect
              v-model="preset"
              :label="t('ideation.preset')"
              :options="options(['free', 'openPreset', 'assisted'])"
          /></template>
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
          <template v-if="initial">
            <div class="space-y-2">
              <label class="text-sm font-medium">{{ t("ideation.defaultVisibility") }}</label
              ><BoardSelect
                v-model="visibility"
                :label="t('ideation.defaultVisibility')"
                :options="options(['private', 'shared'])"
              />
            </div>
            <div class="space-y-2">
              <label class="text-sm font-medium">{{ t("ideation.publicationPolicy") }}</label
              ><BoardSelect
                v-model="policy"
                :label="t('ideation.publicationPolicy')"
                :options="options(['author_only', 'facilitator_assisted'])"
              />
            </div>
          </template>
        </fieldset>
        <Button
          v-if="canManage"
          type="submit"
          :disabled="pending || failure === 'session_creation_unknown'"
          >{{ t(initial ? "ideation.save" : "ideation.createSession") }}</Button
        >
      </form>
      <section v-if="initial && canManage" class="space-y-3 border-t pt-4">
        <h3 class="text-sm font-semibold">{{ t("ideation.responsibilities") }}</h3>
        <p class="text-xs text-muted-foreground">{{ t("ideation.responsibilitiesHelp") }}</p>
        <label class="block text-sm">{{ t("ideation.facilitator") }}</label
        ><BoardSelect
          v-model="facilitator"
          :disabled="pending"
          :label="t('ideation.facilitator')"
          :options="
            members.map((person) => ({ value: String(person.id), label: person.display_name }))
          "
        />
        <label class="block text-sm">{{ t("ideation.decisionOwner") }}</label
        ><BoardSelect
          v-model="decisionOwner"
          :disabled="pending"
          :label="t('ideation.decisionOwner')"
          :options="
            members.map((person) => ({ value: String(person.id), label: person.display_name }))
          "
        />
        <Button size="sm" variant="outline" :disabled="pending" @click="assign">{{
          t("ideation.assign")
        }}</Button>
        <div class="border-t pt-3">
          <Button
            size="sm"
            variant="outline"
            :disabled="pending"
            @click="mutate(initial.status === 'open' ? 'archive_session' : 'reopen_session', {})"
            >{{ t(initial.status === "open" ? "ideation.archive" : "ideation.reopen") }}</Button
          >
        </div>
      </section>
      <section v-if="initial" class="space-y-3 border-t pt-4">
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
    </DialogContent>
  </Dialog>
</template>
