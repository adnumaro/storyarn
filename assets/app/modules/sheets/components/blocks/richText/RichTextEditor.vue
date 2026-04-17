<script setup lang="ts">
import Placeholder from "@tiptap/extension-placeholder";
import StarterKit from "@tiptap/starter-kit";
import { EditorContent, useEditor } from "@tiptap/vue-3";
import {
  Bold,
  Heading1,
  Heading2,
  Heading3,
  Italic,
  List,
  ListOrdered,
  Minus,
  Quote,
  Strikethrough,
} from "lucide-vue-next";
import { onBeforeUnmount, watch } from "vue";

const {
  content = "",
  editable = false,
  placeholder = "Write something...",
} = defineProps<{
  content?: string;
  editable?: boolean;
  placeholder?: string;
}>();

const emit = defineEmits<{
  update: [html: string];
}>();

let debounceTimer: ReturnType<typeof setTimeout> | null = null;

const editor = useEditor({
  content: content || "",
  editable: editable,
  extensions: [StarterKit, Placeholder.configure({ placeholder: placeholder })],
  editorProps: {
    attributes: {
      class: "prose prose-sm dark:prose-invert max-w-none outline-none min-h-[80px] px-3 py-2",
    },
  },
  onUpdate: ({ editor }) => {
    if (debounceTimer) clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => {
      emit("update", editor.getHTML());
    }, 500);
  },
  onBlur: ({ editor }) => {
    if (debounceTimer) clearTimeout(debounceTimer);
    emit("update", editor.getHTML());
  },
});

watch(
  () => content,
  (newContent) => {
    if (editor.value && !editor.value.isFocused && newContent !== editor.value.getHTML()) {
      editor.value.commands.setContent(newContent || "", { emitUpdate: false });
    }
  },
);

watch(
  () => editable,
  (editable) => {
    editor.value?.setEditable(editable);
  },
);

onBeforeUnmount(() => {
  if (debounceTimer) clearTimeout(debounceTimer);
});

function toggleBold(): void {
  editor.value?.chain().focus().toggleBold().run();
}
function toggleItalic(): void {
  editor.value?.chain().focus().toggleItalic().run();
}
function toggleStrike(): void {
  editor.value?.chain().focus().toggleStrike().run();
}
function toggleH1(): void {
  editor.value?.chain().focus().toggleHeading({ level: 1 }).run();
}
function toggleH2(): void {
  editor.value?.chain().focus().toggleHeading({ level: 2 }).run();
}
function toggleH3(): void {
  editor.value?.chain().focus().toggleHeading({ level: 3 }).run();
}
function toggleBulletList(): void {
  editor.value?.chain().focus().toggleBulletList().run();
}
function toggleOrderedList(): void {
  editor.value?.chain().focus().toggleOrderedList().run();
}
function toggleBlockquote(): void {
  editor.value?.chain().focus().toggleBlockquote().run();
}
function setHorizontalRule(): void {
  editor.value?.chain().focus().setHorizontalRule().run();
}

function isActive(name: string, attrs?: { level?: number }): boolean {
  return editor.value?.isActive(name, attrs) ?? false;
}
</script>

<template>
  <div class="rounded-md border border-input overflow-hidden bg-card">
    <!-- Toolbar (only if editable) -->
    <div
      v-if="editable && editor"
      class="flex flex-wrap items-center gap-0.5 px-1.5 py-1 border-b border-border bg-muted/30"
    >
      <button
        v-for="btn in [
          { action: toggleBold, icon: Bold, active: isActive('bold'), title: $t('sheets.rich_text_editor.bold') },
          { action: toggleItalic, icon: Italic, active: isActive('italic'), title: $t('sheets.rich_text_editor.italic') },
          {
            action: toggleStrike,
            icon: Strikethrough,
            active: isActive('strike'),
            title: $t('sheets.rich_text_editor.strikethrough'),
          },
        ]"
        :key="btn.title"
        type="button"
        :class="[
          'size-7 rounded flex items-center justify-center transition-colors',
          btn.active
            ? 'bg-accent text-accent-foreground'
            : 'text-muted-foreground hover:bg-accent hover:text-accent-foreground',
        ]"
        :title="btn.title"
        @click="btn.action"
      >
        <component :is="btn.icon" class="size-3.5" />
      </button>

      <div class="w-px h-4 bg-border mx-0.5" />

      <button
        v-for="btn in [
          {
            action: toggleH1,
            icon: Heading1,
            active: isActive('heading', { level: 1 }),
            title: $t('sheets.rich_text_editor.h1'),
          },
          {
            action: toggleH2,
            icon: Heading2,
            active: isActive('heading', { level: 2 }),
            title: $t('sheets.rich_text_editor.h2'),
          },
          {
            action: toggleH3,
            icon: Heading3,
            active: isActive('heading', { level: 3 }),
            title: $t('sheets.rich_text_editor.h3'),
          },
        ]"
        :key="btn.title"
        type="button"
        :class="[
          'size-7 rounded flex items-center justify-center transition-colors',
          btn.active
            ? 'bg-accent text-accent-foreground'
            : 'text-muted-foreground hover:bg-accent hover:text-accent-foreground',
        ]"
        :title="btn.title"
        @click="btn.action"
      >
        <component :is="btn.icon" class="size-3.5" />
      </button>

      <div class="w-px h-4 bg-border mx-0.5" />

      <button
        v-for="btn in [
          {
            action: toggleBulletList,
            icon: List,
            active: isActive('bulletList'),
            title: $t('sheets.rich_text_editor.bullet_list'),
          },
          {
            action: toggleOrderedList,
            icon: ListOrdered,
            active: isActive('orderedList'),
            title: $t('sheets.rich_text_editor.ordered_list'),
          },
          {
            action: toggleBlockquote,
            icon: Quote,
            active: isActive('blockquote'),
            title: $t('sheets.rich_text_editor.blockquote'),
          },
          { action: setHorizontalRule, icon: Minus, active: false, title: $t('sheets.rich_text_editor.hr') },
        ]"
        :key="btn.title"
        type="button"
        :class="[
          'size-7 rounded flex items-center justify-center transition-colors',
          btn.active
            ? 'bg-accent text-accent-foreground'
            : 'text-muted-foreground hover:bg-accent hover:text-accent-foreground',
        ]"
        :title="btn.title"
        @click="btn.action"
      >
        <component :is="btn.icon" class="size-3.5" />
      </button>
    </div>

    <!-- Editor — stop keydown propagation to prevent @vue-dnd-kit from intercepting -->
    <EditorContent :editor="editor" @keydown.stop />
  </div>
</template>

<style>
/* TipTap placeholder */
.tiptap p.is-editor-empty:first-child::before {
  content: attr(data-placeholder);
  float: left;
  color: hsl(var(--muted-foreground));
  pointer-events: none;
  height: 0;
}
</style>
