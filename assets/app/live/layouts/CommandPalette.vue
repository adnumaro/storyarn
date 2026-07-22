<script setup lang="ts">
import { onUnmounted } from "vue";
import CommandPalette from "@components/command-palette/CommandPalette.vue";
import { accountPaletteCommands } from "@shared/command-palette/accountCommands";
import { GLOBAL_SURFACE, registerPaletteCommands } from "@shared/command-palette/registry";

interface PaletteFeatureFlags {
  aiIntegrations?: boolean;
}

const { featureFlags = {} } = defineProps<{
  featureFlags?: PaletteFeatureFlags;
}>();

const unregisterGlobalCommands = registerPaletteCommands(
  GLOBAL_SURFACE,
  accountPaletteCommands(featureFlags),
);

onUnmounted(unregisterGlobalCommands);
</script>

<template>
  <CommandPalette />
</template>
