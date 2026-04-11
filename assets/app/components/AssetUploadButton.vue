<script setup lang="ts">
import { Upload } from "lucide-vue-next";
import { useLive } from "@composables/useLive";

const MAX_FILE_SIZE = 20 * 1024 * 1024;

const { uploading = false } = defineProps<{
  uploading?: boolean;
}>();

const live = useLive();

function handleFileChange(event: Event): void {
  const input = event.target as HTMLInputElement;
  const file = input.files?.[0];
  if (!file) return;

  input.value = "";

  if (file.size > MAX_FILE_SIZE) {
    live.pushEvent("upload_validation_error", {
      message: "File too large (max 20MB).",
    });
    return;
  }

  live.pushEvent("upload_started", {});

  const reader = new FileReader();
  reader.onload = () => {
    live.pushEvent("upload_asset", {
      filename: file.name,
      content_type: file.type,
      data: reader.result,
    });
  };
  reader.readAsDataURL(file);
}
</script>

<template>
  <div class="flex items-center px-1.5 py-1 surface-panel">
    <label
      :class="[
        'inline-flex items-center justify-center h-8 px-3 text-sm rounded-md hover:bg-accent transition-colors gap-1.5 cursor-pointer',
        uploading && 'pointer-events-none opacity-50',
      ]"
    >
      <Upload class="size-4" />
      <span class="hidden xl:inline">
        {{ uploading ? "Uploading..." : "Upload" }}
      </span>
      <input
        type="file"
        accept="image/*,audio/*"
        class="hidden"
        @change="handleFileChange"
      />
    </label>
  </div>
</template>
