<script setup lang="ts">
import { PlugZap } from "lucide-vue-next";
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import IntegrationCard, { type IntegrationCardData } from "./integrations/IntegrationCard.vue";

const { cards = [] } = defineProps<{
  cards: IntegrationCardData[];
}>();

const { t } = useI18n();

const connectedCards = computed(() => cards.filter((card) => card.status === "connected"));
const availableCards = computed(() => cards.filter((card) => card.status === "not_connected"));
</script>

<template>
  <div id="settings-integrations-page" class="space-y-8">
    <header class="max-w-3xl space-y-1.5">
      <h1 class="text-2xl font-bold tracking-tight text-foreground">
        {{ t("integrations.page.title") }}
      </h1>
      <p class="text-sm leading-relaxed text-muted-foreground">
        {{ t("integrations.page.description") }}
      </p>
    </header>

    <template v-if="cards.length > 0">
      <section
        v-if="connectedCards.length > 0"
        id="connected-integrations"
        class="space-y-3"
        aria-labelledby="connected-integrations-title"
      >
        <div class="flex items-end justify-between gap-4">
          <div class="space-y-1">
            <h2 id="connected-integrations-title" class="text-sm font-semibold text-foreground">
              {{ t("integrations.page.connected.title") }}
            </h2>
            <p class="text-xs leading-relaxed text-muted-foreground">
              {{ t("integrations.page.connected.description") }}
            </p>
          </div>
          <span
            class="rounded-full bg-muted px-2.5 py-1 text-[11px] font-medium text-muted-foreground"
          >
            {{ connectedCards.length }}
          </span>
        </div>

        <div class="space-y-3">
          <IntegrationCard v-for="card in connectedCards" :key="card.provider" :card="card" />
        </div>
      </section>

      <section
        v-if="availableCards.length > 0"
        id="available-integrations"
        class="space-y-3 border-t border-border/60 pt-7"
        aria-labelledby="available-integrations-title"
      >
        <div class="space-y-1">
          <h2 id="available-integrations-title" class="text-sm font-semibold text-foreground">
            {{ t("integrations.page.available.title") }}
          </h2>
          <p class="text-xs leading-relaxed text-muted-foreground">
            {{ t("integrations.page.available.description") }}
          </p>
        </div>

        <div
          class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3"
          :aria-label="t('integrations.page.providers_aria')"
        >
          <IntegrationCard v-for="card in availableCards" :key="card.provider" :card="card" />
        </div>
      </section>
    </template>

    <div
      v-else
      class="flex flex-col items-center gap-2 rounded-xl border border-dashed border-border/70 px-6 py-12 text-center"
    >
      <div class="flex size-10 items-center justify-center rounded-full bg-muted">
        <PlugZap class="size-5 text-muted-foreground" aria-hidden="true" />
      </div>
      <p class="text-sm text-muted-foreground">
        {{ t("integrations.empty.description") }}
      </p>
    </div>
  </div>
</template>
