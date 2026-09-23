<script setup lang="ts">
import { ref } from "vue";
import { useI18n } from "vue-i18n";
import { ChevronDown, ExternalLink, Lightbulb, ListChecks } from "@lucide/vue";
import { Button } from "@components/ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import LiveLink from "@components/navigation/LiveLink.vue";
import DecisionCard from "./DecisionCard.vue";
import DecisionMarkForm from "./DecisionMarkForm.vue";
import type { ApplicationState } from "./decisionTypes";
import type { DecisionAbout } from "./explorationTypes";

type Mark = Exclude<ApplicationState, "not_applied">;

/**
 * Decisions about the content open in the editor, already in the order to act
 * on them. A row opens its session on the decision; rows still to apply here
 * offer "Go apply" and "Mark applied" to editors.
 */
const {
  items,
  name,
  canEdit = false,
  pending = false,
} = defineProps<{
  items: DecisionAbout[];
  name: string;
  canEdit?: boolean;
  pending?: boolean;
}>();
const emit = defineEmits<{
  apply: [item: DecisionAbout];
  declare: [item: DecisionAbout, state: Mark, note: string | null];
}>();
const { t } = useI18n();
const marking = ref<number | null>(null);

function declare(item: DecisionAbout, state: Mark, note: string | null) {
  marking.value = null;
  emit("declare", item, state, note);
}
</script>
<template>
  <section
    id="exploration-decisions"
    aria-labelledby="exploration-decisions-heading"
    class="space-y-2"
  >
    <h3 id="exploration-decisions-heading" class="flex items-center gap-2 text-sm font-medium">
      <ListChecks class="size-4 text-muted-foreground" />
      {{ t("brainstormingDecisions.about.title", { name }) }}
    </h3>
    <ul class="max-h-80 space-y-2 overflow-y-auto">
      <li
        v-for="item in items"
        :key="`${item.sessionId}-${item.decision.id}`"
        :data-decision-about="item.decision.id"
      >
        <LiveLink
          :to="item.sessionUrl"
          class="block rounded-xl outline-none focus-visible:ring-2 focus-visible:ring-ring"
        >
          <DecisionCard :decision="item.decision" />
        </LiveLink>
        <div class="mt-1.5 flex min-h-7 items-center gap-2 px-1 text-[11px] text-muted-foreground">
          <Lightbulb class="size-3 shrink-0" />
          <span class="min-w-0 flex-1 truncate">{{ item.sessionTitle }}</span>
          <template v-if="canEdit && item.toApply && item.decision.canDeclare && item.targetKey">
            <Button
              :id="`exploration-decision-apply-${item.decision.id}`"
              variant="outline"
              size="xs"
              :disabled="pending"
              @click="emit('apply', item)"
              ><ExternalLink class="size-3" />{{
                t("brainstormingDecisions.about.goApply")
              }}</Button
            >
            <Popover
              :open="marking === item.decision.id"
              @update:open="(value: boolean) => (marking = value ? item.decision.id : null)"
            >
              <PopoverTrigger as-child>
                <Button
                  :id="`exploration-decision-mark-${item.decision.id}`"
                  variant="ghost"
                  size="xs"
                  :disabled="pending"
                  >{{ t("brainstormingDecisions.markApplied") }}<ChevronDown class="size-3"
                /></Button>
              </PopoverTrigger>
              <PopoverContent align="end" class="w-[300px] p-3">
                <DecisionMarkForm
                  :name="name"
                  :id-prefix="`exploration-decision-mark-${item.decision.id}`"
                  :pending="pending"
                  @confirm="(state, note) => declare(item, state, note)"
                  @cancel="marking = null"
                />
              </PopoverContent>
            </Popover>
          </template>
        </div>
      </li>
    </ul>
  </section>
</template>
