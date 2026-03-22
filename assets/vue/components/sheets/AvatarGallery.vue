<script setup>
import { ref, watch } from "vue";
import {
	ChevronLeft,
	ChevronRight,
	Image,
	Plus,
	Star,
	Trash2,
	X,
} from "lucide-vue-next";
import { Button } from "@/vue/components/ui/button";
import { Input } from "@/vue/components/ui/input";
import { Textarea } from "@/vue/components/ui/textarea";
import { Badge } from "@/vue/components/ui/badge";
import { Dialog, DialogContent } from "@/vue/components/ui/dialog";

const props = defineProps({
	open: { type: Boolean, default: false },
	avatars: { type: Array, default: () => [] },
	canEdit: { type: Boolean, default: false },
});

const emit = defineEmits([
	"update:open",
	"upload",
	"setDefault",
	"remove",
	"updateName",
	"updateNotes",
]);

// ── View state ──
const view = ref("grid"); // "grid" | "single"
const currentIndex = ref(0);

// Reset to grid when dialog opens
watch(
	() => props.open,
	(open) => {
		if (open) {
			view.value = "grid";
			currentIndex.value = 0;
		}
	},
);

// Keep index in bounds when avatars change
watch(
	() => props.avatars.length,
	(len) => {
		if (currentIndex.value >= len) {
			currentIndex.value = Math.max(0, len - 1);
		}
		if (len === 0 && view.value === "single") {
			view.value = "grid";
		}
	},
);

function openSingle(index) {
	currentIndex.value = index;
	view.value = "single";
}

function navigate(direction) {
	const count = props.avatars.length;
	if (count <= 1) return;
	currentIndex.value = (currentIndex.value + direction + count) % count;
}

// ── Debounced updates ──
const nameDebounces = {};
const notesDebounces = {};

function onNameBlur(id, value, original) {
	clearTimeout(nameDebounces[id]);
	if (value !== (original || "")) {
		emit("updateName", id, value);
	}
}

function onNotesBlur(id, value, original) {
	clearTimeout(notesDebounces[id]);
	if (value !== (original || "")) {
		emit("updateNotes", id, value);
	}
}
</script>

<template>
  <Dialog :open="open" @update:open="(v) => emit('update:open', v)">
    <DialogContent
      class="max-w-xl max-h-[85vh] overflow-hidden flex flex-col p-0 gap-0"
      :show-close-button="false"
    >
      <!-- ═══ GRID VIEW ═══ -->
      <template v-if="view === 'grid'">
        <!-- Header -->
        <div class="flex items-center justify-between px-5 pt-4 pb-3">
          <h3 class="font-bold text-lg">Avatar Gallery</h3>
          <Button variant="ghost" size="icon-sm" @click="emit('update:open', false)">
            <X class="size-4" />
          </Button>
        </div>

        <!-- Scrollable body -->
        <div class="overflow-y-auto px-5 pb-5 flex-1">
          <!-- Empty state -->
          <div v-if="avatars.length === 0" class="text-center py-8 text-muted-foreground/40">
            <Image class="size-8 mx-auto mb-2 opacity-40" />
            <p class="text-sm">No avatars yet. Upload one to get started.</p>
          </div>

          <!-- Thumbnail grid -->
          <div v-else class="grid grid-cols-3 sm:grid-cols-4 gap-3">
            <div
              v-for="(item, i) in avatars"
              :key="item.id"
              class="group/card relative flex flex-col items-center"
            >
              <!-- Thumbnail -->
              <button
                type="button"
                class="aspect-square w-full rounded-lg overflow-hidden border-2 transition-colors border-border hover:border-foreground/30"
                @click="openSingle(i)"
              >
                <img
                  v-if="item.url"
                  :src="item.url"
                  :alt="item.name || ''"
                  class="w-full h-full object-cover"
                />
              </button>

              <!-- Default badge -->
              <div v-if="item.is_default" class="absolute top-1 left-1">
                <Badge variant="default" class="text-[10px] px-1.5 py-0">default</Badge>
              </div>

              <!-- Delete X -->
              <button
                v-if="canEdit"
                type="button"
                class="absolute top-1 right-1 size-5 rounded-full bg-black/70 flex items-center justify-center opacity-0 group-hover/card:opacity-100 transition-opacity"
                @click.stop="emit('remove', item.id)"
              >
                <X class="size-3 text-white" />
              </button>

              <!-- Name input -->
              <input
                v-if="canEdit"
                type="text"
                :value="item.name || ''"
                placeholder="Name..."
                class="w-full mt-1 text-center text-xs bg-transparent border-0 border-b border-border focus:border-primary rounded-none px-0 outline-none"
                @blur="(e) => onNameBlur(item.id, e.target.value, item.name)"
              />
              <p v-else-if="item.name" class="text-xs text-muted-foreground mt-1 truncate max-w-full">
                {{ item.name }}
              </p>
            </div>
          </div>

          <!-- Upload button -->
          <div v-if="canEdit" class="mt-4">
            <Button
              variant="ghost"
              size="sm"
              class="w-full border border-dashed border-muted-foreground/20 gap-1.5"
              @click="emit('upload')"
            >
              <Plus class="size-4" />
              Add avatar
            </Button>
          </div>
        </div>
      </template>

      <!-- ═══ SINGLE VIEW ═══ -->
      <template v-else-if="view === 'single' && avatars[currentIndex]">
        <!-- Header: back + nav -->
        <div class="flex items-center justify-between px-5 pt-4 pb-3">
          <Button variant="ghost" size="sm" class="gap-1" @click="view = 'grid'">
            <ChevronLeft class="size-4" />
            Avatar Gallery
          </Button>

          <div v-if="avatars.length > 1" class="flex items-center gap-1">
            <Button variant="ghost" size="icon-sm" class="size-7" @click="navigate(-1)">
              <ChevronLeft class="size-4" />
            </Button>
            <span class="text-xs text-muted-foreground">
              {{ currentIndex + 1 }}/{{ avatars.length }}
            </span>
            <Button variant="ghost" size="icon-sm" class="size-7" @click="navigate(1)">
              <ChevronRight class="size-4" />
            </Button>
          </div>
        </div>

        <!-- Scrollable body -->
        <div class="overflow-y-auto px-5 pb-5 flex-1">
          <!-- Image -->
          <div class="flex justify-center bg-muted/20 rounded-lg overflow-hidden mb-4">
            <img
              :src="avatars[currentIndex].url"
              :alt="avatars[currentIndex].name || ''"
              class="max-w-full max-h-[55vh] object-contain"
            />
          </div>

          <!-- Name field -->
          <div class="mb-3 space-y-1">
            <label class="text-xs font-medium">Name</label>
            <Input
              :model-value="avatars[currentIndex].name || ''"
              placeholder="e.g. happy, angry, combat..."
              class="h-8 text-sm"
              :disabled="!canEdit"
              @blur="(e) => onNameBlur(avatars[currentIndex].id, e.target.value, avatars[currentIndex].name)"
            />
          </div>

          <!-- Notes field -->
          <div class="mb-3 space-y-1">
            <label class="text-xs font-medium">Notes</label>
            <Textarea
              :model-value="avatars[currentIndex].notes || ''"
              placeholder="Voice direction, art notes..."
              :rows="3"
              class="text-sm resize-none"
              :disabled="!canEdit"
              @blur="(e) => onNotesBlur(avatars[currentIndex].id, e.target.value, avatars[currentIndex].notes)"
            />
          </div>

          <!-- Footer: actions -->
          <div class="flex items-center justify-between pt-3 border-t border-border">
            <div class="flex items-center gap-2">
              <Button
                v-if="canEdit && !avatars[currentIndex].is_default"
                variant="ghost"
                size="sm"
                class="gap-1"
                @click="emit('setDefault', avatars[currentIndex].id)"
              >
                <Star class="size-3.5" />
                Set as default
              </Button>
              <Badge v-else-if="avatars[currentIndex].is_default" variant="default" class="text-xs">
                Default
              </Badge>
            </div>

            <Button
              v-if="canEdit"
              variant="destructive"
              size="sm"
              class="gap-1"
              @click="emit('remove', avatars[currentIndex].id)"
            >
              <Trash2 class="size-3.5" />
              Delete
            </Button>
          </div>
        </div>
      </template>
    </DialogContent>
  </Dialog>
</template>
