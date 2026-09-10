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
    :aria-describedby="`canvas-note-meta-${note.id}`"
    :aria-selected="selected"
    :data-round-id="note.round_id"
    :data-late-contribution="note.late_contribution"
    :data-note-shape="shape"
    class="canvas-note relative grid text-foreground outline-none"
    :class="[
      `canvas-note--${shape}`,
      { 'canvas-note--selected': selected, 'canvas-note--editing': editing },
    ]"
    :style="{ '--note-color': color }"
  >
    <span aria-hidden="true" class="note-outline" />
    <span aria-hidden="true" class="note-surface" />
    <div class="note-content relative z-10 min-w-0">
      <p v-if="note.title" class="mb-1.5 text-[15px] font-semibold leading-snug">
        {{ note.title }}
      </p>
      <EditorContent
        :editor="editor"
        class="note-text min-w-0 text-[15px] leading-normal"
        :class="editing ? 'cursor-text' : 'pointer-events-none select-none'"
        @pointerdown="editing && $event.stopPropagation()"
      />
    </div>
    <div
      :id="`canvas-note-meta-${note.id}`"
      class="note-metadata pointer-events-none absolute left-1/2 top-full z-10 flex -translate-x-1/2 items-center gap-1.5 pt-1.5 text-[10px] leading-4 text-muted-foreground"
    >
      <span class="truncate">{{ author }}</span>
      <span v-if="note.round_id" class="shrink-0">
        ·
        {{
          roundNumber
            ? t("ideation.rounds.number", { number: roundNumber })
            : t("ideation.rounds.assigned")
        }}<span v-if="note.late_contribution"> · {{ t("ideation.rounds.late") }}</span>
      </span>
      <span v-if="editing && status !== 'saved'" class="shrink-0">
        · {{ t(`ideation.saveStatus.${status}`) }}
      </span>
    </div>
  </article>
</template>
<style scoped>
.note-text :deep(p) {
  margin: 0 0 0.35em;
}
.note-text :deep(p:last-child) {
  margin-bottom: 0;
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
  color: hsl(var(--muted-foreground));
  pointer-events: none;
}
.canvas-note {
  --note-outline: inset(0 round 4px);
  --note-fill: color-mix(in srgb, var(--note-color) 13%, hsl(var(--background)));
  --note-border: color-mix(in srgb, var(--note-color) 35%, hsl(var(--border)));
  width: fit-content;
  max-width: 100%;
  overflow-wrap: anywhere;
}
.note-content {
  padding: 10px 12px;
}
.note-outline,
.note-surface,
.note-outline::after,
.note-surface::before {
  position: absolute;
  pointer-events: none;
}
.note-outline {
  inset: -3px;
  background: hsl(var(--primary));
  clip-path: var(--note-outline);
  opacity: 0;
  transition: opacity 120ms ease;
}
.note-outline::after {
  content: "";
  inset: 1.5px;
  background: hsl(var(--background));
  clip-path: var(--note-outline);
}
.canvas-note--selected .note-outline,
.canvas-note--editing .note-outline,
.canvas-note:focus-visible .note-outline {
  opacity: 1;
}
.note-surface {
  inset: 0;
  background: var(--note-border);
  clip-path: var(--note-outline);
}
.note-surface::before {
  content: "";
  inset: 1px;
  background: var(--note-fill);
  clip-path: var(--note-outline);
}
.canvas-note--plain .note-surface {
  background: transparent;
}
.canvas-note--plain .note-surface::before {
  background: transparent;
}
.canvas-note--plain.canvas-note--selected .note-surface::before,
.canvas-note--plain.canvas-note--editing .note-surface::before {
  background: color-mix(in srgb, var(--note-color) 5%, hsl(var(--background)));
}
/* The persisted width limits writing space. Expand the outline around that
   space instead of narrowing the text when its shape changes. Metadata stays
   outside the measured note, and there is no minimum card height. */
.canvas-note--ellipse {
  --note-outline: ellipse(50% 50% at 50% 50%);
  width: max-content;
  max-width: 141.421356%;
  grid-template-columns: minmax(0, 0.207107fr) minmax(0, 1fr) minmax(0, 0.207107fr);
  grid-template-rows: 0.207107fr 1fr 0.207107fr;
}
.canvas-note--diamond {
  --note-outline: polygon(50% 0, 100% 50%, 50% 100%, 0 50%);
  width: max-content;
  max-width: 200%;
  grid-template-columns: minmax(0, 1fr) minmax(0, 2fr) minmax(0, 1fr);
  grid-template-rows: 1fr 2fr 1fr;
}
.canvas-note--ellipse .note-content,
.canvas-note--diamond .note-content {
  grid-area: 2 / 2;
  padding: 8px 10px;
}
.note-metadata {
  width: max-content;
  max-width: 320px;
  opacity: 0;
  transition: opacity 120ms ease;
}
.canvas-note:hover .note-metadata,
.canvas-note--selected .note-metadata,
.canvas-note:focus-within .note-metadata {
  opacity: 1;
}
@media (prefers-reduced-motion: reduce) {
  .note-outline,
  .note-metadata {
    transition: none;
  }
}
</style>
