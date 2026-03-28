<script setup>
import {
	AlertTriangle,
	ArrowDown,
	ArrowUp,
	ArrowUpDown,
	Box,
	ChevronLeft,
	ChevronRight,
	GitBranch,
	Info,
	MessageSquare,
	MoreHorizontal,
	Star,
	TextCursorInput,
	Trash2,
} from "lucide-vue-next";
import { computed } from "vue";
import { Badge } from "@/vue/components/ui/badge";
import { Button } from "@/vue/components/ui/button";
import {
	DropdownMenu,
	DropdownMenuContent,
	DropdownMenuItem,
	DropdownMenuTrigger,
} from "@/vue/components/ui/dropdown-menu";
import {
	Table,
	TableBody,
	TableCell,
	TableHead,
	TableHeader,
	TableRow,
} from "@/vue/components/ui/table";
import { useLive } from "@/vue/composables/useLive";
import { formatRelativeTime } from "@/vue/lib/date-utils";

const props = defineProps({
	stats: { type: Object, default: null },
	tableData: { type: Array, default: () => [] },
	sortBy: { type: String, default: "name" },
	sortDir: { type: String, default: "asc" },
	page: { type: Number, default: 1 },
	totalPages: { type: Number, default: 1 },
	total: { type: Number, default: 0 },
	issues: { type: Array, default: () => [] },
	canEdit: { type: Boolean, default: false },
	workspaceSlug: { type: String, required: true },
	projectSlug: { type: String, required: true },
});

const live = useLive();

function flowHref(row) {
	return `/workspaces/${props.workspaceSlug}/projects/${props.projectSlug}/flows/${row.id}`;
}

function handleSort(column) {
	live.pushEvent("sort_flows", { column });
}

function goToPage(page) {
	live.pushEvent("page_flows", { page });
}

function setMain(id) {
	live.pushEvent("set_main", { id });
}

function requestDelete(id) {
	live.pushEvent("set_pending_delete", { id });
	live.pushEvent("confirm_delete", {});
}

function sortIcon(column) {
	if (props.sortBy !== column) return ArrowUpDown;
	return props.sortDir === "asc" ? ArrowUp : ArrowDown;
}

const statCards = computed(() => {
	if (!props.stats) return [];
	return [
		{
			icon: GitBranch,
			label: "Flows",
			value: props.stats.flow_count,
			color: "text-primary",
		},
		{
			icon: Box,
			label: "Nodes",
			value: props.stats.node_count,
			color: "text-blue-400",
		},
		{
			icon: MessageSquare,
			label: "Dialogue",
			value: props.stats.dialogue_count,
			color: "text-violet-400",
		},
		{
			icon: TextCursorInput,
			label: "Words",
			value: props.stats.word_count,
			color: "text-emerald-400",
		},
	];
});

const columns = [
	{ key: "name", label: "Name", align: "left" },
	{ key: "node_count", label: "Nodes", align: "right" },
	{ key: "dialogue_count", label: "Dialogue", align: "right", hiddenClass: "hidden sm:table-cell" },
	{ key: "condition_count", label: "Conditions", align: "right", hiddenClass: "hidden sm:table-cell" },
	{ key: "word_count", label: "Words", align: "right", hiddenClass: "hidden md:table-cell" },
	{ key: "updated_at", label: "Modified", align: "right", hiddenClass: "hidden md:table-cell" },
];

const pages = computed(() => {
	const result = [];
	for (let i = 1; i <= props.totalPages; i++) {
		result.push(i);
	}
	return result;
});
</script>

<template>
  <div class="max-w-5xl mx-auto px-4 sm:px-6 pt-2 pb-8 space-y-6">
    <!-- Header -->
    <div>
      <h1 class="text-lg font-semibold">Flows</h1>
      <p class="text-sm text-muted-foreground">Create visual narrative flows and dialogue trees</p>
    </div>

    <!-- Empty state -->
    <div v-if="total === 0 && !stats" class="flex flex-col items-center justify-center py-16 text-center">
      <GitBranch class="size-12 text-muted-foreground/30 mb-4" />
      <p class="text-sm text-muted-foreground">No flows yet. Create your first flow to get started.</p>
    </div>

    <!-- Loading skeleton -->
    <div v-else-if="!stats" class="flex justify-center py-12">
      <div class="size-6 border-2 border-muted-foreground/20 border-t-muted-foreground/60 rounded-full animate-spin" />
    </div>

    <!-- Dashboard content -->
    <template v-else>
      <!-- Stats row -->
      <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
        <div
          v-for="stat in statCards"
          :key="stat.label"
          class="rounded-lg border border-border bg-surface p-4 space-y-2"
        >
          <div class="flex items-center gap-2 text-xs text-muted-foreground">
            <component :is="stat.icon" :class="['size-4', stat.color]" />
            {{ stat.label }}
          </div>
          <p class="text-2xl font-bold tabular-nums">{{ stat.value }}</p>
        </div>
      </div>

      <!-- Table section -->
      <div class="space-y-2">
        <h2 class="text-sm font-medium">All Flows</h2>
        <div class="rounded-lg border border-border bg-surface overflow-auto max-h-[60vh]">
          <Table>
            <TableHeader>
              <TableRow class="bg-muted/40 hover:bg-muted/40 sticky top-0 z-10">
                <TableHead
                  v-for="col in columns"
                  :key="col.key"
                  :class="[
                    'font-medium text-xs text-muted-foreground uppercase',
                    col.align === 'right' ? 'text-right' : 'text-left',
                    col.hiddenClass,
                  ]"
                >
                  <button
                    type="button"
                    class="inline-flex items-center gap-1 hover:text-foreground transition-colors"
                    :class="col.align === 'right' && 'ml-auto'"
                    @click="handleSort(col.key)"
                  >
                    {{ col.label }}
                    <component :is="sortIcon(col.key)" class="size-3" />
                  </button>
                </TableHead>
                <TableHead v-if="canEdit" class="w-10" />
              </TableRow>
            </TableHeader>
            <TableBody>
              <TableRow v-for="row in tableData" :key="row.id">
                <TableCell>
                  <a :href="flowHref(row)" class="inline-flex items-center gap-2 font-medium hover:underline">
                    {{ row.name }}
                    <Badge v-if="row.is_main" variant="default" class="text-[10px] px-1.5 py-0">
                      Main
                    </Badge>
                  </a>
                </TableCell>
                <TableCell class="text-right tabular-nums">{{ row.node_count }}</TableCell>
                <TableCell class="text-right tabular-nums hidden sm:table-cell">{{ row.dialogue_count }}</TableCell>
                <TableCell class="text-right tabular-nums hidden sm:table-cell">{{ row.condition_count }}</TableCell>
                <TableCell class="text-right tabular-nums hidden md:table-cell">{{ row.word_count }}</TableCell>
                <TableCell class="text-right text-muted-foreground text-xs hidden md:table-cell">
                  {{ formatRelativeTime(row.updated_at) }}
                </TableCell>
                <TableCell v-if="canEdit" class="text-right w-10">
                  <DropdownMenu>
                    <DropdownMenuTrigger as-child>
                      <Button variant="ghost" size="icon-sm" class="size-7">
                        <MoreHorizontal class="size-4" />
                      </Button>
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end">
                      <DropdownMenuItem v-if="!row.is_main" class="gap-2 text-xs" @select="setMain(row.id)">
                        <Star class="size-3.5" />
                        Set as main
                      </DropdownMenuItem>
                      <DropdownMenuItem class="text-destructive gap-2 text-xs" @select="requestDelete(row.id)">
                        <Trash2 class="size-3.5" />
                        Delete
                      </DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </TableCell>
              </TableRow>
            </TableBody>
          </Table>
        </div>

        <!-- Pagination -->
        <div v-if="totalPages > 1" class="flex items-center justify-between text-xs text-muted-foreground pt-1">
          <span>{{ total }} flows</span>
          <div class="flex items-center gap-1">
            <Button
              variant="ghost"
              size="icon-sm"
              class="size-7"
              :disabled="page <= 1"
              @click="goToPage(page - 1)"
            >
              <ChevronLeft class="size-4" />
            </Button>
            <Button
              v-for="p in pages"
              :key="p"
              :variant="p === page ? 'default' : 'ghost'"
              size="sm"
              class="h-7 min-w-7 px-2 text-xs"
              @click="goToPage(p)"
            >
              {{ p }}
            </Button>
            <Button
              variant="ghost"
              size="icon-sm"
              class="size-7"
              :disabled="page >= totalPages"
              @click="goToPage(page + 1)"
            >
              <ChevronRight class="size-4" />
            </Button>
          </div>
        </div>
      </div>

      <!-- Issues -->
      <div v-if="issues.length > 0" class="space-y-2">
        <h2 class="text-sm font-medium">Issues</h2>
        <div class="rounded-lg border border-border divide-y divide-border">
          <a
            v-for="(issue, i) in issues"
            :key="i"
            :href="issue.href"
            class="flex items-start gap-2 px-3 py-2 text-sm hover:bg-muted/30 transition-colors"
          >
            <AlertTriangle
              v-if="issue.severity === 'warning'"
              class="size-4 text-yellow-500 shrink-0 mt-0.5"
            />
            <Info v-else class="size-4 text-blue-400 shrink-0 mt-0.5" />
            <span class="text-muted-foreground">{{ issue.message }}</span>
          </a>
        </div>
      </div>
    </template>
  </div>
</template>
