<script setup lang="ts">
import { Headphones, History, LayoutList, Link } from "lucide-vue-next";
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { Tabs, TabsList, TabsTrigger } from "@components/ui/tabs/index.ts";
import { useLive } from "@composables/useLive";
import type { TabDefinition } from "../../types";

const {
  currentTab = "content",
  canEdit = false,
  compact = false,
} = defineProps<{
  currentTab?: string;
  canEdit?: boolean;
  compact?: boolean;
}>();

const live = useLive();
const { t } = useI18n();

const allTabs = computed<TabDefinition[]>(() => [
  { value: "content", label: t("sheets.tabs.content"), icon: LayoutList },
  { value: "references", label: t("sheets.tabs.references"), icon: Link },
  { value: "audio", label: t("sheets.tabs.audio"), icon: Headphones },
  { value: "history", label: t("sheets.tabs.history"), icon: History },
]);

const tabs = computed(() =>
  compact ? allTabs.value.filter((t) => t.value !== "history") : allTabs.value,
);

function onTabChange(value: string | number): void {
  if (value !== currentTab) {
    live.pushEvent("switch_tab", { tab: value });
  }
}
</script>

<template>
  <Tabs :model-value="currentTab" @update:model-value="onTabChange" class="mb-5">
    <TabsList class="h-8">
      <TabsTrigger
        v-for="tab in tabs"
        :key="tab.value"
        :value="tab.value"
        :disabled="tab.disabled"
        class="gap-1.5 text-xs px-3"
      >
        <component :is="tab.icon" class="size-3.5" />
        {{ tab.label }}
      </TabsTrigger>
    </TabsList>
  </Tabs>
</template>
