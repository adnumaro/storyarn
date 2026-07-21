<script setup lang="ts">
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import {
  CommandDialog,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
  CommandShortcut,
} from "@components/ui/command";
import { useKeyboard } from "@shared/composables/useKeyboard";
import { useLive } from "@shared/composables/useLive";
import {
  paletteGroups,
  primarySurface,
  type PaletteCommand,
} from "@shared/command-palette/registry";
import PaletteEmpty from "./PaletteEmpty.vue";

const { t } = useI18n();
const live = useLive();

const open = ref(false);
const query = ref("");

const localOpen = computed({
  get: () => open.value,
  set: (value: boolean) => {
    if (value) {
      openPalette();
    } else {
      closePalette();
    }
  },
});

useKeyboard({
  "ctrl+k": () => {
    if (open.value) {
      closePalette();
    } else {
      openPalette();
    }
  },
});

function openPalette(): void {
  query.value = "";
  open.value = true;
  track("palette_opened", {});
}

function closePalette(): void {
  open.value = false;
}

function onSelect(command: PaletteCommand): void {
  track("palette_command_executed", { command_id: command.id });
  closePalette();
  command.run();
}

function onNoResults(queryLength: number): void {
  track("palette_search_no_results", { query_length: queryLength });
}

function commandLabel(command: PaletteCommand): string {
  if (command.label !== undefined) return command.label;
  return t(command.labelKey);
}

// Analytics is fire-and-forget: a dropped event must never break the palette
// (pushEvent throws when the socket is gone mid-navigation).
function track(event: string, payload: Record<string, unknown>): void {
  try {
    live.pushEvent(event, { ...payload, surface: primarySurface.value });
  } catch {
    // socket unavailable — drop the analytics event, never the interaction
  }
}
</script>

<template>
  <CommandDialog
    v-model:open="localOpen"
    :title="t('palette.title')"
    :description="t('palette.description')"
  >
    <CommandInput v-model="query" :placeholder="t('palette.placeholder')" />
    <CommandList>
      <PaletteEmpty @no-results="onNoResults">{{ t("palette.no_results") }}</PaletteEmpty>
      <CommandGroup v-for="group in paletteGroups" :key="group.key" :heading="t(group.key)">
        <CommandItem
          v-for="command in group.commands"
          :key="command.id"
          :value="command.id"
          @select="onSelect(command)"
        >
          <component :is="command.icon" v-if="command.icon" class="size-4 shrink-0" />
          <span>{{ commandLabel(command) }}</span>
          <CommandShortcut v-if="command.shortcut">{{ command.shortcut }}</CommandShortcut>
        </CommandItem>
      </CommandGroup>
    </CommandList>
  </CommandDialog>
</template>
