<script setup lang="ts">
import { CheckCircle2, ExternalLink } from "lucide-vue-next";
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { Button } from "@components/ui/button";

export interface IntegrationCardData {
  provider: string;
  name: string;
  key_generation_url: string;
  docs_url: string;
  key_placeholder: string;
  status: "not_connected" | "connected";
  account_email: string | null;
  account_display_name: string | null;
  key_last_four: string | null;
  connected_at: string | null;
}

const { card } = defineProps<{
  card: IntegrationCardData;
}>();

const emit = defineEmits<{
  connect: [];
  disconnect: [];
}>();

const { t } = useI18n();

const isConnected = computed(() => card.status === "connected");

const initials = computed(() =>
  card.name
    .split(/\s+/)
    .map((part) => part.charAt(0).toUpperCase())
    .join("")
    .slice(0, 2),
);

const identifier = computed(() => {
  if (card.account_email) return card.account_email;
  if (card.account_display_name) return card.account_display_name;
  if (card.key_last_four) return t("integrations.card.key_suffix", { suffix: card.key_last_four });
  return "";
});
</script>

<template>
  <article
    class="flex flex-col gap-4 rounded-lg border border-border/60 bg-card p-4 transition-colors hover:border-border"
    :data-provider="card.provider"
    :data-status="card.status"
  >
    <header class="flex items-start justify-between gap-3">
      <div class="flex items-center gap-3">
        <div
          aria-hidden="true"
          class="flex size-10 items-center justify-center rounded-md bg-muted text-sm font-semibold text-muted-foreground"
        >
          {{ initials }}
        </div>
        <div>
          <h2 class="text-sm font-semibold leading-tight">{{ card.name }}</h2>
          <p
            v-if="isConnected"
            class="mt-0.5 flex items-center gap-1 text-xs text-emerald-600 dark:text-emerald-400"
          >
            <CheckCircle2 class="size-3" aria-hidden="true" />
            <span>{{ t("integrations.card.connected_as", { identifier }) }}</span>
          </p>
          <p v-else class="mt-0.5 text-xs text-muted-foreground">
            {{ t("integrations.card.not_connected") }}
          </p>
        </div>
      </div>
    </header>

    <footer class="flex items-center justify-between gap-2">
      <a
        :href="card.docs_url"
        target="_blank"
        rel="noopener noreferrer"
        data-live-link-exempt="external-provider-docs"
        class="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground hover:underline"
      >
        {{ t("integrations.card.docs") }}
        <ExternalLink class="size-3" aria-hidden="true" />
      </a>

      <Button v-if="isConnected" variant="outline" size="sm" @click="emit('disconnect')">
        {{ t("integrations.card.disconnect") }}
      </Button>
      <Button v-else size="sm" @click="emit('connect')">
        {{ t("integrations.card.connect") }}
      </Button>
    </footer>
  </article>
</template>
