<script setup lang="ts">
import { GitBranch, Settings } from "lucide-vue-next";
import { ToolbarSeparator } from "@components/toolbar/index.ts";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import { Badge } from "@components/ui/badge/index.ts";
import { Tabs, TabsList, TabsTrigger } from "@components/ui/tabs/index.ts";
import { useLive } from "../../../../shared/composables/useLive";
import type { Condition } from "../../types";
import type { NodeData } from "../../lib/node-configs";

defineOptions({ inheritAttrs: false });

interface ConditionToolbarData extends NodeData {
  switch_mode?: boolean;
  condition?: Condition;
}

const { nodeData } = defineProps<{
  nodeData: ConditionToolbarData;
}>();

const live = useLive();

function setSwitchMode(value: string | number) {
  const newSwitchMode = value === "routes";
  if (newSwitchMode !== !!nodeData.switch_mode) {
    live.pushEvent("toggle_switch_mode", {});
  }
}

function openBuilder() {
  live.pushEvent("open_builder", {});
}
</script>

<template>
  <component :is="GitBranch" class="size-4 opacity-60" />
  <ToolbarSeparator />
  <Tabs
    :model-value="nodeData.switch_mode ? 'routes' : 'multi'"
    @update:model-value="setSwitchMode"
  >
    <TabsList class="h-7 p-0.5 bg-background">
      <TabsTrigger value="multi" class="text-[10px] px-1.5 py-0 h-6">
        {{ $t("flows.condition_toolbar.multi") }}
      </TabsTrigger>
      <TabsTrigger value="routes" class="text-[10px] px-1.5 py-0 h-6">
        {{ $t("flows.condition_toolbar.routes") }}
      </TabsTrigger>
    </TabsList>
  </Tabs>
  <Badge
    v-if="nodeData.condition?.rules?.length"
    variant="secondary"
    class="text-[10px] px-1.5 py-0 rounded-full"
  >
    {{ nodeData.condition.rules.length }} rule{{ nodeData.condition.rules.length === 1 ? "" : "s" }}
  </Badge>
  <ToolbarSeparator />
  <ToolbarTooltip :label="$t('flows.condition_toolbar.edit_condition')">
    <button type="button" class="toolbar-btn" @click="openBuilder">
      <Settings class="size-3.5" />
    </button>
  </ToolbarTooltip>
</template>
