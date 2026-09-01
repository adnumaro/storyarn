<script setup lang="ts">
/**
 * Props-driven facade over the app's Tabs compound. The tab strip is driven
 * by `tabs`; the React children render below as the active panel (the design
 * decides what to show for the current value).
 */
import { Tabs, TabsList, TabsTrigger } from "@components/ui/tabs";

export interface TabItem {
  value: string;
  label: string;
  disabled?: boolean;
}

const { tabs = [] } = defineProps<{
  tabs?: TabItem[];
  class?: string;
}>();

const modelValue = defineModel<string>();
</script>

<template>
  <Tabs v-model="modelValue" :class="$props.class">
    <TabsList>
      <TabsTrigger v-for="tab in tabs" :key="tab.value" :value="tab.value" :disabled="tab.disabled">
        {{ tab.label }}
      </TabsTrigger>
    </TabsList>
    <slot />
  </Tabs>
</template>
