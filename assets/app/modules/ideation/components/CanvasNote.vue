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
  roundNumber,
  canCreate = true,
  status = "saved",
} = defineProps<{
  note: Idea;
  body: string;
  editing: boolean;
  selected: boolean;
  author: string;
  roundNumber?: number;
  canCreate?: boolean;
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
      class: "outline-none",
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
        if (canCreate) emit("quickCreate");
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
    // TipTap emits `update` from setEditable by default, which would report a
    // phantom change (autosave + undo entry) on every open/close.
    editor.value?.setEditable(value, false);
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
const shape = computed(() => note.canvas?.shape ?? "rectangle");
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
    :data-round-id="note.round_id"
    :data-late-contribution="note.late_contribution"
    :data-note-shape="shape"
    class="canvas-note relative grid min-h-60 text-[#292d35] outline-none"
    :class="[`canvas-note--${shape}`, { 'canvas-note--selected': selected }]"
    :style="{ '--note-color': color }"
  >
    <span aria-hidden="true" class="note-outline" />
    <span aria-hidden="true" class="note-surface" />
    <div class="note-content relative z-10 flex min-w-0 flex-col p-5">
      <p v-if="note.title" class="mb-3 text-base font-semibold leading-snug">{{ note.title }}</p>
      <EditorContent
        :editor="editor"
        class="note-text min-w-0 flex-1 text-[17px] leading-relaxed"
        :class="editing ? 'cursor-text' : 'pointer-events-none select-none'"
        @pointerdown="editing && $event.stopPropagation()"
      />
      <footer
        class="mt-5 flex flex-wrap items-center justify-between gap-x-3 gap-y-1 text-[11px] opacity-65"
      >
        <span class="min-w-0">
          <span class="block truncate">{{ author }}</span>
          <span v-if="note.round_id" class="mt-1 block"
            >{{
              roundNumber
                ? t("ideation.rounds.number", { number: roundNumber })
                : t("ideation.rounds.assigned")
            }}<span v-if="note.late_contribution"> · {{ t("ideation.rounds.late") }}</span></span
          > </span
        ><span>{{ editing && status !== "saved" ? t(`ideation.saveStatus.${status}`) : "" }}</span>
      </footer>
    </div>
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
  --note-outline: inset(0 round 2px);
  overflow-wrap: anywhere;
}
.note-outline,
.note-surface,
.note-outline::after,
.note-surface::before {
  position: absolute;
  pointer-events: none;
}
.note-outline {
  inset: -6px;
  background: hsl(var(--primary));
  clip-path: var(--note-outline);
  opacity: 0;
  transition: opacity 120ms ease;
}
.note-outline::after {
  content: "";
  inset: 2px;
  background: hsl(var(--background));
  clip-path: var(--note-outline);
}
.canvas-note--selected .note-outline,
.canvas-note:focus-visible .note-outline {
  opacity: 1;
}
.note-surface {
  inset: 0;
  filter: drop-shadow(0 4px 4px rgb(0 0 0 / 0.16));
  transition: filter 120ms ease;
}
.note-surface::before {
  content: "";
  inset: 0;
  background: var(--note-color);
  clip-path: var(--note-outline);
}
.canvas-note--selected .note-surface,
.canvas-note:hover .note-surface {
  filter: drop-shadow(0 6px 7px rgb(0 0 0 / 0.2));
}
.canvas-note--rectangle .note-text :deep(.tiptap) {
  min-height: 9rem;
}
/* The center cell is an inscribed rectangle. Fractional rows grow with its
   content, keeping all text inside the outline without clipping the editor. */
.canvas-note--ellipse {
  --note-outline: ellipse(50% 50% at 50% 50%);
  grid-template-columns: minmax(0, 0.207107fr) minmax(0, 1fr) minmax(0, 0.207107fr);
  grid-template-rows: 0.207107fr 1fr 0.207107fr;
}
.canvas-note--diamond {
  --note-outline: polygon(50% 0, 100% 50%, 50% 100%, 0 50%);
  min-height: 280px;
  grid-template-columns: minmax(0, 1fr) minmax(0, 2fr) minmax(0, 1fr);
  grid-template-rows: 1fr 2fr 1fr;
}
.canvas-note--ellipse .note-content,
.canvas-note--diamond .note-content {
  grid-area: 2 / 2;
  padding: 12px;
}
@media (prefers-reduced-motion: reduce) {
  .note-outline,
  .note-surface {
    transition: none;
  }
}
</style>
