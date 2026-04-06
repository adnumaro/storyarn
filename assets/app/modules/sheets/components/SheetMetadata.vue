<script setup>
import { ref, watch } from "vue";
import { useLive } from "@composables/useLive";

const { sheet, canEdit, isDraft, sourceShortcut } = defineProps({
  sheet: { type: Object, required: true },
  canEdit: { type: Boolean, default: false },
  isDraft: { type: Boolean, default: false },
  sourceShortcut: { type: String, default: null },
});

const live = useLive();

// ── Title editing ──
const editingName = ref(false);
const nameInput = ref(null);
const localName = ref(sheet.name);

watch(
  () => sheet.name,
  (v) => {
    localName.value = v;
  },
);

function startEditName() {
  if (!canEdit) return;
  editingName.value = true;
  setTimeout(() => nameInput.value?.focus(), 0);
}

function saveName() {
  editingName.value = false;
  const name = localName.value?.trim();
  if (name && name !== sheet.name) {
    live.pushEvent("save_name", { name });
  }
}

function onNameKeydown(e) {
  if (e.key === "Enter") {
    e.preventDefault();
    saveName();
  }
}

// ── Shortcut editing ──
const editingShortcut = ref(false);
const shortcutInput = ref(null);
const localShortcut = ref(sheet.shortcut || "");

watch(
  () => sheet.shortcut,
  (v) => {
    localShortcut.value = v || "";
  },
);

function startEditShortcut() {
  if (!canEdit || isDraft) return;
  editingShortcut.value = true;
  setTimeout(() => shortcutInput.value?.focus(), 0);
}

function saveShortcut() {
  editingShortcut.value = false;
  const shortcut = localShortcut.value?.trim();
  if (shortcut !== (sheet.shortcut || "")) {
    live.pushEvent("save_shortcut", { shortcut: shortcut || "" });
  }
}

function onShortcutKeydown(e) {
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
        placeholder="Untitled"
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
      {{ sheet.name || "Untitled" }}
    </h1>

    <!-- Shortcut -->
    <div class="mt-1 flex items-center gap-1">
      <span class="text-muted-foreground/50">#</span>
      <div v-if="isDraft && sourceShortcut" class="text-sm text-muted-foreground/40">
        {{ sourceShortcut }}
      </div>
      <div v-else-if="canEdit && editingShortcut">
        <input
          ref="shortcutInput"
          v-model="localShortcut"
          class="text-sm text-muted-foreground bg-transparent outline-none border-none px-0"
          placeholder="add-shortcut"
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
        {{ sheet.shortcut || (canEdit ? "add-shortcut" : "") }}
      </div>
    </div>
  </div>
</template>
