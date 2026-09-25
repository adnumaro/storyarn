<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { ChevronDown, ClipboardList, ExternalLink, Link2, Unlink } from "@lucide/vue";
import { Button } from "@components/ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import DecisionTaskForm from "./DecisionTaskForm.vue";
import DecisionTaskPrepare from "./DecisionTaskPrepare.vue";
import { sectionHeading } from "./decisionSections";
import { taskHost } from "./decisionTask";
import type { DecisionRecord, DecisionTask } from "./decisionTypes";

/**
 * Tasks in external trackers that carry this decision out. Links are manual:
 * Storyarn opens them but never reads or updates the task.
 */
const {
  decision,
  pending = false,
  saved = 0,
} = defineProps<{
  decision: DecisionRecord;
  pending?: boolean;
  /** Counts confirmed task changes; a form closes only once its change is saved. */
  saved?: number;
}>();
const emit = defineEmits<{
  link: [url: string, title: string | null];
  edit: [key: string, url: string, title: string | null];
  unlink: [key: string];
}>();
const { t, locale } = useI18n();
// Which popover is open: "new", "prepare" or the key of the task being edited.
const editing = ref<string | null>(null);

function open(key: string, value: boolean) {
  if (value) editing.value = key;
  else if (editing.value === key) editing.value = null;
}
// A failed save keeps the form and what was typed in it.
watch(
  () => saved,
  () => {
    editing.value = null;
  },
);
const limit = computed(() => {
  if (decision.canLinkTasks || !decision.canUnlinkTasks) return null;
  return decision.tasks.length >= 20
    ? t("brainstormingDecisions.tasks.limitLinks")
    : t("brainstormingDecisions.tasks.limitChanges");
});
function linkedBy(task: DecisionTask) {
  const parsed = new Date(task.linkedAt);
  const when = Number.isNaN(parsed.getTime())
    ? ""
    : new Intl.DateTimeFormat(locale.value, { month: "short", day: "numeric" }).format(parsed);
  return t("brainstormingDecisions.tasks.linkedBy", {
    name: task.linkedByName || t("brainstormingDecisions.formerMember"),
    date: when,
  });
}
</script>
<template>
  <section id="decision-tasks" aria-labelledby="decision-tasks-heading">
    <div class="mb-2.5 flex items-center gap-1">
      <h3 id="decision-tasks-heading" :class="sectionHeading">
        {{ t("brainstormingDecisions.tasks.heading") }}
      </h3>
      <span class="flex-1" />
      <Popover
        :open="editing === 'prepare'"
        @update:open="(value: boolean) => open('prepare', value)"
      >
        <PopoverTrigger as-child>
          <Button id="decision-prepare-task" variant="ghost" size="xs"
            ><ClipboardList class="size-3" />{{ t("brainstormingDecisions.tasks.prepare") }}</Button
          >
        </PopoverTrigger>
        <PopoverContent align="end" class="w-[400px] max-w-[calc(100vw-2rem)] p-3">
          <DecisionTaskPrepare :decision="decision" @close="editing = null" />
        </PopoverContent>
      </Popover>
      <Popover
        v-if="decision.canLinkTasks"
        :open="editing === 'new'"
        @update:open="(value: boolean) => open('new', value)"
      >
        <PopoverTrigger as-child>
          <Button id="decision-link-task" variant="ghost" size="xs" :disabled="pending"
            ><Link2 class="size-3" />{{ t("brainstormingDecisions.tasks.link") }}</Button
          >
        </PopoverTrigger>
        <PopoverContent align="end" class="w-[320px] p-3">
          <DecisionTaskForm
            id-prefix="decision-link-task"
            :confirm-label="t('brainstormingDecisions.tasks.link')"
            :pending="pending"
            @confirm="(url, title) => emit('link', url, title)"
            @cancel="editing = null"
          />
        </PopoverContent>
      </Popover>
    </div>
    <ul v-if="decision.tasks.length" class="space-y-2">
      <li
        v-for="task in decision.tasks"
        :id="`decision-task-${task.key}`"
        :key="task.key"
        class="rounded-xl border border-border bg-card/60 p-3"
      >
        <div class="flex min-h-[18px] flex-wrap items-center gap-x-2.5 gap-y-1">
          <ExternalLink class="size-[15px] shrink-0 text-muted-foreground" />
          <a
            :id="`decision-task-open-${task.key}`"
            :href="task.url"
            target="_blank"
            rel="noopener noreferrer"
            data-live-link-exempt="external-task"
            class="min-w-0 truncate text-[13px] font-medium hover:underline"
            >{{ task.title || taskHost(task.url) }}</a
          >
          <span
            class="shrink-0 rounded border border-border px-1 text-[10.5px] text-muted-foreground"
            >{{ t("brainstormingDecisions.tasks.manual") }}</span
          >
        </div>
        <p class="mt-0.5 ml-[25px] truncate text-[11px] text-muted-foreground">
          <template v-if="task.title">{{ taskHost(task.url) }} · </template>{{ linkedBy(task) }}
        </p>
        <div
          v-if="decision.canEditTasks || decision.canUnlinkTasks"
          class="mt-2.5 ml-[25px] flex gap-1.5"
        >
          <Popover
            v-if="decision.canEditTasks"
            :open="editing === task.key"
            @update:open="(value: boolean) => open(task.key, value)"
          >
            <PopoverTrigger as-child>
              <Button
                :id="`decision-edit-task-${task.key}`"
                variant="ghost"
                size="xs"
                :disabled="pending"
                >{{ t("brainstormingDecisions.tasks.edit") }}<ChevronDown class="size-3"
              /></Button>
            </PopoverTrigger>
            <PopoverContent align="start" class="w-[320px] p-3">
              <DecisionTaskForm
                :id-prefix="`decision-edit-task-${task.key}`"
                :initial-url="task.url"
                :initial-title="task.title ?? ''"
                :confirm-label="t('brainstormingDecisions.tasks.save')"
                :pending="pending"
                @confirm="(url, title) => emit('edit', task.key, url, title)"
                @cancel="editing = null"
              />
            </PopoverContent>
          </Popover>
          <Button
            v-if="decision.canUnlinkTasks"
            :id="`decision-unlink-task-${task.key}`"
            variant="ghost"
            size="xs"
            :disabled="pending"
            @click="emit('unlink', task.key)"
            ><Unlink class="size-3" />{{ t("brainstormingDecisions.tasks.unlink") }}</Button
          >
        </div>
      </li>
    </ul>
    <p
      v-else
      class="rounded-xl border border-dashed border-border px-3 py-2.5 text-xs text-muted-foreground"
    >
      {{ t("brainstormingDecisions.tasks.empty") }}
    </p>
    <p v-if="limit" id="decision-task-limit" class="mt-1.5 text-xs text-muted-foreground">
      {{ limit }}
    </p>
  </section>
</template>
