<script setup lang="ts">
import { onMounted, watch, nextTick, computed } from "vue";
import { EditorContent, useEditor } from "@tiptap/vue-3";
import { DOMParser } from "@tiptap/pm/model";
import StarterKit from "@tiptap/starter-kit";
import Placeholder from "@tiptap/extension-placeholder";
import { useI18n } from "vue-i18n";
import { pasteContent } from "../lib/paste";
import type { Idea } from "../types";
const {
  note,
  body,
  editing,
  selected,
  author,
  status = "saved",
} = defineProps<{
  note: Idea;
  body: string;
  editing: boolean;
  selected: boolean;
  author: string;
  status?: string;
}>();
const emit = defineEmits<{ change: [body: string]; finish: []; quickCreate: [] }>();
const { t } = useI18n();
const editor = useEditor({
  content: pasteContent(body),
  editable: editing,
  extensions: [
    StarterKit.configure({ link: false, heading: false, horizontalRule: false, codeBlock: false }),
    Placeholder.configure({ placeholder: t("ideation.canvas.write") }),
  ],
  editorProps: {
    attributes: {
      role: "textbox",
      "aria-label": t("ideation.body"),
      "aria-multiline": "true",
      class: "min-h-36 outline-none",
    },
    transformPastedHTML: pasteContent,
    handleKeyDown: (_, event) => {
      if (event.key === "Escape") {
        event.stopPropagation();
        emit("finish");
        return true;
      }
      if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
        event.stopPropagation();
        emit("quickCreate");
        return true;
      }
      return false;
    },
  },
  onUpdate: ({ editor }) => emit("change", editor.getHTML()),
});
async function focus() {
  await nextTick();
  if (editing) editor.value?.commands.focus("end");
}
watch(
  () => editing,
  (value) => {
    editor.value?.setEditable(value);
    if (value) void focus();
  },
);
watch(
  () => body,
  (value) => {
    const instance = editor.value;
    if (!instance) return;
    const container = document.createElement("div");
    container.innerHTML = pasteContent(value);
    const content = DOMParser.fromSchema(instance.schema).parse(container, {
      preserveWhitespace: "full",
    });
    // Server echoes may normalize HTML without changing the document. Keep the
    // same editor and native undo stack; remote replacements are not local edits.
    if (!instance.state.doc.eq(content))
      instance
        .chain()
        .setMeta("addToHistory", false)
        .setContent(content, { emitUpdate: false })
        .run();
  },
);
onMounted(focus);
const color = computed(
  () =>
    ({
      yellow: "#f5e6a8",
      coral: "#f8cbbd",
      mint: "#cbe8d5",
      blue: "#c9e2f5",
      violet: "#e2d5f4",
      paper: "#f4f1e9",
    })[note.canvas?.color ?? "yellow"] ?? "#f5e6a8",
);
</script>
<template>
  <article
    :id="`canvas-note-${note.id}`"
    tabindex="0"
    :aria-label="note.title || note.preview || t('ideation.untitled')"
    :aria-selected="selected"
    class="canvas-note flex min-h-60 flex-col rounded-sm p-5 text-[#292d35] shadow-md outline-none transition-shadow"
    :class="
      selected
        ? 'ring-2 ring-primary ring-offset-4 ring-offset-background shadow-lg'
        : 'hover:shadow-lg'
    "
    :style="{ backgroundColor: color }"
  >
    <p v-if="note.title" class="mb-3 text-base font-semibold leading-snug">{{ note.title }}</p>
    <EditorContent
      :editor="editor"
      class="note-text flex-1 text-[17px] leading-relaxed"
      :class="editing ? 'cursor-text' : 'pointer-events-none select-none'"
      @pointerdown="editing && $event.stopPropagation()"
    />
    <footer class="mt-5 flex items-center justify-between gap-3 text-[11px] opacity-65">
      <span class="truncate">{{ author }}</span
      ><span class="flex shrink-0 items-center gap-1">{{
        editing && status !== "saved" ? t(`ideation.saveStatus.${status}`) : ""
      }}</span>
    </footer>
  </article>
</template>
<style scoped>
.note-text :deep(p) {
  margin: 0 0 0.4em;
}
.note-text :deep(ul) {
  padding-left: 1.2em;
  list-style-type: disc;
}
.note-text :deep(ol) {
  padding-left: 1.2em;
  list-style-type: decimal;
}
.note-text :deep(.is-editor-empty:first-child::before) {
  content: attr(data-placeholder);
  float: left;
  height: 0;
  color: #59606b;
  pointer-events: none;
}
.canvas-note {
  overflow-wrap: anywhere;
}
</style>
