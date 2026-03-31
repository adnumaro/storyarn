<script setup>
import { CloudFog, EllipsisVertical, Eye, EyeOff, Pencil, Plus, Trash2 } from "lucide-vue-next";
import { nextTick, ref } from "vue";
import { Button } from "@components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@components/ui/dropdown-menu";
import { useLive } from "@composables/useLive";

const props = defineProps({
  layers: { type: Array, default: () => [] },
  activeLayerId: { type: [Number, String], default: null },
  canEdit: { type: Boolean, default: false },
  editMode: { type: Boolean, default: true },
});

const live = useLive();
const renamingLayerId = ref(null);
const renameValue = ref("");
const renameInputRef = ref(null);
const deleteDialogOpen = ref(false);
const pendingDeleteLayer = ref(null);

function setActiveLayer(id) {
  live.pushEvent("set_active_layer", { id });
}

function toggleVisibility(id) {
  live.pushEvent("toggle_layer_visibility", { id });
}

function createLayer() {
  live.pushEvent("create_layer", {});
}

function startRename(layer) {
  renamingLayerId.value = layer.id;
  renameValue.value = layer.name;
  nextTick(() => {
    renameInputRef.value?.focus();
    renameInputRef.value?.select();
  });
}

function finishRename(layerId) {
  const trimmed = renameValue.value.trim();
  if (trimmed && renamingLayerId.value === layerId) {
    live.pushEvent("rename_layer", { id: layerId, name: trimmed });
  }
  renamingLayerId.value = null;
}

function cancelRename() {
  renamingLayerId.value = null;
}

function toggleFog(layer) {
  live.pushEvent("update_layer_fog", {
    id: layer.id,
    field: "fog_enabled",
    value: String(!layer.fogEnabled),
  });
}

function requestDelete(layer) {
  pendingDeleteLayer.value = layer;
  deleteDialogOpen.value = true;
}

function confirmDelete() {
  if (pendingDeleteLayer.value) {
    live.pushEvent("set_pending_delete_layer", {
      id: pendingDeleteLayer.value.id,
    });
    live.pushEvent("confirm_delete_layer", {});
  }
  deleteDialogOpen.value = false;
  pendingDeleteLayer.value = null;
}

function isActive(layer) {
  return props.activeLayerId != null && String(layer.id) === String(props.activeLayerId);
}
</script>

<template>
  <div>
    <!-- Layer rows -->
    <div class="flex flex-col gap-0.5">
      <div v-for="layer in layers" :key="layer.id" class="flex items-center group">
        <!-- Visibility toggle -->
        <button
          v-if="canEdit && editMode"
          type="button"
          class="shrink-0 size-6 inline-flex items-center justify-center rounded hover:bg-accent"
          title="Toggle visibility"
          @click="toggleVisibility(layer.id)"
        >
          <component
            :is="layer.visible ? Eye : EyeOff"
            :class="['size-3', !layer.visible && 'opacity-40']"
          />
        </button>

        <!-- Rename input -->
        <input
          v-if="renamingLayerId === layer.id"
          ref="renameInputRef"
          v-model="renameValue"
          type="text"
          class="flex-1 min-w-0 h-7 px-2 text-xs bg-background border border-border rounded-md focus:outline-none focus:ring-1 focus:ring-ring"
          @blur="finishRename(layer.id)"
          @keydown.enter="finishRename(layer.id)"
          @keydown.escape="cancelRename"
        />

        <!-- Layer name button -->
        <button
          v-else
          type="button"
          :class="[
            'flex items-center gap-1 flex-1 min-w-0 px-2 py-1 rounded-md cursor-pointer text-sm',
            isActive(layer) ? 'bg-accent text-accent-foreground font-medium' : 'hover:bg-accent/50',
          ]"
          title="Set as active layer"
          @click="setActiveLayer(layer.id)"
        >
          <span :class="['text-xs truncate', !layer.visible && 'opacity-40 line-through']">
            {{ layer.name }}
          </span>
          <CloudFog
            v-if="layer.fogEnabled"
            class="size-3 opacity-50 shrink-0"
            title="Fog of War enabled"
          />
        </button>

        <!-- Kebab menu -->
        <DropdownMenu v-if="canEdit && editMode && renamingLayerId !== layer.id">
          <DropdownMenuTrigger as-child>
            <button
              type="button"
              class="shrink-0 size-5 inline-flex items-center justify-center rounded text-muted-foreground opacity-0 group-hover:opacity-100 transition-opacity hover:bg-accent hover:text-foreground"
              title="Layer options"
            >
              <EllipsisVertical class="size-3" />
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem class="text-xs gap-2" @select="startRename(layer)">
              <Pencil class="size-3.5" />
              Rename
            </DropdownMenuItem>
            <DropdownMenuItem class="text-xs gap-2" @select="toggleFog(layer)">
              <component :is="layer.fogEnabled ? Eye : CloudFog" class="size-3.5" />
              {{ layer.fogEnabled ? "Disable Fog" : "Enable Fog" }}
            </DropdownMenuItem>
            <DropdownMenuItem
              class="text-xs gap-2 text-destructive"
              :disabled="layers.length <= 1"
              @select="requestDelete(layer)"
            >
              <Trash2 class="size-3.5" />
              Delete
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </div>

    <!-- Add layer button -->
    <div v-if="canEdit && editMode" class="mt-1">
      <Button
        variant="ghost"
        size="sm"
        class="w-full justify-start gap-1.5 text-xs text-muted-foreground"
        @click="createLayer"
      >
        <Plus class="size-3.5" />
        New Layer
      </Button>
    </div>

    <!-- Delete confirmation -->
    <Dialog v-model:open="deleteDialogOpen">
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Delete layer?</DialogTitle>
          <DialogDescription>
            This layer will be deleted. All elements on this layer will be moved to no layer.
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button variant="outline" size="sm" @click="deleteDialogOpen = false">Cancel</Button>
          <Button variant="destructive" size="sm" @click="confirmDelete">Delete</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </div>
</template>
