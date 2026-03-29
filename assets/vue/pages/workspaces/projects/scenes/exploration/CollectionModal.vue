<script setup>
import { PackageCheck, PackageOpen, X } from "lucide-vue-next";
import { Button } from "@/vue/components/ui/button";
import {
	Dialog,
	DialogContent,
	DialogHeader,
	DialogTitle,
} from "@/vue/components/ui/dialog";
import { useLive } from "@/vue/composables/useLive";

const props = defineProps({
	open: { type: Boolean, default: false },
	zone: { type: Object, default: null },
	items: { type: Array, default: () => [] },
});

const live = useLive();

function takeItem(itemId) {
	live.pushEvent("collection_take", { "item-id": itemId });
}

function takeAll() {
	live.pushEvent("collection_take_all", {});
}

function close() {
	live.pushEvent("collection_close", {});
}
</script>

<template>
  <Dialog :open="open">
    <DialogContent :show-close-button="false" @escape-key-down="close">
      <DialogHeader class="flex-row items-center justify-between space-y-0">
        <DialogTitle class="flex items-center gap-2">
          <PackageOpen class="size-5 opacity-60" />
          Collection
        </DialogTitle>
        <Button variant="ghost" size="icon-sm" @click="close">
          <X class="size-4" />
        </Button>
      </DialogHeader>

      <!-- Empty state -->
      <div v-if="items.length === 0" class="flex flex-col items-center py-6 text-center">
        <PackageOpen class="size-8 opacity-30 mb-2" />
        <p class="text-sm text-muted-foreground">
          {{ zone?.emptyMessage || 'Nothing here...' }}
        </p>
      </div>

      <!-- Items -->
      <div v-else class="space-y-2">
        <div
          v-for="item in items"
          :key="item.id"
          class="flex items-center justify-between gap-3 rounded-md border border-border px-3 py-2"
        >
          <span class="text-sm">
            {{ item.label || item._sheet_name || 'Item' }}
          </span>
          <Button size="sm" @click="takeItem(item.id)">
            Take
          </Button>
        </div>
      </div>

      <!-- Take All -->
      <div v-if="items.length > 0 && zone?.collectAllEnabled" class="flex justify-end pt-2">
        <Button variant="outline" @click="takeAll">
          <PackageCheck class="size-4" />
          Take All
        </Button>
      </div>
    </DialogContent>
  </Dialog>
</template>
