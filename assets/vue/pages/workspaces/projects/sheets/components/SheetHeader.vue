<script setup>
import { ref, computed, watch } from "@/vue/index.js";
import { useLive } from "@/vue/composables/useLive.js";
import { Image, Trash2, X, Plus, LayoutGrid, Star } from "lucide-vue-next";
import { Button } from "@/vue/components/ui/button/index.js";
import { Input } from "@/vue/components/ui/input/index.js";
import {
	Popover,
	PopoverContent,
	PopoverTrigger,
} from "@/vue/components/ui/popover/index.js";
import ColorPickerPopover from "@/vue/components/ColorPickerPopover.vue";
import AvatarGallery from "./AvatarGallery.vue";

const props = defineProps({
	sheet: { type: Object, required: true },
	canEdit: { type: Boolean, default: false },
	isDraft: { type: Boolean, default: false },
	sourceShortcut: { type: String, default: null },
});

const live = useLive();

// ── Title editing ──
const editingName = ref(false);
const nameInput = ref(null);
const localName = ref(props.sheet.name);

watch(
	() => props.sheet.name,
	(v) => {
		localName.value = v;
	},
);

function startEditName() {
	if (!props.canEdit) return;
	editingName.value = true;
	setTimeout(() => nameInput.value?.focus(), 0);
}

function saveName() {
	editingName.value = false;
	const name = localName.value?.trim();
	if (name && name !== props.sheet.name) {
		live.pushEvent("save_name", { name });
	}
}

function onNameKeydown(e) {
	if (e.key === "Enter") {
		e.preventDefault();
		saveName();
	}
}

// ── Shortcut editing ──
const editingShortcut = ref(false);
const shortcutInput = ref(null);
const localShortcut = ref(props.sheet.shortcut || "");

watch(
	() => props.sheet.shortcut,
	(v) => {
		localShortcut.value = v || "";
	},
);

function startEditShortcut() {
	if (!props.canEdit || props.isDraft) return;
	editingShortcut.value = true;
	setTimeout(() => shortcutInput.value?.focus(), 0);
}

function saveShortcut() {
	editingShortcut.value = false;
	const shortcut = localShortcut.value?.trim();
	if (shortcut !== (props.sheet.shortcut || "")) {
		live.pushEvent("save_shortcut", { shortcut: shortcut || "" });
	}
}

function onShortcutKeydown(e) {
	if (e.key === "Enter") {
		e.preventDefault();
		saveShortcut();
	}
}

// ── Color picker ──
const localColor = ref(props.sheet.color || "#3b82f6");

watch(
	() => props.sheet.color,
	(v) => {
		localColor.value = v || "#3b82f6";
	},
);

function onColorUpdate(color) {
	localColor.value = color;
	live.pushEvent("set_sheet_color", { color });
}

// ── Banner upload ──
function triggerBannerUpload() {
	const input = document.createElement("input");
	input.type = "file";
	input.accept = "image/*";
	input.onchange = (e) => uploadFile(e.target.files[0], "upload_banner");
	input.click();
}

function removeBanner() {
	live.pushEvent("remove_banner", {});
}

// ── Avatar upload ──
function triggerAvatarUpload() {
	const input = document.createElement("input");
	input.type = "file";
	input.accept = "image/*";
	input.multiple = true;
	input.onchange = (e) => {
		Array.from(e.target.files).forEach((file) =>
			uploadFile(file, "upload_avatar"),
		);
	};
	input.click();
}

function uploadFile(file, eventName) {
	if (!file) return;
	const reader = new FileReader();
	reader.onload = () => {
		live.pushEvent(eventName, {
			filename: file.name,
			content_type: file.type,
			data: reader.result,
		});
	};
	reader.readAsDataURL(file);
}

// ── Avatars ──
const galleryOpen = ref(false);

const defaultAvatar = computed(
	() =>
		props.sheet.avatars?.find((a) => a.is_default) ||
		props.sheet.avatars?.[0] ||
		null,
);

function setDefaultAvatar(id) {
	live.pushEvent("set_default_avatar", { id });
}

function removeAvatar(id) {
	live.pushEvent("remove_avatar", { id });
}

function updateAvatarName(id, value) {
	live.pushEvent("gallery_update_name", { id, value });
}

function updateAvatarNotes(id, value) {
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
            {{ sheet.bannerUrl ? "Change" : "Add cover" }}
          </Button>
          <Button
            v-if="sheet.bannerUrl"
            variant="secondary"
            size="sm"
            class="bg-surface/80 hover:bg-surface gap-1.5"
            @click="removeBanner"
          >
            <Trash2 class="size-4" />
            Remove
          </Button>
        </div>
      </div>

      <!-- Color picker (bottom-right) -->
      <div v-if="canEdit" class="absolute bottom-3 right-3 z-10">
        <ColorPickerPopover
          :color="localColor"
          variant="full"
          @update:color="onColorUpdate"
        />
      </div>
    </div>

    <!-- Avatar + Title row -->
    <div class="flex items-start gap-4 mb-8 px-2">
      <!-- Avatar -->
      <Popover>
        <PopoverTrigger as-child>
          <button class="shrink-0 group/avatar relative" :disabled="!canEdit">
            <img
              v-if="defaultAvatar?.url"
              :src="defaultAvatar.url"
              :alt="sheet.name"
              class="size-20 rounded-lg object-cover"
            />
            <div
              v-else
              class="size-20 rounded-lg bg-muted flex items-center justify-center"
            >
              <span class="text-2xl font-bold text-muted-foreground/40">
                {{ sheet.name?.[0]?.toUpperCase() || "?" }}
              </span>
            </div>
          </button>
        </PopoverTrigger>
        <PopoverContent v-if="canEdit" align="start" :side-offset="8" class="w-auto p-3">
          <!-- Film strip -->
          <div class="grid grid-cols-3 gap-2" style="width: 16.5rem">
            <div v-for="avatar in sheet.avatars" :key="avatar.id" class="flex flex-col items-center">
              <div
                :class="[
                  'relative group/thumb size-20 rounded-lg overflow-hidden border-2 transition-colors',
                  avatar.is_default
                    ? 'border-primary'
                    : 'border-border hover:border-foreground/30',
                ]"
              >
                <button
                  v-if="avatar.url"
                  type="button"
                  class="w-full h-full"
                  @click="setDefaultAvatar(avatar.id)"
                >
                  <img :src="avatar.url" :alt="avatar.name || ''" class="w-full h-full object-cover" />
                </button>
                <button
                  type="button"
                  class="absolute top-0 right-0 size-4 bg-black/70 rounded-bl flex items-center justify-center opacity-0 group-hover/thumb:opacity-100 transition-opacity z-10"
                  @click.stop="removeAvatar(avatar.id)"
                >
                  <X class="size-2.5 text-white" />
                </button>
              </div>
              <span class="text-[10px] text-muted-foreground truncate max-w-full mt-0.5">
                {{ avatar.name || "" }}
              </span>
            </div>

            <!-- Upload slot -->
            <div class="flex flex-col items-center">
              <button
                class="size-20 rounded-lg border-2 border-dashed border-muted-foreground/20 hover:border-muted-foreground/40 flex items-center justify-center transition-colors"
                @click="triggerAvatarUpload"
              >
                <Plus class="size-5 text-muted-foreground/40" />
              </button>
            </div>
          </div>

          <!-- Gallery link -->
          <button
            v-if="sheet.avatars?.length > 0"
            class="flex items-center justify-center gap-1.5 w-full mt-2 pt-2 border-t border-border text-xs text-muted-foreground hover:text-foreground transition-colors"
            @click="galleryOpen = true"
          >
            <LayoutGrid class="size-3.5" />
            Gallery
          </button>
        </PopoverContent>
      </Popover>

      <!-- Title + Shortcut -->
      <div class="flex-1 min-w-0 pt-1">
        <!-- Name -->
        <div v-if="canEdit && editingName">
          <input
            ref="nameInput"
            v-model="localName"
            class="text-3xl font-bold w-full bg-transparent outline-none border-none px-0"
            placeholder="Untitled"
            @blur="saveName"
            @keydown="onNameKeydown"
          />
        </div>
        <h1
          v-else
          class="text-3xl font-bold"
          :class="canEdit && 'cursor-text hover:bg-accent/30 rounded px-1 -mx-1 transition-colors'"
          @click="startEditName"
        >
          {{ sheet.name || "Untitled" }}
        </h1>

        <!-- Shortcut -->
        <div class="mt-1 flex items-center gap-1">
          <span class="text-muted-foreground/50">#</span>
          <div v-if="isDraft && sourceShortcut" class="text-sm text-muted-foreground/40">
            {{ sourceShortcut }}
          </div>
          <div v-else-if="canEdit && editingShortcut">
            <input
              ref="shortcutInput"
              v-model="localShortcut"
              class="text-sm text-muted-foreground bg-transparent outline-none border-none px-0"
              placeholder="add-shortcut"
              @blur="saveShortcut"
              @keydown="onShortcutKeydown"
            />
          </div>
          <div
            v-else
            class="text-sm text-muted-foreground/50"
            :class="canEdit && 'cursor-text hover:text-muted-foreground transition-colors'"
            @click="startEditShortcut"
          >
            {{ sheet.shortcut || (canEdit ? "add-shortcut" : "") }}
          </div>
        </div>
      </div>
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
