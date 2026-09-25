<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { ArrowRight, ExternalLink } from "@lucide/vue";
import { Button } from "@components/ui/button";
import LiveLink from "@components/navigation/LiveLink.vue";
import type { NotificationItem } from "@components/notifications/types";
import DecisionCard from "./DecisionCard.vue";
import type { DecisionNoticeData } from "./decisionTypes";

/**
 * One decision notification in the inbox: actor · what happened · the compact
 * card · one primary action · time. A request to accept stays unread when
 * opened; it is settled once the decision stops waiting for it.
 */
const { notification, data, when } = defineProps<{
  notification: NotificationItem;
  data: DecisionNoticeData;
  when: string;
}>();
const emit = defineEmits<{ open: [keepUnread: boolean] }>();
const { t } = useI18n();

const kind = computed(() => notification.kind.replace("decision_", ""));
const sentence = computed(() =>
  data.target
    ? t(`brainstormingDecisions.notice.${kind.value}Target`, { target: data.target })
    : t(`brainstormingDecisions.notice.${kind.value}`),
);
// Asking someone to act is the primary action; news is only opened.
const primary = computed(() =>
  ["decision_to_accept", "decision_next_action"].includes(notification.kind),
);
</script>
<template>
  <div :data-decision-notice="notification.id">
    <p class="text-sm leading-5 text-pretty">
      <span class="font-semibold">{{
        notification.actorName || t("brainstormingDecisions.formerMember")
      }}</span>
      {{ sentence }}
    </p>
    <div class="mt-1.5 rounded-lg border border-border bg-background/60 px-2 py-1.5">
      <DecisionCard :decision="data.decision" size="compact" />
    </div>
    <div class="mt-2 flex min-w-0 items-center gap-2 text-xs text-muted-foreground">
      <Button :variant="primary ? 'default' : 'outline'" size="xs" as-child>
        <LiveLink
          :id="`notification-action-${notification.id}`"
          :to="data.action.href"
          @click="emit('open', notification.kind === 'decision_to_accept')"
        >
          <component
            :is="data.action.kind === 'apply' ? ExternalLink : ArrowRight"
            class="size-3"
          />
          {{
            data.action.kind === "apply"
              ? t("brainstormingDecisions.notice.goApply")
              : t("brainstormingDecisions.notice.open")
          }}
        </LiveLink>
      </Button>
      <time :datetime="notification.createdAt" class="shrink-0">{{ when }}</time>
      <template v-if="data.sessionName">
        <span aria-hidden="true">·</span>
        <span class="truncate">{{ data.sessionName }}</span>
      </template>
    </div>
  </div>
</template>
