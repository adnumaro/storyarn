<script setup lang="ts">
import { watch } from "vue";
import { useI18n } from "vue-i18n";
import { EditorContent, useEditor } from "@tiptap/vue-3";
import StarterKit from "@tiptap/starter-kit";
import Placeholder from "@tiptap/extension-placeholder";
import { Bold, Italic, List, ListOrdered, Quote } from "@lucide/vue";
import { Button } from "@components/ui/button";
import { pasteContent } from "../lib/paste";

const {
  value,
  readonly = false,
  label,
} = defineProps<{ value: string; readonly?: boolean; label: string }>();
const emit = defineEmits<{ change: [value: string]; save: [] }>();
const { t } = useI18n();
const editor = useEditor({
  content: pasteContent(value),
  editable: !readonly,
  extensions: [
    StarterKit.configure({ link: false, horizontalRule: false, heading: { levels: [2, 3] } }),
    Placeholder.configure({ placeholder: t("ideation.bodyPlaceholder") }),
  ],
  editorProps: {
    attributes: {
      role: "textbox",
      "aria-label": label,
      "aria-multiline": "true",
      class: "min-h-40 outline-none p-3",
    },
    transformPastedHTML: pasteContent,
    handleKeyDown: (_view, event) => {
      if ((event.ctrlKey || event.metaKey) && event.key === "Enter") {
        emit("save");
        return true;
      }
      return false;
    },
  },
  onUpdate: ({ editor: instance }) => emit("change", instance.getHTML()),
});
watch(
  () => value,
  (next) => {
    if (editor.value && editor.value.getHTML() !== next) {
      editor.value.commands.setContent(pasteContent(next), { emitUpdate: false });
    }
  },
);
watch(
  () => readonly,
  (next) => editor.value?.setEditable(!next, false),
);
</script>

<template>
  <div class="overflow-hidden rounded-lg border bg-background">
    <div
      v-if="!readonly && editor"
      class="flex gap-1 border-b p-1"
      role="group"
      :aria-label="t('ideation.formatting')"
    >
      <Button
        variant="ghost"
        size="icon-sm"
        :aria-label="t('ideation.bold')"
        :aria-pressed="editor.isActive('bold')"
        @click="editor.chain().focus().toggleBold().run()"
        ><Bold class="size-4"
      /></Button>
      <Button
        variant="ghost"
        size="icon-sm"
        :aria-label="t('ideation.italic')"
        :aria-pressed="editor.isActive('italic')"
        @click="editor.chain().focus().toggleItalic().run()"
        ><Italic class="size-4"
      /></Button>
      <Button
        variant="ghost"
        size="icon-sm"
        :aria-label="t('ideation.bulletList')"
        @click="editor.chain().focus().toggleBulletList().run()"
        ><List class="size-4"
      /></Button>
      <Button
        variant="ghost"
        size="icon-sm"
        :aria-label="t('ideation.orderedList')"
        @click="editor.chain().focus().toggleOrderedList().run()"
        ><ListOrdered class="size-4"
      /></Button>
      <Button
        variant="ghost"
        size="icon-sm"
        :aria-label="t('ideation.quote')"
        @click="editor.chain().focus().toggleBlockquote().run()"
        ><Quote class="size-4"
      /></Button>
    </div>
    <EditorContent :editor="editor" class="prose prose-sm max-w-none dark:prose-invert" />
  </div>
</template>
