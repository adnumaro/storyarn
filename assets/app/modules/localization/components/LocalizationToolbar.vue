<script setup lang="ts">
import { BarChart3, Download, Languages } from "lucide-vue-next";
import { ref } from "vue";
import { Button } from "@components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@components/ui/dropdown-menu";
import { useLive } from "@composables/useLive";

const {
  reportUrl = "",
  exportCsvUrl = null,
  exportXlsxUrl = null,
  hasProvider = false,
} = defineProps<{
  reportUrl?: string;
  exportCsvUrl?: string | null;
  exportXlsxUrl?: string | null;
  hasProvider?: boolean;
}>();

const live = useLive();
const translating = ref(false);

function translateBatch(): void {
  translating.value = true;
  live.pushEvent("translate_batch", {}, () => {
    translating.value = false;
  });
}
</script>

<template>
  <div class="flex items-center gap-1 px-1.5 py-1 surface-panel">
    <a
      :href="reportUrl"
      data-phx-link="redirect"
      data-phx-link-state="push"
      class="inline-flex items-center justify-center h-8 px-3 text-sm rounded-md hover:bg-accent transition-colors gap-1.5"
    >
      <BarChart3 class="size-4" />
      <span class="hidden xl:inline">Report</span>
    </a>

    <DropdownMenu v-if="exportCsvUrl || exportXlsxUrl">
      <DropdownMenuTrigger as-child>
        <Button variant="ghost" size="sm" class="gap-1.5">
          <Download class="size-4" />
          <span class="hidden xl:inline">Export</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuItem v-if="exportXlsxUrl" as-child>
          <a :href="exportXlsxUrl">Excel (.xlsx)</a>
        </DropdownMenuItem>
        <DropdownMenuItem v-if="exportCsvUrl" as-child>
          <a :href="exportCsvUrl">CSV (.csv)</a>
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>

    <Button
      v-if="hasProvider"
      size="sm"
      :disabled="translating"
      class="gap-1.5"
      @click="translateBatch"
    >
      <Languages class="size-4" />
      <span class="hidden xl:inline">{{
        translating ? "Translating..." : "Translate All Pending"
      }}</span>
    </Button>
  </div>
</template>
