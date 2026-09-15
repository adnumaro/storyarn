<script setup lang="ts">
import { onMounted, watch, nextTick, computed } from "vue";
import { EditorContent, useEditor } from "@tiptap/vue-3";
import { DOMParser } from "@tiptap/pm/model";
import StarterKit from "@tiptap/starter-kit";
import Placeholder from "@tiptap/extension-placeholder";
import { useI18n } from "vue-i18n";
import { Bookmark, CircleX } from "@lucide/vue";
import { pasteContent } from "../lib/paste";
import type { Idea } from "../types";
import { noteFill, noteInk } from "../lib/noteColors";
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
// A note kept for later wears a tab and a dashed edge; a discarded one fades
// behind the others, struck through, and comes back to full strength while
// it is being edited.
const parked = computed(() => note.state === "parked");
const discarded = computed(() => note.state === "discarded");
const fill = computed(() => noteFill(note.canvas?.color));
const ink = computed(() => noteInk(note.canvas?.color) ?? undefined);
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
    :data-note-state="note.state"
    class="canvas-note relative grid text-foreground outline-none"
    :class="[
      `canvas-note--${shape}`,
      {
        'canvas-note--selected': selected,
        'canvas-note--editing': editing,
        'canvas-note--parked': parked,
        'canvas-note--discarded': discarded,
      },
    ]"
    :style="{ '--note-color': fill, '--note-ink': ink }"
  >
    <span aria-hidden="true" class="note-outline" />
    <span aria-hidden="true" class="note-surface" />
    <svg
      v-if="parked || discarded"
      aria-hidden="true"
      class="note-dash pointer-events-none absolute inset-0 h-full w-full overflow-visible"
      viewBox="0 0 100 100"
      preserveAspectRatio="none"
    >
      <ellipse v-if="shape === 'ellipse'" cx="50" cy="50" rx="50" ry="50" />
      <polygon v-else-if="shape === 'diamond'" points="50,0 100,50 50,100 0,50" />
      <rect v-else x="0" y="0" width="100" height="100" rx="2" />
    </svg>
    <span v-if="parked || discarded" aria-hidden="true" class="note-tab">
      <Bookmark v-if="parked" class="size-2.5" /><CircleX v-else class="size-2.5" />
      {{ t(parked ? "ideation.forLater" : "ideation.discarded") }}
    </span>
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
/* For later: the edge turns dashed and a tab sits over the top edge. */
.canvas-note--parked .note-surface {
  background: transparent;
}
/* Each state colours its own frame and tab, so a note kept for later and a
   discarded one read apart at a glance whatever the note's colour. */
.canvas-note--parked {
  --note-state: hsl(var(--primary));
}
.canvas-note--discarded {
  --note-state: hsl(var(--muted-foreground));
}
.note-dash {
  fill: none;
  stroke: var(--note-state);
  stroke-width: 1.5;
  stroke-dasharray: 4 3;
  vector-effect: non-scaling-stroke;
}
.note-dash > * {
  vector-effect: non-scaling-stroke;
}
.note-tab {
  position: absolute;
  top: 1px;
  left: 10px;
  z-index: 11;
  display: inline-flex;
  height: 18px;
  align-items: center;
  gap: 3px;
  padding: 0 7px 0 6px;
  transform: translateY(-100%);
  border: 1.5px dashed var(--note-state);
  border-bottom: 0;
  border-radius: 4px 4px 0 0;
  background: color-mix(in srgb, var(--note-state) 12%, hsl(var(--background)));
  font-size: 10px;
  font-weight: 600;
  line-height: 1;
  white-space: nowrap;
  color: var(--note-state);
}
.canvas-note--ellipse .note-tab,
.canvas-note--diamond .note-tab {
  left: 50%;
  transform: translate(-50%, -100%);
}
/* Discarded: the same frame and tab in grey, faded behind the others and
   struck through, back to full strength while it is being edited. */
.canvas-note--discarded {
  opacity: 0.55;
  filter: grayscale(1);
}
.canvas-note--discarded.canvas-note--editing {
  opacity: 1;
}
.canvas-note--discarded:not(.canvas-note--editing) .note-content p,
.canvas-note--discarded:not(.canvas-note--editing) .note-text :deep(p) {
  text-decoration: line-through 1.5px;
}
.canvas-note--plain .note-surface {
  background: transparent;
}
/* A text-only note wears its colour on the words, leaning on the theme's ink
   so it reads on both grounds. */
.canvas-note--plain .note-content {
  color: color-mix(in srgb, var(--note-ink, hsl(var(--foreground))) 80%, hsl(var(--foreground)));
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
