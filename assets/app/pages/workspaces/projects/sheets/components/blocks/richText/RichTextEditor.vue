<script setup>
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

const { content, editable, placeholder } = defineProps({
  content: { type: String, default: "" },
  editable: { type: Boolean, default: false },
  placeholder: { type: String, default: "Write something..." },
});

const emit = defineEmits(["update"]);

let debounceTimer = null;

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
    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => {
      emit("update", editor.getHTML());
    }, 500);
  },
  onBlur: ({ editor }) => {
    clearTimeout(debounceTimer);
    emit("update", editor.getHTML());
  },
});

watch(
  () => content,
  (newContent) => {
    if (editor.value && !editor.value.isFocused && newContent !== editor.value.getHTML()) {
      editor.value.commands.setContent(newContent || "", false);
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
  clearTimeout(debounceTimer);
});

function toggleBold() {
  editor.value?.chain().focus().toggleBold().run();
}
function toggleItalic() {
  editor.value?.chain().focus().toggleItalic().run();
}
function toggleStrike() {
  editor.value?.chain().focus().toggleStrike().run();
}
function toggleH1() {
  editor.value?.chain().focus().toggleHeading({ level: 1 }).run();
}
function toggleH2() {
  editor.value?.chain().focus().toggleHeading({ level: 2 }).run();
}
function toggleH3() {
  editor.value?.chain().focus().toggleHeading({ level: 3 }).run();
}
function toggleBulletList() {
  editor.value?.chain().focus().toggleBulletList().run();
}
function toggleOrderedList() {
  editor.value?.chain().focus().toggleOrderedList().run();
}
function toggleBlockquote() {
  editor.value?.chain().focus().toggleBlockquote().run();
}
function setHorizontalRule() {
  editor.value?.chain().focus().setHorizontalRule().run();
}

function isActive(name, attrs) {
  return editor.value?.isActive(name, attrs) ?? false;
}
</script>

<template>
  <div class="rounded-md border border-input overflow-hidden bg-background">
    <!-- Toolbar (only if editable) -->
    <div
      v-if="editable && editor"
      class="flex flex-wrap items-center gap-0.5 px-1.5 py-1 border-b border-border bg-muted/30"
    >
      <button
        v-for="btn in [
          { action: toggleBold, icon: Bold, active: isActive('bold'), title: 'Bold' },
          { action: toggleItalic, icon: Italic, active: isActive('italic'), title: 'Italic' },
          {
            action: toggleStrike,
            icon: Strikethrough,
            active: isActive('strike'),
            title: 'Strikethrough',
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
            title: 'Heading 1',
          },
          {
            action: toggleH2,
            icon: Heading2,
            active: isActive('heading', { level: 2 }),
            title: 'Heading 2',
          },
          {
            action: toggleH3,
            icon: Heading3,
            active: isActive('heading', { level: 3 }),
            title: 'Heading 3',
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
            title: 'Bullet list',
          },
          {
            action: toggleOrderedList,
            icon: ListOrdered,
            active: isActive('orderedList'),
            title: 'Ordered list',
          },
          {
            action: toggleBlockquote,
            icon: Quote,
            active: isActive('blockquote'),
            title: 'Blockquote',
          },
          { action: setHorizontalRule, icon: Minus, active: false, title: 'Horizontal rule' },
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

    <!-- Editor -->
    <EditorContent :editor="editor" />
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
