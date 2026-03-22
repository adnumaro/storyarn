<script setup>
import { useLive } from "@/vue/composables/useLive";
import {
	Link,
	Headphones,
	History,
	LayoutList,
} from "lucide-vue-next";
import { Tabs, TabsList, TabsTrigger } from "@/vue/components/ui/tabs";

const props = defineProps({
	currentTab: { type: String, default: "content" },
	canEdit: { type: Boolean, default: false },
});

const live = useLive();

const tabs = [
	{ value: "content", label: "Content", icon: LayoutList },
	{ value: "references", label: "References", icon: Link },
	{ value: "audio", label: "Audio", icon: Headphones },
	{ value: "history", label: "History", icon: History },
];

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
