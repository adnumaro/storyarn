<script setup lang="ts">
import { GripVertical, Plus, Trash2, X } from "lucide-vue-next";
import { ref } from "vue";
import { Button } from "@components/ui/button/index.ts";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@components/ui/dialog/index.ts";
import { Input } from "@components/ui/input/index.ts";
import { Textarea } from "@components/ui/textarea/index.ts";
import { useLive } from "@composables/useLive";
import type { GalleryImage } from "../../../types";

const {
  blockId,
  images = [],
  canEdit = false,
} = defineProps<{
  blockId: number | string;
  images?: GalleryImage[];
  canEdit?: boolean;
}>();

const live = useLive();
const detailImage = ref<GalleryImage | null>(null);
const detailOpen = ref(false);

// ── Upload ──
function triggerUpload(): void {
  const input = document.createElement("input");
  input.type = "file";
  input.accept = "image/*";
  input.multiple = true;
  input.onchange = (e) => {
    Array.from((e.target as HTMLInputElement).files!).forEach((file) => {
      const reader = new FileReader();
      reader.onload = () => {
        live.pushEvent("upload_gallery_image", {
          block_id: blockId,
          filename: file.name,
          content_type: file.type,
          data: reader.result,
        });
      };
      reader.readAsDataURL(file);
    });
  };
  input.click();
}

// ── Detail modal ──
function openDetail(image: GalleryImage): void {
  detailImage.value = image;
  detailOpen.value = true;
}

function updateImageField(id: number | string, field: string, value: string): void {
  live.pushEvent("update_gallery_image", {
    gallery_image_id: id,
    field,
    value,
  });
}

function removeImage(id: number | string): void {
  live.pushEvent("remove_gallery_image", {
    gallery_image_id: id,
    block_id: blockId,
  });
  if (detailImage.value?.id === id) {
    detailOpen.value = false;
    detailImage.value = null;
  }
}

// ── Drag & drop reorder ──
let dragIndex: number | null = null;

function onDragStart(e: DragEvent, index: number): void {
  dragIndex = index;
  e.dataTransfer!.effectAllowed = "move";
  (e.target as HTMLElement).classList.add("opacity-30");
}

function onDragEnd(e: DragEvent): void {
  (e.target as HTMLElement).classList.remove("opacity-30");
  dragIndex = null;
}

function onDragOver(e: DragEvent): void {
  e.preventDefault();
  e.dataTransfer!.dropEffect = "move";
}

function onDrop(e: DragEvent, dropIndex: number): void {
  e.preventDefault();
  if (dragIndex === null || dragIndex === dropIndex) return;

  // Build new order
  const ids = images.map((img) => img.id);
  const [moved] = ids.splice(dragIndex, 1);
  ids.splice(dropIndex, 0, moved);

  live.pushEvent("reorder_gallery_images", {
    block_id: blockId,
    ids,
  });

  dragIndex = null;
}
</script>

<template>
  <div>
    <!-- Image grid -->
    <div v-if="images.length > 0" class="grid grid-cols-3 sm:grid-cols-4 gap-2">
      <div
        v-for="(img, i) in images"
        :key="img.id"
        class="group/thumb relative aspect-square rounded-lg overflow-hidden border border-border"
        :draggable="canEdit"
        @dragstart="onDragStart($event, i)"
        @dragend="onDragEnd"
        @dragover="onDragOver"
        @drop="onDrop($event, i)"
      >
        <button type="button" class="w-full h-full" @click="openDetail(img)">
          <img
            v-if="img.url"
            :src="img.url"
            :alt="img.label || ''"
            class="w-full h-full object-cover"
          />
        </button>

        <!-- Delete X -->
        <button
          v-if="canEdit"
          type="button"
          class="absolute top-1 right-1 size-5 rounded-full bg-black/70 flex items-center justify-center opacity-0 group-hover/thumb:opacity-100 transition-opacity"
          @click.stop="removeImage(img.id)"
        >
          <X class="size-3 text-white" />
        </button>

        <!-- Label -->
        <div v-if="img.label" class="absolute bottom-0 inset-x-0 bg-black/50 px-1.5 py-0.5">
          <p class="text-[10px] text-white truncate">{{ img.label }}</p>
        </div>
      </div>
    </div>

    <!-- Empty state -->
    <div v-else class="py-6 text-center text-sm text-muted-foreground">No images yet.</div>

    <!-- Upload button -->
    <div v-if="canEdit" class="mt-2">
      <Button
        variant="ghost"
        size="sm"
        class="gap-1.5 border border-dashed border-border text-xs"
        @click="triggerUpload"
      >
        <Plus class="size-3.5" />
        Add image
      </Button>
    </div>

    <!-- Detail modal -->
    <Dialog v-model:open="detailOpen">
      <DialogContent v-if="detailImage" class="max-w-lg">
        <DialogHeader>
          <DialogTitle>{{ detailImage.label || "Image" }}</DialogTitle>
        </DialogHeader>

        <!-- Full image -->
        <div class="flex justify-center bg-muted/20 rounded-lg overflow-hidden">
          <img
            :src="detailImage.url"
            :alt="detailImage.label || ''"
            class="max-w-full max-h-[50vh] object-contain"
          />
        </div>

        <!-- Label -->
        <div class="space-y-1">
          <label class="text-xs font-medium">Label</label>
          <Input
            :model-value="detailImage.label || ''"
            placeholder="Image label..."
            class="h-8 text-sm"
            :disabled="!canEdit"
            @blur="
              (e) =>
                updateImageField(detailImage!.id, 'label', (e.target as HTMLInputElement).value)
            "
          />
        </div>

        <!-- Description -->
        <div class="space-y-1">
          <label class="text-xs font-medium">Description</label>
          <Textarea
            :model-value="detailImage.description || ''"
            placeholder="Description..."
            :rows="2"
            class="text-sm resize-none"
            :disabled="!canEdit"
            @blur="
              (e) =>
                updateImageField(
                  detailImage!.id,
                  'description',
                  (e.target as HTMLTextAreaElement).value,
                )
            "
          />
        </div>

        <!-- Delete -->
        <div v-if="canEdit" class="flex justify-end">
          <Button
            variant="destructive"
            size="sm"
            class="gap-1"
            @click="removeImage(detailImage.id)"
          >
            <Trash2 class="size-3.5" />
            Delete
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  </div>
</template>
