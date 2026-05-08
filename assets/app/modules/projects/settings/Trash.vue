<script setup lang="ts">
import { AlertTriangle, Trash2, Undo2 } from "lucide-vue-next";
import { ref } from "vue";
import { Button } from "@components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog";
import { useLive } from "@shared/composables/useLive";

interface TrashedSheet {
  id: number;
  name: string;
  deleted_at: string;
}

const { trashedSheets = [], canManage = false } = defineProps<{
  trashedSheets?: TrashedSheet[];
  canManage?: boolean;
}>();

const live = useLive();

const showDeleteConfirm = ref(false);
const showEmptyConfirm = ref(false);
const sheetToDelete = ref<TrashedSheet | null>(null);

function restoreSheet(id: number) {
  live.pushEvent("restore_sheet", { id });
}

function openDeleteConfirm(sheet: TrashedSheet) {
  sheetToDelete.value = sheet;
  live.pushEvent("show_delete_confirm", { id: sheet.id });
  showDeleteConfirm.value = true;
}

function confirmDelete() {
  live.pushEvent("confirm_delete_permanently", {});
  showDeleteConfirm.value = false;
  sheetToDelete.value = null;
}

function emptyTrash() {
  live.pushEvent("empty_trash", {});
  showEmptyConfirm.value = false;
}

function formatTimeAgo(datetime: string | null) {
  if (!datetime) return "";
  const now = new Date();
  const deleted = new Date(datetime);
  const diffSeconds = Math.floor((now.getTime() - deleted.getTime()) / 1000);

  if (diffSeconds < 60) return "just now";
  if (diffSeconds < 3600) {
    const minutes = Math.floor(diffSeconds / 60);
    return `${minutes} minute${minutes === 1 ? "" : "s"} ago`;
  }
  if (diffSeconds < 86400) {
    const hours = Math.floor(diffSeconds / 3600);
    return `${hours} hour${hours === 1 ? "" : "s"} ago`;
  }
  const days = Math.floor(diffSeconds / 86400);
  return `${days} day${days === 1 ? "" : "s"} ago`;
}
</script>

<template>
  <div class="max-w-3xl mx-auto">
    <div class="flex items-center justify-between mb-6">
      <div>
        <h1 class="text-2xl font-bold tracking-tight">{{ $t("project_settings.trash.title") }}</h1>
        <p class="text-sm text-muted-foreground mt-1">
          {{ $t("project_settings.trash.description") }}
        </p>
      </div>
      <Button
        v-if="canManage && trashedSheets.length > 0"
        variant="destructive"
        @click="showEmptyConfirm = true"
      >
        <Trash2 class="size-4 mr-2" />
        {{ $t("project_settings.trash.empty_trash") }}
      </Button>
    </div>

    <div class="mt-8">
      <!-- Empty state -->
      <div
        v-if="trashedSheets.length === 0"
        class="flex flex-col items-center justify-center py-16 text-center"
      >
        <Trash2 class="size-10 text-muted-foreground/40 mb-4" />
        <h3 class="text-lg font-medium text-muted-foreground">
          {{ $t("project_settings.trash.empty_title") }}
        </h3>
        <p class="text-sm text-muted-foreground/70 mt-1">
          {{ $t("project_settings.trash.empty_description") }}
        </p>
      </div>

      <!-- Trashed items list -->
      <div v-else class="space-y-2">
        <div
          v-for="sheet in trashedSheets"
          :key="sheet.id"
          class="flex items-center justify-between p-4 bg-muted rounded-lg"
        >
          <div class="flex items-center gap-3 min-w-0">
            <div
              class="shrink-0 size-10 rounded-lg bg-muted-foreground/10 flex items-center justify-center text-sm font-medium"
            >
              {{ sheet.name?.charAt(0)?.toUpperCase() || "?" }}
            </div>
            <div class="min-w-0">
              <p class="font-medium truncate">{{ sheet.name }}</p>
              <p class="text-sm text-muted-foreground">
                {{ $t("project_settings.trash.deleted_prefix")
                }}{{ formatTimeAgo(sheet.deleted_at) }}
              </p>
            </div>
          </div>

          <div v-if="canManage" class="flex items-center gap-2 shrink-0">
            <Button variant="ghost" size="sm" @click="restoreSheet(sheet.id)">
              <Undo2 class="size-4 mr-1" />
              {{ $t("project_settings.trash.restore") }}
            </Button>
            <Button
              variant="ghost"
              size="sm"
              class="text-destructive hover:bg-destructive/10"
              @click="openDeleteConfirm(sheet)"
            >
              <Trash2 class="size-4 mr-1" />
              {{ $t("project_settings.trash.delete") }}
            </Button>
          </div>
        </div>
      </div>
    </div>

    <!-- Delete confirmation dialog -->
    <Dialog v-model:open="showDeleteConfirm">
      <DialogContent>
        <DialogHeader>
          <DialogTitle class="flex items-center gap-2">
            <AlertTriangle class="size-5 text-destructive" />
            {{ $t("project_settings.trash.delete_confirm_title") }}
          </DialogTitle>
          <DialogDescription>
            {{ $t("project_settings.trash.delete_confirm_description") }}
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button variant="outline" @click="showDeleteConfirm = false">{{
            $t("project_settings.trash.cancel")
          }}</Button>
          <Button variant="destructive" @click="confirmDelete">{{
            $t("project_settings.trash.delete")
          }}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>

    <!-- Empty trash confirmation dialog -->
    <Dialog v-model:open="showEmptyConfirm">
      <DialogContent>
        <DialogHeader>
          <DialogTitle class="flex items-center gap-2">
            <AlertTriangle class="size-5 text-destructive" />
            {{ $t("project_settings.trash.empty_confirm_title") }}
          </DialogTitle>
          <DialogDescription>
            {{ $t("project_settings.trash.empty_confirm_description") }}
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button variant="outline" @click="showEmptyConfirm = false">{{
            $t("project_settings.trash.cancel")
          }}</Button>
          <Button variant="destructive" @click="emptyTrash">{{
            $t("project_settings.trash.empty_trash")
          }}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </div>
</template>
