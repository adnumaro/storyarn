<script setup lang="ts">
import { Settings2, Eye, EyeOff } from "@lucide/vue";
import { useLive } from "@shared/composables/useLive";
import { ref } from "vue";
import { useBoardText, RoundControls, TimerControls } from "@modules/ideation";
import EditableText from "@components/forms/EditableText.vue";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import type { Session, Round, SessionTimer } from "@modules/ideation";
const { session, epoch, canManage, canEdit, rounds, roundsNext, activeRound, timer } = defineProps<{
  session: Session;
  timer: SessionTimer | null;
  rounds: Round[];
  roundsNext: number | null;
  activeRound: Round | null;
  epoch: string;
  canManage: boolean;
  canEdit: boolean;
}>();
const { t, error } = useBoardText();
const failure = ref<string | null>(null);
const live = useLive();
const pending = ref(false);
function setMode() {
  if (pending.value || !canManage) return;
  pending.value = true;
  failure.value = null;
  live.pushEvent(
    "set_private_mode",
    {
      epoch,
      session_id: session.id,
      revision: session.revision,
      enabled: !session.configuration.private_mode,
    },
    (reply) => {
      pending.value = false;
      if (reply?.status !== "ok") failure.value = String(reply?.code ?? "unavailable");
    },
    () => {
      pending.value = false;
      failure.value = "offline";
    },
  );
}
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
  <div class="relative flex h-8 min-w-0 items-center gap-1">
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
      class="mx-2 max-w-48 truncate text-xs font-medium"
      @save="rename"
    />
    <ToolbarTooltip :label="t('ideation.sessionSettings')" side="bottom"
      ><button
        type="button"
        class="toolbar-btn"
        :aria-label="t('ideation.sessionSettings')"
        @click="action('settings')"
      >
        <Settings2 class="size-3.5" /></button
    ></ToolbarTooltip>
    <RoundControls
      :session="session"
      :epoch="epoch"
      :rounds="rounds"
      :rounds-next="roundsNext"
      :active-round="activeRound"
      :can-manage="canManage"
      :can-edit="canEdit"
    />
    <TimerControls
      :session="session"
      :epoch="epoch"
      :timer="timer"
      :can-manage="canManage"
      :can-edit="canEdit"
    />
    <ToolbarTooltip
      :label="
        t(
          session.configuration.private_mode
            ? 'ideation.canvas.privateModeHelp'
            : 'ideation.canvas.sharedModeHelp',
        )
      "
      side="bottom"
    >
      <button
        type="button"
        class="toolbar-btn gap-1.5"
        :class="session.configuration.private_mode ? 'text-primary' : ''"
        :disabled="!canManage || !canEdit || session.status !== 'open' || pending"
        :aria-label="
          t(
            session.configuration.private_mode
              ? 'ideation.canvas.endPrivate'
              : 'ideation.canvas.startPrivate',
          )
        "
        @click="setMode"
      >
        <EyeOff v-if="session.configuration.private_mode" class="size-3.5" /><Eye
          v-else
          class="size-3.5"
        /><span class="hidden sm:inline">{{
          t(
            session.configuration.private_mode
              ? "ideation.canvas.privateMode"
              : "ideation.canvas.sharedMode",
          )
        }}</span>
      </button>
    </ToolbarTooltip>
  </div>
</template>
