<script setup>
import { ref, watch } from "vue";
import { useLive } from "@/vue/composables/useLive.js";

const props = defineProps({
	sheet: { type: Object, required: true },
	canEdit: { type: Boolean, default: false },
	isDraft: { type: Boolean, default: false },
	sourceShortcut: { type: String, default: null },
});

const live = useLive();

// ── Title editing ──
const editingName = ref(false);
const nameInput = ref(null);
const localName = ref(props.sheet.name);

watch(
	() => props.sheet.name,
	(v) => {
		localName.value = v;
	},
);

function startEditName() {
	if (!props.canEdit) return;
	editingName.value = true;
	setTimeout(() => nameInput.value?.focus(), 0);
}

function saveName() {
	editingName.value = false;
	const name = localName.value?.trim();
	if (name && name !== props.sheet.name) {
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
const localShortcut = ref(props.sheet.shortcut || "");

watch(
	() => props.sheet.shortcut,
	(v) => {
		localShortcut.value = v || "";
	},
);

function startEditShortcut() {
	if (!props.canEdit || props.isDraft) return;
	editingShortcut.value = true;
	setTimeout(() => shortcutInput.value?.focus(), 0);
}

function saveShortcut() {
	editingShortcut.value = false;
	const shortcut = localShortcut.value?.trim();
	if (shortcut !== (props.sheet.shortcut || "")) {
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
