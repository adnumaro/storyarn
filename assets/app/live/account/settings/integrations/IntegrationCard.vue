<script setup lang="ts">
import { Building2, CheckCircle2, ChevronRight, CircleAlert, Cpu, Plug } from "lucide-vue-next";
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import LiveLink from "@components/navigation/LiveLink.vue";

export interface IntegrationCardData {
  provider: string;
  name: string;
  status: "not_connected" | "connected";
  account_email: string | null;
  account_display_name: string | null;
  key_last_four: string | null;
  workspace_count: number;
  compatible_model_count: number;
  catalog_status:
    | "not_connected"
    | "ready"
    | "connection_only"
    | "model_deprecated"
    | "model_unavailable";
  detail_path: string;
}

const { card } = defineProps<{
  card: IntegrationCardData;
}>();

const { t } = useI18n();

const connected = computed(() => card.status === "connected");

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
  return t("integrations.card.personal_connection");
});

function countLabel(singularKey: string, pluralKey: string, count: number): string {
  return t(count === 1 ? singularKey : pluralKey, { count });
}
</script>

<template>
  <LiveLink
    :to="card.detail_path"
    :class="[
      'group relative flex rounded-xl border border-border/70 bg-card shadow-sm transition-all duration-200',
      'hover:-translate-y-0.5 hover:border-primary/30 hover:shadow-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2',
      connected
        ? 'items-center gap-4 px-4 py-4 sm:px-5'
        : 'min-h-36 flex-col justify-between gap-5 p-4',
    ]"
    :data-provider="card.provider"
    :data-status="card.status"
    :data-layout="connected ? 'connected' : 'available'"
    :aria-label="t('integrations.card.open_details', { name: card.name })"
  >
    <div :class="['flex min-w-0 items-center gap-3', !connected && 'w-full']">
      <div
        aria-hidden="true"
        :class="[
          'flex shrink-0 items-center justify-center rounded-lg text-sm font-semibold transition-colors',
          connected
            ? 'size-11 bg-primary/10 text-primary'
            : 'size-10 bg-muted text-muted-foreground group-hover:bg-primary/10 group-hover:text-primary',
        ]"
      >
        {{ initials }}
      </div>

      <div class="min-w-0">
        <div class="flex min-w-0 flex-wrap items-center gap-1.5">
          <h3 class="truncate text-sm font-semibold text-foreground">{{ card.name }}</h3>
          <span
            v-if="connected && card.catalog_status !== 'ready'"
            class="inline-flex shrink-0 items-center gap-1 rounded-full bg-amber-500/10 px-1.5 py-0.5 text-[10px] font-medium text-amber-700 dark:text-amber-300"
            data-testid="catalog-warning"
          >
            <CircleAlert class="size-2.5" aria-hidden="true" />
            {{ t(`integrations.card.catalog_warnings.${card.catalog_status}`) }}
          </span>
        </div>
        <p
          v-if="connected"
          class="mt-1 flex min-w-0 items-center gap-1.5 text-xs text-emerald-600 dark:text-emerald-400"
        >
          <CheckCircle2 class="size-3.5 shrink-0" aria-hidden="true" />
          <span class="truncate">{{ identifier }}</span>
        </p>
        <p v-else class="mt-1 text-xs text-muted-foreground">
          {{ t("integrations.card.not_connected") }}
        </p>
      </div>
    </div>

    <div
      v-if="connected"
      class="ml-auto hidden shrink-0 items-center gap-5 text-xs text-muted-foreground sm:flex"
    >
      <span class="inline-flex items-center gap-1.5">
        <Building2 class="size-3.5" aria-hidden="true" />
        {{
          countLabel(
            "integrations.card.workspace_singular",
            "integrations.card.workspace_plural",
            card.workspace_count,
          )
        }}
      </span>
      <span class="inline-flex items-center gap-1.5">
        <Cpu class="size-3.5" aria-hidden="true" />
        {{
          countLabel(
            "integrations.card.model_singular",
            "integrations.card.model_plural",
            card.compatible_model_count,
          )
        }}
      </span>
    </div>

    <div v-else class="flex w-full items-end justify-between gap-4">
      <div class="space-y-1 text-xs text-muted-foreground">
        <p class="flex items-center gap-1.5">
          <Cpu class="size-3.5" aria-hidden="true" />
          {{
            countLabel(
              "integrations.card.model_singular",
              "integrations.card.model_plural",
              card.compatible_model_count,
            )
          }}
        </p>
        <p class="flex items-center gap-1.5 text-foreground">
          <Plug class="size-3.5 text-primary" aria-hidden="true" />
          {{ t("integrations.card.configure") }}
        </p>
      </div>
      <ChevronRight
        class="size-4 text-muted-foreground transition-transform group-hover:translate-x-0.5 group-hover:text-foreground"
        aria-hidden="true"
      />
    </div>

    <ChevronRight
      v-if="connected"
      class="size-4 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5 group-hover:text-foreground"
      aria-hidden="true"
    />
  </LiveLink>
</template>
