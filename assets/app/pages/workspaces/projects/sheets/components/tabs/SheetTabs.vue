<script setup>
import { Headphones, History, LayoutList, Link } from "lucide-vue-next";
import { computed } from "vue";
import { Tabs, TabsList, TabsTrigger } from "@components/ui/tabs/index.js";
import { useLive } from "@composables/useLive.js";

const { currentTab, canEdit, compact } = defineProps({
  currentTab: { type: String, default: "content" },
  canEdit: { type: Boolean, default: false },
  compact: { type: Boolean, default: false },
});

const live = useLive();

const allTabs = [
  { value: "content", label: "Content", icon: LayoutList },
  { value: "references", label: "References", icon: Link },
  { value: "audio", label: "Audio", icon: Headphones },
  { value: "history", label: "History", icon: History },
];

const tabs = computed(() =>
  compact ? allTabs.filter((t) => t.value !== "history") : allTabs,
);

function onTabChange(value) {
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
