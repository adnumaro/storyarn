<script setup lang="ts">
import { Settings2 } from "@lucide/vue";
import { useLive } from "@shared/composables/useLive";
import { ref } from "vue";
import { useBoardText, TimerControls } from "@modules/ideation";
import EditableText from "@components/forms/EditableText.vue";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import type { Session, SessionTimer } from "@modules/ideation";
import ExplorationContext from "./ExplorationContext.vue";
import DecisionsButton from "./DecisionsButton.vue";
import type { BrainstormingReference } from "./referenceTypes";
const {
  session,
  epoch,
  canManage,
  canEdit,
  timer,
  contextReference = null,
} = defineProps<{
  session: Session;
  timer: SessionTimer | null;
  epoch: string;
  canManage: boolean;
  canEdit: boolean;
  contextReference?: BrainstormingReference | null;
}>();
const { t, error } = useBoardText();
const failure = ref<string | null>(null);
const live = useLive();
function action(action: string) {
  live.pushEvent("board_action", { action, epoch, session_id: session.id });
}
function rename(title: string) {
  failure.value = null;
  live.pushEvent(
    "update_session",
    { title, epoch, session_id: session.id, revision: session.revision },
    (reply) => {
      if (reply?.status !== "ok") failure.value = String(reply?.code ?? "unavailable");
    },
    () => {
      failure.value = "offline";
    },
  );
}
</script>
<template>
  <div class="@container relative flex h-8 min-w-0 flex-1 items-center gap-1">
    <ExplorationContext
      v-if="contextReference"
      :reference="contextReference"
      :session-id="session.id"
      :epoch="epoch"
      compact
    />
    <p
      v-if="failure"
      role="alert"
      class="surface-panel absolute left-0 top-full z-50 mt-2 max-w-sm p-3 text-xs text-destructive"
    >
      {{ error(failure) }}
    </p>
    <EditableText
      id="brainstorming-session-title"
      :model-value="session.title"
      :disabled="!canManage"
      class="mx-2 min-w-16 max-w-48 flex-1 truncate text-xs font-medium"
      @save="rename"
    />
    <DecisionsButton :session-id="session.id" :epoch="epoch" />
    <ToolbarTooltip :label="t('ideation.sessionSettings')" side="bottom"
      ><button
        type="button"
        class="toolbar-btn"
        :aria-label="t('ideation.sessionSettings')"
        @click="action('settings')"
      >
        <Settings2 class="size-3.5" /></button
    ></ToolbarTooltip>
    <TimerControls
      :session="session"
      :epoch="epoch"
      :timer="timer"
      :can-manage="canManage"
      :can-edit="canEdit"
    />
  </div>
</template>
