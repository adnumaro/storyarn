<script setup>
import { computed } from "@/vue/index.js";
import { useLive } from "@/vue/composables/useLive.js";
import {
	Link,
	Headphones,
	History,
	LayoutList,
} from "lucide-vue-next";
import { Tabs, TabsList, TabsTrigger } from "@/vue/components/ui/tabs/index.js";

const props = defineProps({
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
	props.compact ? allTabs.filter((t) => t.value !== "history") : allTabs,
);

function onTabChange(value) {
	if (value !== props.currentTab) {
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
