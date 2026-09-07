<script setup lang="ts">
import { computed, onBeforeUnmount, ref } from "vue";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
import IdeaEditor from "./IdeaEditor.vue";
import BoardSelect from "./BoardSelect.vue";
import { useBoardText } from "../composables/useBoardText";
import type { BoardContext, Idea, IdeaContent, Request, Session } from "../types";

const { session, context, request, source } = defineProps<{
  session: Session;
  context: BoardContext;
  request: Request;
  source?: Idea;
}>();
const emit = defineEmits<{ close: []; created: [idea: Idea]; preserve: [content: IdeaContent] }>();
const { t, error, options } = useBoardText();
// Freeze the configuration the user actually saw, even while props refresh.
const version = session.configuration_version;
const assisted = session.configuration.publication_policy === "facilitator_assisted";
const title = ref(source?.title ?? "");
const body = ref(source?.body ?? "");
const visibility = ref<string>(session.configuration.default_visibility);
const consent = ref(false);
const pending = ref(false);
const failure = ref<string | null>(null);
let attempt: Record<string, unknown> | null = null;
let completed = false;
let disposed = false;
const locked = computed(() => pending.value || failure.value === "offline");
async function submit() {
  if (pending.value) return;
  attempt ??= {
    title: title.value,
    body: body.value,
    state: "active",
    visibility: visibility.value,
    publication_consent: consent.value ? "facilitator_assisted" : "author_only",
    configuration_version: version,
    request_key: crypto.randomUUID(),
    ...(source ? { idea_id: source.id, revision: source.revision } : {}),
  };
  pending.value = true;
  const reply = await request<Idea>(source ? "derive_idea" : "create_idea", attempt, context);
  if (disposed) return;
  pending.value = false;
  if (reply.status === "ok") {
    completed = true;
    emit("created", reply.value);
  } else {
    failure.value = reply.status === "error" ? reply.code : "unavailable";
    if (failure.value !== "offline") attempt = null;
  }
}
onBeforeUnmount(() => {
  disposed = true;
  if (!completed && (title.value || body.value))
    emit("preserve", { title: title.value, body: body.value, state: "active" });
});
</script>
<template>
  <Dialog :open="true" @update:open="!$event && !pending && emit('close')">
    <DialogContent class="max-h-[90dvh] overflow-y-auto sm:max-w-xl" @interact-outside.prevent>
      <DialogHeader
        ><DialogTitle>{{ t(source ? "ideation.derive" : "ideation.newIdea") }}</DialogTitle
        ><DialogDescription>{{ t("ideation.newIdeaHelp") }}</DialogDescription></DialogHeader
      >
      <form id="idea-composer" class="space-y-4" @submit.prevent="submit">
        <label for="new-idea-title" class="block text-sm font-medium">{{
          t("ideation.ideaTitle")
        }}</label>
        <Input
          id="new-idea-title"
          v-model="title"
          :maxlength="160"
          :disabled="locked"
          :placeholder="t('ideation.titleOptional')"
        />
        <IdeaEditor
          :value="body"
          :readonly="locked"
          :label="t('ideation.body')"
          @change="body = $event"
          @save="submit"
        />
        <BoardSelect
          v-model="visibility"
          :disabled="locked"
          :label="t('ideation.visibility')"
          :options="options(['private', 'shared'])"
        />
        <p class="text-xs text-muted-foreground">
          {{ t(visibility === "shared" ? "ideation.createSharedHelp" : "ideation.privateHelp") }}
        </p>
        <label v-if="assisted" class="flex items-start gap-2 text-sm"
          ><input
            v-model="consent"
            type="checkbox"
            :disabled="locked"
            class="mt-1 accent-primary"
          /><span
            >{{ t("ideation.assistedConsent")
            }}<span class="mt-1 block text-xs text-muted-foreground">{{
              t("ideation.assistedConsentHelp")
            }}</span></span
          ></label
        >
        <p v-if="failure" role="alert" class="text-sm text-destructive">{{ error(failure) }}</p>
        <DialogFooter
          ><Button type="button" variant="outline" :disabled="pending" @click="emit('close')">{{
            t("ideation.close")
          }}</Button
          ><Button type="submit" :disabled="pending">{{
            t(failure === "offline" ? "ideation.retry" : "ideation.createIdea")
          }}</Button></DialogFooter
        >
      </form>
    </DialogContent>
  </Dialog>
</template>
