<script setup lang="ts">
import { useI18n } from "vue-i18n";
import DecisionSources from "./DecisionSources.vue";
import type { DecisionAgreement } from "./decisionTypes";
defineProps<{ agreement: DecisionAgreement }>();
const { t, locale } = useI18n();
function date(value: string) {
  const at = new Date(value);
  return Number.isNaN(at.getTime())
    ? value
    : new Intl.DateTimeFormat(locale.value, { dateStyle: "medium", timeStyle: "short" }).format(at);
}
</script>
<template>
  <div class="space-y-4">
    <div>
      <h3 class="break-words text-base font-semibold leading-snug">{{ agreement.title }}</h3>
      <p class="mt-1 text-xs text-muted-foreground">
        {{ t("brainstormingDecisions.owner") }}:
        {{ agreement.ownerName || t("brainstormingDecisions.formerMember")
        }}<span v-if="agreement.acceptedAt"> · {{ date(agreement.acceptedAt) }}</span>
      </p>
    </div>
    <section>
      <h4 class="mb-1 text-xs font-medium text-muted-foreground">
        {{ t("brainstormingDecisions.conclusion") }}
      </h4>
      <p class="whitespace-pre-wrap break-words text-sm leading-relaxed">
        {{ agreement.conclusion }}
      </p>
    </section>
    <section>
      <h4 class="mb-1 text-xs font-medium text-muted-foreground">
        {{ t("brainstormingDecisions.reason") }}
      </h4>
      <p class="whitespace-pre-wrap break-words text-sm leading-relaxed">{{ agreement.reason }}</p>
    </section>
    <section>
      <h4 class="mb-2 text-xs font-medium text-muted-foreground">
        {{ t("brainstormingDecisions.sourcesCount", { count: agreement.sources.length }) }}
      </h4>
      <DecisionSources :sources="agreement.sources" />
    </section>
  </div>
</template>
