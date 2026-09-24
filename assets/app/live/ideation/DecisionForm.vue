<script setup lang="ts">
import { computed, nextTick, reactive, ref, watch, type Component } from "vue";
import { useI18n } from "vue-i18n";
import {
  Anchor,
  Ban,
  Check,
  Clock,
  FlaskConical,
  Loader2,
  Pencil,
  Plus,
  RefreshCw,
  Send,
  TextQuote,
  UserCheck,
} from "@lucide/vue";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
import { Textarea } from "@components/ui/textarea";
import { ToggleGroup, ToggleGroupItem } from "@components/ui/toggle-group";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select";
import DecisionAffects from "./DecisionAffects.vue";
import DecisionSources from "./DecisionSources.vue";
import {
  defaultOwner,
  draftFields,
  draftInput,
  fieldsReady,
  newFields,
  sourceRound,
  sourcesReady,
  type DecisionFormOptions,
} from "./decisionForm";
import { deriveTitle } from "./decisionStatus";
import type {
  DecisionDraftInput,
  DecisionRevision,
  DecisionSource,
  DecisionSourceIdentity,
  DecisionVerb,
} from "./decisionTypes";

const {
  context,
  draft,
  draftVersion = null,
  sources,
  canAssign,
  enabled,
  pending,
  options,
} = defineProps<{
  context: string;
  draft: DecisionRevision | null;
  draftVersion?: number | null;
  sources: DecisionSource[];
  canAssign: boolean;
  enabled: boolean;
  pending: boolean;
  options: DecisionFormOptions;
}>();
const emit = defineEmits<{
  submit: [input: DecisionDraftInput];
  removeSource: [source: DecisionSourceIdentity];
  browseSources: [];
  refreshSources: [];
  searchTargets: [query: string];
  dirty: [value: boolean];
}>();
const { t } = useI18n();
const verbs: DecisionVerb[] = ["create", "change", "test", "keep", "discard"];
const verbIcons: Record<DecisionVerb, Component> = {
  create: Plus,
  change: Pencil,
  test: FlaskConical,
  keep: Anchor,
  discard: Ban,
};

const form = reactive(newFields(null, ""));
const baseVersion = ref<number | null>(null);
const baseline = ref("");
const conclusionInput = ref<InstanceType<typeof Textarea> | null>(null);

const changed = computed(() => draft !== null && draftVersion !== baseVersion.value);
const fingerprint = () =>
  JSON.stringify([
    form,
    sources.map((source) => [source.type, source.id, source.identity, source.version]),
  ]);

watch(
  () => context,
  async () => {
    const at = context;
    Object.assign(
      form,
      draft ? draftFields(draft) : newFields(options.prefill, defaultOwner(options)),
    );
    baseVersion.value = draftVersion;
    baseline.value = fingerprint();
    await nextTick();
    const element = conclusionInput.value?.$el;
    if (context === at && element instanceof HTMLTextAreaElement && element.isConnected)
      element.focus({ preventScroll: true });
  },
  { immediate: true },
);
watch(
  () => form.conclusion,
  (value) => {
    if (!form.titleTouched) form.title = deriveTitle(value);
  },
);
watch(fingerprint, (value) => emit("dirty", value !== baseline.value));

const selfResponsible = computed(
  () => options.viewerId !== null && Number(form.owner) === options.viewerId,
);
const ownerName = computed(
  () =>
    options.members.find((person) => person.id === Number(form.owner))?.display_name ??
    draft?.responsibleName ??
    t("brainstormingDecisions.formerMember"),
);
const round = computed(() => sourceRound(sources, options.rounds));
const canSave = computed(
  () => enabled && !pending && !changed.value && sourcesReady(sources) && fieldsReady(form),
);

function setVerb(value: unknown) {
  // A single ToggleGroup emits undefined when its item is pressed again.
  if (typeof value === "string" && verbs.includes(value as DecisionVerb))
    form.verb = value as DecisionVerb;
}
function editTitle(value: string | number) {
  form.title = String(value);
  form.titleTouched = form.title.trim() !== deriveTitle(form.conclusion);
}
function submit(register: boolean) {
  const verb = form.verb;
  if (!canSave.value || verb === null) return;
  emit(
    "submit",
    draftInput({ ...form, verb }, register && selfResponsible.value, baseVersion.value),
  );
}
function useCurrentVersion() {
  if (draft === null || pending) return;
  baseVersion.value = draftVersion;
  if (!canAssign) form.owner = String(draft.responsibleId ?? "");
}
</script>
<template>
  <div class="space-y-4">
    <div
      v-if="changed && draft"
      id="decision-current-proposal"
      role="alert"
      class="rounded-lg border border-amber-400/40 bg-amber-500/5 p-3"
    >
      <p class="text-xs font-medium">{{ t("brainstormingDecisions.changedProposal") }}</p>
      <p class="mt-1.5 text-xs leading-relaxed text-muted-foreground">
        {{ t("brainstormingDecisions.changedProposalHelp") }}
      </p>
      <Button
        id="decision-use-current-version"
        class="mt-3 w-full"
        size="sm"
        variant="outline"
        :disabled="pending || !enabled"
        @click="useCurrentVersion"
        >{{ t("brainstormingDecisions.keepMyProposal") }}</Button
      >
    </div>
    <section aria-labelledby="decision-sources-heading">
      <div class="flex items-center justify-between gap-2">
        <h3 id="decision-sources-heading" class="text-[13px] font-medium">
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
        class="mt-2 rounded-lg border border-dashed p-4 text-center text-xs leading-relaxed text-muted-foreground"
      >
        {{ t("brainstormingDecisions.chooseSources") }}
      </p>
      <DecisionSources
        v-else
        class="mt-2"
        variant="form"
        :sources="sources"
        :editable="enabled"
        :pending="pending"
        @remove="emit('removeSource', $event)"
      />
      <p
        id="decision-context-line"
        class="mt-2 flex flex-wrap items-baseline gap-1.5 text-xs text-muted-foreground"
      >
        <template v-if="round"
          ><span class="font-semibold text-foreground/80">R{{ round.number }}</span
          ><span v-if="round.prompt">{{ round.prompt }}</span></template
        ><span class="opacity-70">{{
          round
            ? `· ${t("brainstormingDecisions.contextHint")}`
            : t("brainstormingDecisions.contextHint")
        }}</span>
      </p>
      <Button
        v-if="sources.some((source) => source.changed && source.currentVersion !== null)"
        id="decision-refresh-sources"
        size="sm"
        variant="outline"
        class="mt-2"
        :disabled="pending || !enabled"
        @click="emit('refreshSources')"
        ><RefreshCw class="size-3.5" />{{ t("brainstormingDecisions.refreshSources") }}</Button
      >
      <slot name="picker" />
    </section>
    <form id="decision-proposal-form" class="space-y-4" @submit.prevent="submit(true)">
      <div>
        <div class="mb-1.5 flex items-baseline gap-1.5">
          <label for="decision-conclusion" class="text-[13px] font-medium">{{
            t("brainstormingDecisions.conclusion")
          }}</label
          ><span class="text-[11px] text-muted-foreground">{{
            t("brainstormingDecisions.required")
          }}</span>
        </div>
        <Textarea
          id="decision-conclusion"
          ref="conclusionInput"
          v-model="form.conclusion"
          :maxlength="4000"
          :rows="3"
          required
          :disabled="pending || !enabled"
          :placeholder="t('brainstormingDecisions.conclusionPlaceholder')"
        />
        <p
          v-if="options.prefill?.fromGroup && !draft"
          class="mt-1.5 flex items-center gap-[5px] text-xs text-muted-foreground"
        >
          <TextQuote class="size-3" />{{
            t("brainstormingDecisions.fromSynthesis", { group: options.prefill.fromGroup })
          }}
        </p>
      </div>
      <div class="@container">
        <div class="mb-1.5 flex items-baseline gap-1.5">
          <span id="decision-verb-label" class="text-[13px] font-medium">{{
            t("brainstormingDecisions.meansWeWill")
          }}</span
          ><span class="text-[11px] text-muted-foreground">{{
            t("brainstormingDecisions.required")
          }}</span>
        </div>
        <ToggleGroup
          type="single"
          variant="outline"
          class="w-full @max-[20rem]:hidden"
          aria-labelledby="decision-verb-label"
          :model-value="form.verb ?? undefined"
          :disabled="pending || !enabled"
          @update:model-value="setVerb"
        >
          <ToggleGroupItem
            v-for="option in verbs"
            :id="`decision-verb-${option}`"
            :key="option"
            :value="option"
            class="flex-1"
            >{{ t(`brainstormingDecisions.verbs.${option}`) }}</ToggleGroupItem
          >
        </ToggleGroup>
        <Select
          :model-value="form.verb ?? undefined"
          :disabled="pending || !enabled"
          @update:model-value="setVerb"
          ><SelectTrigger class="w-full @min-[20rem]:hidden" aria-labelledby="decision-verb-label"
            ><SelectValue :placeholder="t('brainstormingDecisions.meansWeWill')" /></SelectTrigger
          ><SelectContent
            ><SelectItem v-for="option in verbs" :key="option" :value="option">{{
              t(`brainstormingDecisions.verbs.${option}`)
            }}</SelectItem></SelectContent
          ></Select
        >
        <p
          v-if="form.verb"
          class="mt-1.5 flex items-center gap-[5px] text-xs text-muted-foreground"
        >
          <component :is="verbIcons[form.verb]" class="size-3" />{{
            t(`brainstormingDecisions.verbHints.${form.verb}`)
          }}
        </p>
        <DecisionAffects
          v-model="form.affected"
          class="mt-3"
          :verb="form.verb"
          :suggestions="options.suggestions"
          :results="options.results"
          :disabled="pending || !enabled"
          @search="emit('searchTargets', $event)"
        />
      </div>
      <div>
        <div class="mb-1.5 flex items-baseline gap-1.5">
          <label for="decision-reason" class="text-[13px] font-medium">{{
            t("brainstormingDecisions.reason")
          }}</label
          ><span class="text-[11px] text-muted-foreground">{{
            t("brainstormingDecisions.optional")
          }}</span>
        </div>
        <Textarea
          id="decision-reason"
          v-model="form.reason"
          :maxlength="4000"
          :rows="2"
          :disabled="pending || !enabled"
          :placeholder="t('brainstormingDecisions.reasonPlaceholder')"
        />
      </div>
      <div>
        <label
          id="decision-owner-label"
          for="decision-owner"
          class="mb-1.5 block text-[13px] font-medium"
          >{{ t("brainstormingDecisions.owner") }}</label
        >
        <Select v-if="canAssign" v-model="form.owner" :disabled="pending || !enabled"
          ><SelectTrigger id="decision-owner" aria-labelledby="decision-owner-label" class="w-full"
            ><SelectValue :placeholder="t('brainstormingDecisions.chooseOwner')" /></SelectTrigger
          ><SelectContent
            ><SelectItem
              v-for="person in options.members"
              :key="person.id"
              :value="String(person.id)"
              >{{ person.display_name }}</SelectItem
            ></SelectContent
          ></Select
        >
        <Input v-else id="decision-owner" :model-value="ownerName" readonly />
        <p
          id="decision-owner-preview"
          class="mt-1.5 flex items-center gap-1.5 text-xs"
          :class="selfResponsible ? 'text-primary' : 'text-muted-foreground'"
        >
          <UserCheck v-if="selfResponsible" class="size-3" /><Clock v-else class="size-3" />{{
            selfResponsible
              ? t("brainstormingDecisions.registerPreview")
              : t("brainstormingDecisions.proposePreview", { name: ownerName })
          }}
        </p>
        <p v-if="!canAssign" class="mt-1 text-[11px] text-muted-foreground">
          {{ t("brainstormingDecisions.assignHelp") }}
        </p>
      </div>
      <button
        v-if="!form.nextOpen"
        id="decision-add-next-action"
        type="button"
        class="flex items-center gap-[5px] text-[13px] text-muted-foreground hover:text-foreground disabled:opacity-50"
        :disabled="pending || !enabled"
        @click="form.nextOpen = true"
      >
        <Plus class="size-[13px]" />{{ t("brainstormingDecisions.addNextAction") }}
        <span class="text-[11px]">· {{ t("brainstormingDecisions.nextActionHint") }}</span>
      </button>
      <div v-else>
        <div class="mb-1.5 flex items-baseline gap-1.5">
          <label for="decision-next-action" class="text-[13px] font-medium">{{
            t("brainstormingDecisions.nextAction")
          }}</label
          ><span class="text-[11px] text-muted-foreground">{{
            t("brainstormingDecisions.nextActionOptional")
          }}</span>
        </div>
        <div class="grid grid-cols-[minmax(0,1fr)_150px] gap-1.5">
          <Input
            id="decision-next-action"
            v-model="form.nextText"
            :maxlength="500"
            :disabled="pending || !enabled"
            :placeholder="t('brainstormingDecisions.nextActionPlaceholder')"
          />
          <Select v-model="form.nextOwner" :disabled="pending || !enabled"
            ><SelectTrigger
              id="decision-next-action-owner"
              class="w-full"
              :aria-label="t('brainstormingDecisions.nextActionOwner')"
              ><SelectValue
                :placeholder="t('brainstormingDecisions.nextActionOwner')" /></SelectTrigger
            ><SelectContent
              ><SelectItem value="none">{{ t("brainstormingDecisions.noOwner") }}</SelectItem
              ><SelectItem
                v-for="person in options.members"
                :key="person.id"
                :value="String(person.id)"
                >{{ person.display_name }}</SelectItem
              ></SelectContent
            ></Select
          >
        </div>
      </div>
      <template v-if="options.replaceable.length">
        <button
          v-if="!form.replacesOpen"
          id="decision-add-replaces"
          type="button"
          class="flex items-center gap-[5px] text-[13px] text-muted-foreground hover:text-foreground disabled:opacity-50"
          :disabled="pending || !enabled"
          @click="form.replacesOpen = true"
        >
          <Plus class="size-[13px]" />{{ t("brainstormingDecisions.addReplaces") }}
          <span class="text-[11px]">· {{ t("brainstormingDecisions.replacesHint") }}</span>
        </button>
        <div v-else>
          <label
            id="decision-replaces-label"
            for="decision-replaces"
            class="mb-1.5 block text-[13px] font-medium"
            >{{ t("brainstormingDecisions.addReplaces") }}</label
          >
          <Select v-model="form.replaces" :disabled="pending || !enabled"
            ><SelectTrigger
              id="decision-replaces"
              class="w-full"
              aria-labelledby="decision-replaces-label"
              ><SelectValue
                :placeholder="t('brainstormingDecisions.chooseReplaced')" /></SelectTrigger
            ><SelectContent
              ><SelectItem value="none">{{ t("brainstormingDecisions.noReplacement") }}</SelectItem
              ><SelectItem
                v-for="item in options.replaceable"
                :key="item.id"
                :value="String(item.id)"
                >{{ item.title }}</SelectItem
              ></SelectContent
            ></Select
          >
        </div>
      </template>
      <div>
        <div class="mb-1.5 flex items-baseline gap-1.5">
          <label for="decision-title" class="text-xs font-medium text-muted-foreground">{{
            t("brainstormingDecisions.titleLabel")
          }}</label
          ><span class="text-[11px] text-muted-foreground">{{
            t("brainstormingDecisions.titleHint")
          }}</span>
        </div>
        <Input
          id="decision-title"
          :model-value="form.title"
          :maxlength="160"
          class="h-8 text-sm"
          :disabled="pending || !enabled"
          :placeholder="t('brainstormingDecisions.titlePlaceholder')"
          @update:model-value="editTitle"
        />
      </div>
      <p
        v-if="sources.some((source) => !source.available)"
        role="alert"
        class="text-xs text-destructive"
      >
        {{ t("brainstormingDecisions.replaceUnavailable") }}
      </p>
      <div class="sticky bottom-0 -mx-1 border-t bg-background/95 px-1 pt-3 pb-2 backdrop-blur-sm">
        <Button id="decision-save-proposal" type="submit" class="w-full" :disabled="!canSave"
          ><Loader2 v-if="pending" class="size-4 animate-spin" /><Check
            v-else-if="selfResponsible"
            class="size-3.5"
          /><Send v-else class="size-3.5" />{{
            selfResponsible
              ? t("brainstormingDecisions.register")
              : t("brainstormingDecisions.proposeButton")
          }}</Button
        >
        <p class="mt-2 text-center text-[11px] text-muted-foreground">
          {{
            selfResponsible
              ? t("brainstormingDecisions.registerHelp")
              : t("brainstormingDecisions.proposalHelp")
          }}
        </p>
        <button
          v-if="selfResponsible"
          id="decision-save-as-proposal"
          type="button"
          class="mx-auto mt-1.5 block text-xs text-primary hover:underline disabled:opacity-50"
          :disabled="!canSave"
          @click="submit(false)"
        >
          {{ t("brainstormingDecisions.saveAsProposal") }}
        </button>
      </div>
    </form>
  </div>
</template>
