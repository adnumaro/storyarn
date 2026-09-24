<script setup lang="ts">
import { computed, ref, watch, type Component } from "vue";
import { useI18n } from "vue-i18n";
import { Check, Clapperboard, FileText, Plus, Sparkle, Workflow, X } from "@lucide/vue";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import type { AffectedChip } from "./decisionForm";
import type { DecisionTargetOption, DecisionTargetType, DecisionVerb } from "./decisionTypes";

const {
  modelValue,
  verb,
  suggestions,
  results,
  disabled = false,
} = defineProps<{
  modelValue: AffectedChip[];
  verb: DecisionVerb | null;
  suggestions: DecisionTargetOption[];
  results: DecisionTargetOption[];
  disabled?: boolean;
}>();
const emit = defineEmits<{
  "update:modelValue": [value: AffectedChip[]];
  search: [query: string];
}>();
const { t } = useI18n();
const icons: Record<DecisionTargetType, Component> = {
  sheet: FileText,
  flow: Workflow,
  scene: Clapperboard,
};
const targetTypes: DecisionTargetType[] = ["sheet", "flow", "scene"];
const open = ref(false);
const query = ref("");
const creating = ref(false);
const newLabel = ref("");
const newType = ref<DecisionTargetType>("sheet");
const full = computed(() => modelValue.length >= 5);
const folded = computed(() => (verb === "keep" || verb === "discard") && modelValue.length === 0);
const verbName = computed(() =>
  verb ? t(`brainstormingDecisions.verbs.${verb}`).toLowerCase() : "",
);
const origin = computed(() => suggestions.filter((item) => item.relation === "origin"));
const referenced = computed(() => suggestions.filter((item) => item.relation !== "origin"));
const project = computed(() =>
  results.filter((item) => !suggestions.some((known) => same(known, item))),
);
let timer: ReturnType<typeof setTimeout> | undefined;
watch(query, (value) => {
  clearTimeout(timer);
  timer = setTimeout(() => emit("search", value.trim()), 250);
});
watch(open, (value) => {
  if (!value) {
    creating.value = false;
    newLabel.value = "";
    query.value = "";
  } else emit("search", "");
});

function same(a: { type: string; id: number | null }, b: { type: string; id: number | null }) {
  return a.type === b.type && a.id !== null && a.id === b.id;
}
function chosen(option: DecisionTargetOption) {
  return modelValue.some((item) => same(item, option));
}
function toggle(option: DecisionTargetOption) {
  if (chosen(option))
    emit(
      "update:modelValue",
      modelValue.filter((item) => !same(item, option)),
    );
  else if (!full.value)
    emit("update:modelValue", [
      ...modelValue,
      { type: option.type, id: option.id, name: option.name, available: true },
    ]);
}
function addNew() {
  const label = newLabel.value.trim();
  if (!label || full.value) return;
  const duplicate = modelValue.some(
    (item) =>
      item.id === null &&
      item.type === newType.value &&
      item.name.toLowerCase() === label.toLowerCase(),
  );
  if (!duplicate)
    emit("update:modelValue", [
      ...modelValue,
      { type: newType.value, id: null, label, name: label, available: true },
    ]);
  creating.value = false;
  newLabel.value = "";
}
function remove(index: number) {
  emit(
    "update:modelValue",
    modelValue.filter((_, position) => position !== index),
  );
}
</script>
<template>
  <div class="flex flex-wrap items-center gap-1.5">
    <span class="mr-1 text-[13px] font-medium">{{ t("brainstormingDecisions.affects") }}</span>
    <span
      v-for="(item, index) in modelValue"
      :key="`${item.type}-${item.id ?? item.name}`"
      :data-affected-target="`${item.type}-${item.id ?? 'new'}`"
      class="inline-flex h-[26px] max-w-full items-center gap-1.5 rounded-[7px] border border-border bg-muted/45 pr-1.5 pl-2 text-[13px]"
      ><component :is="icons[item.type]" class="size-[13px] shrink-0 text-muted-foreground" /><span
        class="truncate"
        :class="item.available ? '' : 'text-muted-foreground line-through'"
        >{{ item.name }}</span
      ><span class="shrink-0 text-[11px] text-muted-foreground">{{
        item.id === null
          ? t("brainstormingDecisions.targetNew")
          : item.available
            ? t(`brainstormingDecisions.targetTypes.${item.type}`)
            : t("brainstormingDecisions.targetUnavailable")
      }}</span
      ><button
        type="button"
        class="rounded-sm text-muted-foreground hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring focus-visible:outline-none"
        :disabled="disabled"
        :aria-label="t('brainstormingDecisions.removeTarget', { name: item.name })"
        @click="remove(index)"
      >
        <X class="size-3" /></button
    ></span>
    <Popover v-model:open="open">
      <PopoverTrigger as-child>
        <button
          id="decision-affects-add"
          type="button"
          :disabled="disabled || full"
          class="inline-flex h-[26px] items-center gap-[5px] rounded-[7px] border border-dashed px-2.5 text-xs disabled:opacity-50"
          :class="
            modelValue.length || folded
              ? 'border-border text-muted-foreground'
              : 'border-primary/50 text-primary'
          "
        >
          <Plus class="size-3" />{{
            folded ? t("brainstormingDecisions.addAffected") : t("brainstormingDecisions.add")
          }}
        </button>
      </PopoverTrigger>
      <PopoverContent align="start" class="w-80 p-2">
        <Input
          id="decision-target-search"
          v-model="query"
          :placeholder="t('brainstormingDecisions.searchTargets')"
          class="h-8 text-sm"
          :aria-label="t('brainstormingDecisions.searchTargets')"
        />
        <div class="mt-1.5 max-h-72 overflow-y-auto">
          <template
            v-for="section in [
              { key: 'origin', label: 'originSection', items: origin },
              { key: 'references', label: 'referencesSection', items: referenced },
              { key: 'project', label: 'projectSection', items: project },
            ]"
            :key="section.key"
          >
            <template v-if="section.items.length">
              <p
                class="px-2 pt-2 pb-1 text-[10.5px] font-semibold tracking-[.06em] text-muted-foreground uppercase"
              >
                {{ t(`brainstormingDecisions.${section.label}`) }}
              </p>
              <button
                v-for="option in section.items"
                :id="`decision-target-option-${option.type}-${option.id}`"
                :key="`${option.type}-${option.id}`"
                type="button"
                class="flex h-[34px] w-full items-center gap-2.5 rounded-[7px] px-2 text-left text-[13px] hover:bg-accent focus-visible:bg-accent focus-visible:outline-none disabled:opacity-50"
                :disabled="disabled || (full && !chosen(option))"
                @click="toggle(option)"
              >
                <component
                  :is="icons[option.type]"
                  class="size-3.5 shrink-0 text-muted-foreground"
                />
                <span class="min-w-0 flex-1 truncate">{{ option.name }}</span>
                <span class="shrink-0 text-[11px] text-muted-foreground">{{
                  t(`brainstormingDecisions.targetTypes.${option.type}`)
                }}</span>
                <Check v-if="chosen(option)" class="size-3.5 shrink-0 text-primary" />
              </button>
            </template>
          </template>
          <p
            v-if="query.trim() && !origin.length && !referenced.length && !project.length"
            class="px-2 py-3 text-xs text-muted-foreground"
          >
            {{ t("brainstormingDecisions.noTargetResults") }}
          </p>
        </div>
        <div class="mt-1 border-t border-border pt-1.5">
          <button
            v-if="!creating"
            id="decision-target-new"
            type="button"
            class="flex h-[34px] w-full items-center gap-2.5 rounded-[7px] px-2 text-left text-[13px] hover:bg-accent disabled:opacity-50"
            :disabled="disabled || full"
            @click="creating = true"
          >
            <Sparkle class="size-3.5 shrink-0 text-muted-foreground" />
            <span class="flex-1">{{ t("brainstormingDecisions.somethingNew") }}</span>
            <span class="text-[11px] text-muted-foreground">{{
              t("brainstormingDecisions.somethingNewHelp")
            }}</span>
          </button>
          <form v-else class="flex items-center gap-1.5 p-1" @submit.prevent="addNew">
            <Input
              id="decision-target-new-label"
              v-model="newLabel"
              :maxlength="160"
              class="h-8 flex-1 text-sm"
              :placeholder="t('brainstormingDecisions.newLabelPlaceholder')"
            />
            <div class="flex shrink-0 items-center rounded-md border border-border p-0.5">
              <button
                v-for="type in targetTypes"
                :key="type"
                type="button"
                class="inline-flex size-7 items-center justify-center rounded-[5px]"
                :class="newType === type ? 'bg-accent text-foreground' : 'text-muted-foreground'"
                :aria-pressed="newType === type"
                :aria-label="t(`brainstormingDecisions.targetTypes.${type}`)"
                :title="t(`brainstormingDecisions.targetTypes.${type}`)"
                @click="newType = type"
              >
                <component :is="icons[type]" class="size-3.5" />
              </button>
            </div>
            <Button type="submit" size="sm" :disabled="!newLabel.trim()">{{
              t("brainstormingDecisions.add")
            }}</Button>
          </form>
        </div>
      </PopoverContent>
    </Popover>
    <span v-if="folded" class="text-[11px] text-muted-foreground">{{
      t("brainstormingDecisions.usuallyNone", { verb: verbName })
    }}</span>
    <span v-else-if="verb && !modelValue.length" class="text-[11px] text-muted-foreground">{{
      t("brainstormingDecisions.expectedFor", { verb: verbName })
    }}</span>
  </div>
</template>
