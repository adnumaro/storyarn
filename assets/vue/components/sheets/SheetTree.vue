<script setup>
import { ref, computed } from "vue"
import { useLive } from "@/vue/composables/useLive"
import { Plus } from "lucide-vue-next"
import { Input } from "@/vue/components/ui/input"
import { Button } from "@/vue/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/vue/components/ui/dialog"
import SheetTreeNode from "./SheetTreeNode.vue"

const props = defineProps({
  sheetsTree: { type: Array, default: () => [] },
  selectedSheetId: { type: [String, Number], default: null },
  canEdit: { type: Boolean, default: false },
  workspaceSlug: { type: String, required: true },
  projectSlug: { type: String, required: true },
})

const live = useLive()
const searchQuery = ref("")
const deleteDialogOpen = ref(false)
const pendingDeleteSheet = ref(null)

function sheetHref(sheet) {
  return `/workspaces/${props.workspaceSlug}/projects/${props.projectSlug}/sheets/${sheet.id}`
}

function matchesSearch(node, query) {
  if (node.name.toLowerCase().includes(query)) return true
  if (node.children) {
    return node.children.some((child) => matchesSearch(child, query))
  }
  return false
}

function filterTree(nodes, query) {
  return nodes
    .filter((node) => matchesSearch(node, query))
    .map((node) => ({
      ...node,
      children: node.children ? filterTree(node.children, query) : [],
    }))
}

const filteredTree = computed(() => {
  if (!searchQuery.value) return props.sheetsTree
  return filterTree(props.sheetsTree, searchQuery.value.toLowerCase())
})

function createSheet() {
  live.pushEvent("create_sheet", {})
}

function createChildSheet(parentId) {
  live.pushEvent("create_child_sheet", { parent_id: parentId })
}

function requestDelete(sheet) {
  pendingDeleteSheet.value = sheet
  deleteDialogOpen.value = true
}

function confirmDelete() {
  if (pendingDeleteSheet.value) {
    live.pushEvent("set_pending_delete_sheet", { id: pendingDeleteSheet.value.id })
    live.pushEvent("confirm_delete_sheet", {})
  }
  deleteDialogOpen.value = false
  pendingDeleteSheet.value = null
}
</script>

<template>
  <div class="space-y-2">
    <!-- Search -->
    <div class="px-1">
      <Input
        v-model="searchQuery"
        type="search"
        placeholder="Filter sheets..."
        class="h-7 text-xs"
      />
    </div>

    <!-- Empty state -->
    <div v-if="filteredTree.length === 0" class="px-2 py-4 text-xs text-muted-foreground text-center">
      No sheets yet
    </div>

    <!-- Tree -->
    <div v-else class="space-y-0.5">
      <SheetTreeNode
        v-for="node in filteredTree"
        :key="node.id"
        :node="node"
        :selected-sheet-id="selectedSheetId"
        :can-edit="canEdit"
        :depth="0"
        :search-active="!!searchQuery"
        :sheet-href="sheetHref"
        @create-child="createChildSheet"
        @request-delete="requestDelete"
      />
    </div>

    <!-- New Sheet button -->
    <div v-if="canEdit" class="pt-2 px-1">
      <Button
        variant="ghost"
        size="sm"
        class="w-full justify-start gap-2 text-xs text-muted-foreground"
        @click="createSheet"
      >
        <Plus class="size-3.5" />
        New Sheet
      </Button>
    </div>

    <!-- Delete confirmation dialog -->
    <Dialog v-model:open="deleteDialogOpen">
      <DialogContent class="z-[1040]">
        <DialogHeader>
          <DialogTitle>Delete sheet?</DialogTitle>
          <DialogDescription>
            Are you sure you want to delete "{{ pendingDeleteSheet?.name }}"?
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
