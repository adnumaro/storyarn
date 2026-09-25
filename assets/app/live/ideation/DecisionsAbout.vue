<script setup lang="ts">
import { ref } from "vue";
import { useI18n } from "vue-i18n";
import { ChevronDown, ExternalLink } from "@lucide/vue";
import { Button } from "@components/ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import LiveLink from "@components/navigation/LiveLink.vue";
import DecisionCard from "./DecisionCard.vue";
import DecisionMarkForm from "./DecisionMarkForm.vue";
import type { ApplicationState } from "./decisionTypes";
import type { DecisionAbout } from "./explorationTypes";

/**
 * Decisions about the content open in the editor, already in the order to act
 * on them. Those still to apply here are full cards with "Go apply" and "Mark
 * applied" for editors; the rest are compact rows. Every one opens its session
 * on the decision.
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
  declare: [item: DecisionAbout, state: ApplicationState, note: string | null];
}>();
const { t } = useI18n();
const marking = ref<number | null>(null);

function declare(item: DecisionAbout, state: ApplicationState, note: string | null) {
  marking.value = null;
  emit("declare", item, state, note);
}
function actionable(item: DecisionAbout) {
  return canEdit && item.toApply && item.decision.canDeclare && !!item.targetKey;
}
</script>
<template>
  <section
    id="exploration-decisions"
    aria-labelledby="exploration-decisions-heading"
    class="space-y-2"
  >
    <h3 id="exploration-decisions-heading" class="flex items-baseline gap-2 text-sm font-medium">
      {{ t("brainstormingDecisions.about.title", { name }) }}
      <span class="text-xs font-normal text-muted-foreground">{{ items.length }}</span>
    </h3>
    <ul class="space-y-2">
      <li
        v-for="item in items"
        :key="`${item.sessionId}-${item.decision.id}`"
        :data-decision-about="item.decision.id"
      >
        <DecisionCard
          v-if="item.toApply"
          :decision="item.decision"
          :href="item.sessionUrl"
          :session-name="item.sessionTitle"
          :round-count="item.roundCount"
        >
          <template v-if="actionable(item)" #actions>
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
        </DecisionCard>
        <LiveLink
          v-else
          :to="item.sessionUrl"
          class="block rounded-lg border border-border px-3 py-2 outline-none hover:border-primary/40 hover:bg-accent/30 focus-visible:ring-2 focus-visible:ring-ring"
        >
          <DecisionCard
            :decision="item.decision"
            size="compact"
            :session-name="item.sessionTitle"
          />
        </LiveLink>
      </li>
    </ul>
  </section>
</template>
