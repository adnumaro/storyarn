<script setup lang="ts">
import { onMounted, onUnmounted, ref } from "vue";
import CommandPalette from "@components/command-palette/CommandPalette.vue";
import { accountPaletteCommands } from "@shared/command-palette/accountCommands";
import type { OperationDefinition } from "@shared/command-palette/operationCatalog";
import { GLOBAL_SURFACE, registerPaletteCommands } from "@shared/command-palette/registry";

interface PaletteFeatureFlags {
  aiIntegrations?: boolean;
}

const {
  featureFlags = {},
  operationCatalog = [],
  projectContext = false,
  sudoGrant = null,
} = defineProps<{
  featureFlags?: PaletteFeatureFlags;
  operationCatalog?: OperationDefinition[];
  projectContext?: boolean;
  sudoGrant?: string | null;
}>();

const ready = ref(false);

const unregisterGlobalCommands = registerPaletteCommands(
  GLOBAL_SURFACE,
  accountPaletteCommands(featureFlags, sudoGrant),
);

onMounted(() => {
  // Child mounted hooks (including the global keyboard listener) have run by
  // this point. E2E waits on this marker instead of racing Vue startup.
  ready.value = true;
});
onUnmounted(unregisterGlobalCommands);
</script>

<template>
  <div class="contents" :data-command-palette-ready="ready">
    <CommandPalette :operation-catalog="operationCatalog" :project-context="projectContext" />
  </div>
</template>
