<script setup lang="ts">
import { Image, Trash2 } from "lucide-vue-next";
import { ref, watch } from "vue";
import ColorPickerPopover from "@components/forms/ColorPickerPopover.vue";
import { Button } from "@components/ui/button";
import { useLive } from "@shared/composables/useLive.ts";
import { useUpload } from "@shared/composables/useUpload.ts";
import type { Sheet } from "../../../types";
import AvatarGallery from "./AvatarGallery.vue";
import SheetAvatarSection from "./SheetAvatarSection.vue";
import SheetMetadata from "./SheetMetadata.vue";

const {
  sheet,
  canEdit = false,
  sourceShortcut = null,
} = defineProps<{
  sheet: Sheet;
  canEdit?: boolean;
  sourceShortcut?: string | null;
}>();

const live = useLive();
const { uploadFile, uploadFiles } = useUpload();

// ── Color picker ──
const localColor = ref(sheet.color || "#3b82f6");

watch(
  () => sheet.color,
  (v) => {
    localColor.value = v || "#3b82f6";
  },
);

function onColorUpdate(color: string): void {
  localColor.value = color;
  live.pushEvent("set_sheet_color", { color });
}

// ── Banner upload ──
function triggerBannerUpload(): void {
  const input = document.createElement("input");
  input.type = "file";
  input.accept = "image/*";
  input.onchange = async (e) => {
    const file = (e.target as HTMLInputElement).files?.[0];
    if (!file) return;
    const result = await uploadFile(file, "banner");
    if (result) live.pushEvent("attach_banner", { asset_id: result.id });
  };
  input.click();
}

function removeBanner(): void {
  live.pushEvent("remove_banner", {});
}

// ── Avatar upload ──
function triggerAvatarUpload(): void {
  const input = document.createElement("input");
  input.type = "file";
  input.accept = "image/*";
  input.multiple = true;
  input.onchange = async (e) => {
    const files = Array.from((e.target as HTMLInputElement).files ?? []);
    const results = await uploadFiles(files, "avatar");
    for (const result of results) {
      live.pushEvent("attach_avatar", { asset_id: result.id });
    }
  };
  input.click();
}

// ── Avatars ──
const galleryOpen = ref(false);

function setDefaultAvatar(id: number | string): void {
  live.pushEvent("set_default_avatar", { id });
}

function removeAvatar(id: number | string): void {
  live.pushEvent("remove_avatar", { id });
}

function updateAvatarName(id: number | string, value: string): void {
  live.pushEvent("gallery_update_name", { id, value });
}

function updateAvatarNotes(id: number | string, value: string): void {
  live.pushEvent("gallery_update_notes", { id, value });
}
</script>

<template>
  <div>
    <!-- Banner -->
    <div
      class="relative group h-48 sm:h-56 lg:h-64 overflow-hidden rounded-2xl mb-6"
      :style="sheet.bannerUrl ? {} : { backgroundColor: localColor }"
    >
      <!-- Banner image -->
      <img
        v-if="sheet.bannerUrl"
        :src="sheet.bannerUrl"
        alt=""
        class="w-full h-full object-cover"
      />

      <!-- Hover overlay (edit mode) -->
      <div
        v-if="canEdit"
        class="absolute inset-0 bg-black/0 group-hover:bg-black/30 transition-colors flex items-center justify-center opacity-0 group-hover:opacity-100"
      >
        <div class="flex gap-2">
          <Button
            variant="secondary"
            size="sm"
            class="bg-surface/80 hover:bg-surface gap-1.5"
            @click="triggerBannerUpload"
          >
            <Image class="size-4" />
            {{ sheet.bannerUrl ? $t("sheets.header.change_cover") : $t("sheets.header.add_cover") }}
          </Button>
          <Button
            v-if="sheet.bannerUrl"
            variant="secondary"
            size="sm"
            class="bg-surface/80 hover:bg-surface gap-1.5"
            @click="removeBanner"
          >
            <Trash2 class="size-4" />
            {{ $t("sheets.header.remove_cover") }}
          </Button>
        </div>
      </div>

      <!-- Color picker (bottom-right) -->
      <div v-if="canEdit" class="absolute bottom-3 right-3 z-10">
        <ColorPickerPopover :color="localColor" variant="full" @update:color="onColorUpdate" />
      </div>
    </div>

    <!-- Avatar + Title row -->
    <div class="flex items-start gap-4 mb-8 px-2">
      <!-- Avatar -->
      <SheetAvatarSection
        :sheet="sheet"
        :can-edit="canEdit"
        @trigger-upload="triggerAvatarUpload"
        @set-default="setDefaultAvatar"
        @remove="removeAvatar"
        @open-gallery="galleryOpen = true"
      />

      <!-- Title + Shortcut -->
      <SheetMetadata :sheet="sheet" :can-edit="canEdit" :source-shortcut="sourceShortcut" />
    </div>

    <!-- Avatar Gallery Dialog -->
    <AvatarGallery
      v-model:open="galleryOpen"
      :avatars="sheet.avatars || []"
      :can-edit="canEdit"
      @upload="triggerAvatarUpload"
      @set-default="setDefaultAvatar"
      @remove="removeAvatar"
      @update-name="updateAvatarName"
      @update-notes="updateAvatarNotes"
    />
  </div>
</template>
