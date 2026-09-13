<script setup lang="ts">
import { computed, nextTick, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { Plus, Loader2, RefreshCw } from "@lucide/vue";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
import { Textarea } from "@components/ui/textarea";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select";
import DecisionSources from "./DecisionSources.vue";
import DecisionSummary from "./DecisionSummary.vue";
import type {
  DecisionDraftInput,
  DecisionRecord,
  DecisionSource,
  DecisionSourceIdentity,
  DecisionMember,
} from "./decisionTypes";

const { context, draft, sources, members, defaultOwnerId, canAssign, enabled, pending } =
  defineProps<{
    context: string;
    draft: DecisionRecord | null;
    sources: DecisionSource[];
    members: DecisionMember[];
    defaultOwnerId: number | null;
    canAssign: boolean;
    enabled: boolean;
    pending: boolean;
  }>();
const emit = defineEmits<{
  submit: [input: DecisionDraftInput];
  removeSource: [source: DecisionSourceIdentity];
  browseSources: [];
  refreshSources: [];
  dirty: [value: boolean];
}>();
const { t } = useI18n();
const title = ref("");
const conclusion = ref("");
const reason = ref("");
const owner = ref("");
const baseRevision = ref<number | undefined>();
const baseline = ref("");
const titleInput = ref<InstanceType<typeof Input> | null>(null);
const changed = computed(() => draft !== null && draft.revision !== baseRevision.value);
const fingerprint = () =>
  JSON.stringify([
    title.value,
    conclusion.value,
    reason.value,
    owner.value,
    sources.map((source) => [source.type, source.id, source.identity, source.version]),
  ]);
watch(
  () => context,
  async () => {
    const initial = draft ?? {
      title: "",
      conclusion: "",
      reason: "",
      ownerId: defaultOwnerId,
      revision: undefined,
    };
    title.value = initial.title;
    conclusion.value = initial.conclusion;
    reason.value = initial.reason;
    owner.value = String(initial.ownerId ?? "");
    baseRevision.value = initial.revision;
    baseline.value = fingerprint();
    const at = context;
    await nextTick();
    const element = titleInput.value?.$el;
    if (context === at && element instanceof HTMLInputElement && element.isConnected)
      element.focus();
  },
  { immediate: true },
);
watch(fingerprint, (value) => emit("dirty", value !== baseline.value));
const canSave = computed(
  () =>
    enabled &&
    !pending &&
    !changed.value &&
    title.value.trim() &&
    conclusion.value.trim() &&
    reason.value.trim() &&
    Number(owner.value) > 0 &&
    sources.length > 0 &&
    sources.length <= 20 &&
    sources.every((source) => source.available),
);
const ownerName = computed(
  () =>
    members.find((person) => person.id === Number(owner.value))?.display_name ??
    draft?.ownerName ??
    t("brainstormingDecisions.formerMember"),
);
function submit() {
  if (!canSave.value) return;
  emit("submit", {
    title: title.value.trim(),
    conclusion: conclusion.value.trim(),
    reason: reason.value.trim(),
    owner_id: Number(owner.value),
    ...(baseRevision.value !== undefined ? { revision: baseRevision.value } : {}),
  });
}
function useCurrentVersion() {
  if (!draft || pending) return;
  baseRevision.value = draft.revision;
  if (!canAssign) owner.value = String(draft.ownerId ?? "");
}
</script>
<template>
  <div class="space-y-5">
    <details
      v-if="changed && draft"
      id="decision-current-proposal"
      open
      class="rounded-lg border border-amber-400/40 bg-amber-500/5 p-3"
    >
      <summary class="cursor-pointer text-xs font-medium">
        {{ t("brainstormingDecisions.changedProposal") }}
      </summary>
      <p class="my-3 text-xs leading-relaxed text-muted-foreground">
        {{ t("brainstormingDecisions.changedProposalHelp") }}
      </p>
      <DecisionSummary :agreement="draft" />
      <Button
        id="decision-use-current-version"
        class="mt-3 w-full"
        size="sm"
        variant="outline"
        :disabled="pending || !enabled"
        @click="useCurrentVersion"
        >{{ t("brainstormingDecisions.keepMyProposal") }}</Button
      >
    </details>
    <section aria-labelledby="decision-sources-heading" class="space-y-2">
      <div class="flex items-center justify-between gap-2">
        <h3 id="decision-sources-heading" class="text-xs font-medium">
          {{ t("brainstormingDecisions.sourcesCount", { count: sources.length }) }}
        </h3>
        <Button
          id="decision-add-sources"
          variant="ghost"
          size="sm"
          :disabled="pending || !enabled || sources.length >= 20"
          @click="emit('browseSources')"
          ><Plus class="size-3.5" />{{ t("brainstormingDecisions.addSources") }}</Button
        >
      </div>
      <p
        v-if="!sources.length"
        class="rounded-lg border border-dashed p-4 text-center text-xs leading-relaxed text-muted-foreground"
      >
        {{ t("brainstormingDecisions.chooseSources") }}
      </p>
      <DecisionSources
        :sources="sources"
        :editable="enabled"
        :pending="pending"
        @remove="emit('removeSource', $event)"
      />
      <Button
        v-if="sources.some((source) => source.changed && source.currentVersion !== null)"
        id="decision-refresh-sources"
        size="sm"
        variant="outline"
        :disabled="pending || !enabled"
        @click="emit('refreshSources')"
        ><RefreshCw class="size-3.5" />{{ t("brainstormingDecisions.refreshSources") }}</Button
      >
      <slot name="picker" />
    </section>
    <form id="decision-proposal-form" class="space-y-4" @submit.prevent="submit">
      <div class="space-y-1.5">
        <label for="decision-title" class="text-xs font-medium">{{
          t("brainstormingDecisions.name")
        }}</label
        ><Input
          id="decision-title"
          ref="titleInput"
          v-model="title"
          :maxlength="160"
          required
          :disabled="pending || !enabled"
          :placeholder="t('brainstormingDecisions.titlePlaceholder')"
        />
      </div>
      <div class="space-y-1.5">
        <label for="decision-conclusion" class="text-xs font-medium">{{
          t("brainstormingDecisions.conclusion")
        }}</label
        ><Textarea
          id="decision-conclusion"
          v-model="conclusion"
          :maxlength="4000"
          :rows="4"
          required
          :disabled="pending || !enabled"
          :placeholder="t('brainstormingDecisions.conclusionPlaceholder')"
        />
      </div>
      <div class="space-y-1.5">
        <label for="decision-reason" class="text-xs font-medium">{{
          t("brainstormingDecisions.reason")
        }}</label
        ><Textarea
          id="decision-reason"
          v-model="reason"
          :maxlength="4000"
          :rows="3"
          required
          :disabled="pending || !enabled"
          :placeholder="t('brainstormingDecisions.reasonPlaceholder')"
        />
      </div>
      <div class="space-y-1.5">
        <label id="decision-owner-label" for="decision-owner" class="text-xs font-medium">{{
          t("brainstormingDecisions.owner")
        }}</label>
        <Select v-if="canAssign" v-model="owner" :disabled="pending || !enabled"
          ><SelectTrigger id="decision-owner" aria-labelledby="decision-owner-label" class="w-full"
            ><SelectValue :placeholder="t('brainstormingDecisions.chooseOwner')" /></SelectTrigger
          ><SelectContent
            ><SelectItem v-for="person in members" :key="person.id" :value="String(person.id)">{{
              person.display_name
            }}</SelectItem></SelectContent
          ></Select
        >
        <Input v-else id="decision-owner" :model-value="ownerName" readonly />
        <p class="text-[11px] leading-relaxed text-muted-foreground">
          {{
            t(canAssign ? "brainstormingDecisions.ownerHelp" : "brainstormingDecisions.assignHelp")
          }}
        </p>
      </div>
      <p
        v-if="sources.some((source) => !source.available)"
        role="alert"
        class="text-xs text-destructive"
      >
        {{ t("brainstormingDecisions.replaceUnavailable") }}
      </p>
      <div class="sticky bottom-0 -mx-1 border-t bg-background/95 px-1 pb-2 pt-3 backdrop-blur-sm">
        <Button id="decision-save-proposal" type="submit" class="w-full" :disabled="!canSave"
          ><Loader2 v-if="pending" class="size-4 animate-spin" />{{
            t(draft ? "brainstormingDecisions.saveRevision" : "brainstormingDecisions.saveProposal")
          }}</Button
        >
        <p class="mt-2 text-center text-[11px] text-muted-foreground">
          {{ t("brainstormingDecisions.proposalHelp") }}
        </p>
      </div>
    </form>
  </div>
</template>
