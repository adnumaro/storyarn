<script setup lang="ts">
import { PlugZap } from "lucide-vue-next";
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import ConfirmDialog from "@components/ConfirmDialog.vue";
import { useLive } from "@shared/composables/useLive";
import ConnectKeyDialog from "./integrations/ConnectKeyDialog.vue";
import IntegrationCard, { type IntegrationCardData } from "./integrations/IntegrationCard.vue";

const { cards = [] } = defineProps<{
  cards: IntegrationCardData[];
}>();

const { t } = useI18n();
const live = useLive();

const connectTarget = ref<IntegrationCardData | null>(null);
const disconnectTarget = ref<IntegrationCardData | null>(null);
const disconnectOpen = ref(false);
const connecting = ref(false);
const disconnecting = ref(false);
const inlineError = ref<string | null>(null);

// Sequence tokens: replies from a cancelled/superseded request must not
// mutate dialog state for a newer one. Bumped on every open/close/submit.
let connectSeq = 0;
let disconnectSeq = 0;

const disconnectDialogTitle = computed(() =>
  disconnectTarget.value
    ? t("integrations.disconnect.title", { name: disconnectTarget.value.name })
    : "",
);

const disconnectDialogDescription = computed(() =>
  disconnectTarget.value
    ? t("integrations.disconnect.description", { name: disconnectTarget.value.name })
    : "",
);

function openConnect(card: IntegrationCardData): void {
  inlineError.value = null;
  connectSeq += 1;
  connectTarget.value = card;
}

function closeConnect(): void {
  connectSeq += 1;
  connectTarget.value = null;
  connecting.value = false;
}

function openDisconnect(card: IntegrationCardData): void {
  inlineError.value = null;
  disconnectSeq += 1;
  disconnectTarget.value = card;
  disconnectOpen.value = true;
}

interface EventReply {
  status?: string;
  error?: string;
}

function submitConnect(apiKey: string, onResult: (errorCode: string | null) => void): void {
  const target = connectTarget.value;
  if (!target) {
    onResult("no_target");
    return;
  }

  const seq = ++connectSeq;
  connecting.value = true;

  live.pushEvent(
    "connect",
    { provider: target.provider, api_key: apiKey },
    (reply: EventReply) => {
      if (seq !== connectSeq) return;
      connecting.value = false;
      if (reply?.status === "ok") {
        closeConnect();
        onResult(null);
      } else {
        onResult(reply?.error ?? "unknown_error");
      }
    },
    () => {
      if (seq !== connectSeq) return;
      connecting.value = false;
      onResult("connection_lost");
    },
  );
}

function confirmDisconnect(): void {
  const target = disconnectTarget.value;
  if (!target) return;

  const seq = ++disconnectSeq;
  disconnecting.value = true;
  inlineError.value = null;

  live.pushEvent(
    "disconnect",
    { provider: target.provider },
    (reply: EventReply) => {
      if (seq !== disconnectSeq) return;
      disconnecting.value = false;
      if (reply?.status === "ok") {
        disconnectTarget.value = null;
      } else {
        inlineError.value = reply?.error ?? "unknown_error";
      }
    },
    () => {
      if (seq !== disconnectSeq) return;
      disconnecting.value = false;
      inlineError.value = "connection_lost";
    },
  );
}

function cancelDisconnect(): void {
  disconnectSeq += 1;
  disconnectTarget.value = null;
}
</script>

<template>
  <div id="settings-integrations-page" class="space-y-6">
    <header>
      <h1 class="text-lg font-semibold leading-8">
        {{ t("integrations.page.title") }}
      </h1>
      <p class="text-sm text-muted-foreground">
        {{ t("integrations.page.description") }}
      </p>
    </header>

    <div
      v-if="inlineError"
      role="alert"
      class="rounded-md border border-destructive/40 bg-destructive/5 px-3 py-2 text-sm text-destructive"
    >
      {{ t(`integrations.errors.${inlineError}`, t("integrations.errors.unknown_error")) }}
    </div>

    <section
      v-if="cards.length > 0"
      class="grid grid-cols-1 gap-4 sm:grid-cols-2"
      :aria-label="t('integrations.page.providers_aria')"
    >
      <IntegrationCard
        v-for="card in cards"
        :key="card.provider"
        :card="card"
        @connect="openConnect(card)"
        @disconnect="openDisconnect(card)"
      />
    </section>

    <div
      v-else
      class="flex flex-col items-center gap-2 rounded-lg border border-dashed border-border/60 px-6 py-10 text-center"
    >
      <PlugZap class="size-6 text-muted-foreground" />
      <p class="text-sm text-muted-foreground">
        {{ t("integrations.empty.description") }}
      </p>
    </div>

    <ConnectKeyDialog
      v-if="connectTarget"
      :open="!!connectTarget"
      :card="connectTarget"
      :submitting="connecting"
      @submit="submitConnect"
      @cancel="closeConnect"
    />

    <ConfirmDialog
      v-model:open="disconnectOpen"
      :title="disconnectDialogTitle"
      :description="disconnectDialogDescription"
      :confirm-text="t('integrations.disconnect.confirm')"
      :cancel-text="t('integrations.disconnect.cancel')"
      variant="destructive"
      @confirm="confirmDisconnect"
      @cancel="cancelDisconnect"
    />
  </div>
</template>
