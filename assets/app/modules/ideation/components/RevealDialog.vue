<script setup lang="ts">
import { onBeforeUnmount, ref } from "vue";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog";
import { Button } from "@components/ui/button";
import { useBoardText } from "../composables/useBoardText";
import type { BoardContext, Idea, Request, Reveal } from "../types";

const { request, context, idea } = defineProps<{
  request: Request;
  context: BoardContext;
  idea?: Idea;
}>();
const emit = defineEmits<{ close: []; published: [] }>();
const { t, error } = useBoardText();
const includeDiscarded = ref(false);
const operation = ref<Reveal | null>(null);
const pending = ref(false);
const failure = ref<string | null>(null);
let selection: Record<string, unknown> | null = null;
let disposed = false;
onBeforeUnmount(() => {
  disposed = true;
});
async function submit() {
  if (pending.value) return;
  pending.value = true;
  selection ??= {
    request_key: crypto.randomUUID(),
    ...(idea
      ? { targets: [{ idea_id: idea.id, revision: idea.revision }] }
      : { mode: "eligible", include_discarded: includeDiscarded.value }),
  };
  const wasPrepared = operation.value !== null;
  const reply = operation.value
    ? await request<Reveal>("reveal_ideas", { operation_id: operation.value.id }, context)
    : await request<Reveal>("prepare_reveal", selection, context);
  if (disposed) return;
  pending.value = false;
  if (reply.status === "ok") {
    failure.value = null;
    operation.value = reply.value;
    if (wasPrepared) emit("published");
  } else failure.value = reply.status === "error" ? reply.code : "unavailable";
}
</script>
<template>
  <Dialog :open="true" @update:open="!$event && !pending && emit('close')">
    <DialogContent @interact-outside.prevent>
      <DialogHeader
        ><DialogTitle>{{
          t(idea ? "ideation.publishRevision" : "ideation.assistedReveal")
        }}</DialogTitle
        ><DialogDescription>{{
          t(idea ? "ideation.publishHelp" : "ideation.revealHelp")
        }}</DialogDescription></DialogHeader
      >
      <template v-if="!operation">
        <p v-if="idea" class="text-sm">
          {{ idea.title || t("ideation.untitled") }} ·
          {{ t("ideation.revision", { number: idea.revision }) }}
        </p>
        <label v-else class="flex items-center gap-2 text-sm"
          ><input
            v-model="includeDiscarded"
            type="checkbox"
            :disabled="pending || selection !== null"
            class="accent-primary"
          />{{ t("ideation.includeDiscarded") }}</label
        >
      </template>
      <template v-else
        ><p class="text-lg font-semibold" role="status">
          {{ t("ideation.revealCount", { count: operation.count }) }}
        </p>
        <p class="text-sm text-muted-foreground">{{ t("ideation.frozenRevealHelp") }}</p></template
      >
      <p v-if="failure" role="alert" class="text-sm text-destructive">{{ error(failure) }}</p>
      <DialogFooter
        ><Button variant="outline" :disabled="pending" @click="emit('close')">{{
          t("ideation.cancel")
        }}</Button
        ><Button :disabled="pending || operation?.count === 0" @click="submit">{{
          t(operation ? "ideation.confirmPublish" : "ideation.prepareReveal")
        }}</Button></DialogFooter
      >
    </DialogContent>
  </Dialog>
</template>
