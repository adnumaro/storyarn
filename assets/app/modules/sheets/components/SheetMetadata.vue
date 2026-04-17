<script setup lang="ts">
import { ref, watch } from "vue";
import { useLive } from "@composables/useLive";
import type { Sheet } from "../types";

const { sheet, canEdit = false } = defineProps<{
  sheet: Sheet;
  canEdit?: boolean;
  sourceShortcut?: string | null;
}>();

const live = useLive();

// ── Title editing ──
const editingName = ref(false);
const nameInput = ref<HTMLInputElement | null>(null);
const localName = ref(sheet.name);

watch(
  () => sheet.name,
  (v) => {
    localName.value = v;
  },
);

function startEditName(): void {
  if (!canEdit) return;
  editingName.value = true;
  setTimeout(() => nameInput.value?.focus(), 0);
}

function saveName(): void {
  editingName.value = false;
  const name = localName.value?.trim();
  if (name && name !== sheet.name) {
    live.pushEvent("save_name", { name });
  }
}

function onNameKeydown(e: KeyboardEvent): void {
  if (e.key === "Enter") {
    e.preventDefault();
    saveName();
  }
}

// ── Shortcut editing ──
const editingShortcut = ref(false);
const shortcutInput = ref<HTMLInputElement | null>(null);
const localShortcut = ref(sheet.shortcut || "");

watch(
  () => sheet.shortcut,
  (v) => {
    localShortcut.value = v || "";
  },
);

function startEditShortcut(): void {
  if (!canEdit) return;
  editingShortcut.value = true;
  setTimeout(() => shortcutInput.value?.focus(), 0);
}

function saveShortcut(): void {
  editingShortcut.value = false;
  const shortcut = localShortcut.value?.trim();
  if (shortcut !== (sheet.shortcut || "")) {
    live.pushEvent("save_shortcut", { shortcut: shortcut || "" });
  }
}

function onShortcutKeydown(e: KeyboardEvent): void {
  if (e.key === "Enter") {
    e.preventDefault();
    saveShortcut();
  }
}
</script>

<template>
  <div class="flex-1 min-w-0 pt-1">
    <!-- Name -->
    <div v-if="canEdit && editingName">
      <input
        ref="nameInput"
        v-model="localName"
        class="text-3xl font-bold w-full bg-transparent outline-none border-none px-0"
        :placeholder="$t('sheets.metadata.untitled')"
        @blur="saveName"
        @keydown="onNameKeydown"
      />
    </div>
    <h1
      v-else
      class="text-3xl font-bold"
      :class="canEdit && 'cursor-text hover:bg-accent/30 rounded px-1 -mx-1 transition-colors'"
      @click="startEditName"
    >
      {{ localName || $t("sheets.metadata.untitled") }}
    </h1>

    <!-- Shortcut -->
    <div class="mt-1 flex items-center gap-1">
      <span class="text-muted-foreground/50">#</span>
      <div v-if="canEdit && editingShortcut">
        <input
          ref="shortcutInput"
          v-model="localShortcut"
          class="text-sm text-muted-foreground bg-transparent outline-none border-none px-0"
          :placeholder="$t('sheets.metadata.add_shortcut')"
          @blur="saveShortcut"
          @keydown="onShortcutKeydown"
        />
      </div>
      <div
        v-else
        class="text-sm text-muted-foreground/50"
        :class="canEdit && 'cursor-text hover:text-muted-foreground transition-colors'"
        @click="startEditShortcut"
      >
        {{ localShortcut || (canEdit ? $t("sheets.metadata.add_shortcut") : "") }}
      </div>
    </div>
  </div>
</template>
