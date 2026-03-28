<script setup>
import {
	AlertTriangle,
	Box,
	Clock,
	FileText,
	GitBranch,
	Info,
	Map as MapIcon,
	MessageSquare,
	ScrollText,
	Text,
	Variable,
} from "lucide-vue-next";
import { computed } from "vue";
import { Badge } from "@/vue/components/ui/badge";
import { useLive } from "@/vue/composables/useLive";
import { formatRelativeTime } from "@/vue/lib/date-utils";

const props = defineProps({
	stats: { type: Object, default: null },
	nodeDist: { type: Array, default: () => [] },
	speakers: { type: Array, default: () => [] },
	issues: { type: Array, default: () => [] },
	localization: { type: Array, default: () => [] },
	activity: { type: Array, default: () => [] },
	canEdit: { type: Boolean, default: false },
	workspaceSlug: { type: String, required: true },
	projectSlug: { type: String, required: true },
	loading: { type: Boolean, default: false },
});

const live = useLive();

const statCards = computed(() => {
	if (!props.stats) return [];
	return [
		{
			icon: FileText,
			label: "Sheets",
			value: props.stats.sheet_count,
			href: `/workspaces/${props.workspaceSlug}/projects/${props.projectSlug}/sheets`,
		},
		{
			icon: Variable,
			label: "Variables",
			value: props.stats.variable_count,
			href: `/workspaces/${props.workspaceSlug}/projects/${props.projectSlug}/sheets`,
		},
		{
			icon: GitBranch,
			label: "Flows",
			value: props.stats.flow_count,
			href: `/workspaces/${props.workspaceSlug}/projects/${props.projectSlug}/flows`,
		},
		{
			icon: MessageSquare,
			label: "Dialogue Lines",
			value: props.stats.dialogue_count,
			href: `/workspaces/${props.workspaceSlug}/projects/${props.projectSlug}/flows`,
		},
		{
			icon: MapIcon,
			label: "Scenes",
			value: props.stats.scene_count,
			href: `/workspaces/${props.workspaceSlug}/projects/${props.projectSlug}/scenes`,
		},
		{
			icon: Text,
			label: "Words",
			value: props.stats.total_word_count,
			href: null,
		},
	];
});

const activityIcons = {
	sheet: FileText,
	flow: GitBranch,
	scene: MapIcon,
	screenplay: ScrollText,
	node: Box,
};

function activityIcon(type) {
	return activityIcons[type] || Clock;
}

function activityTypeLabel(type) {
	const labels = {
		sheet: "Sheet",
		flow: "Flow",
		scene: "Scene",
		screenplay: "Screenplay",
	};
	return labels[type] || type;
}
</script>

<template>
  <div class="max-w-5xl mx-auto px-4 sm:px-6 py-8 space-y-6">
    <!-- Loading State -->
    <div v-if="loading" class="flex justify-center py-12">
      <div class="size-6 border-2 border-muted-foreground/20 border-t-muted-foreground/60 rounded-full animate-spin" />
    </div>

    <!-- Dashboard Content -->
    <div v-else class="space-y-6">
      <!-- Section 1: Stats -->
      <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
        <a
          v-for="stat in statCards"
          :key="stat.label"
          :href="stat.href"
          class="rounded-lg border border-border bg-surface p-4 space-y-2 transition-colors"
          :class="stat.href ? 'hover:bg-muted/30 cursor-pointer' : 'cursor-default'"
        >
          <div class="flex items-center gap-2 text-xs text-muted-foreground">
            <component :is="stat.icon" class="size-4" />
            {{ stat.label }}
          </div>
          <p class="text-2xl font-bold tabular-nums">{{ stat.value }}</p>
        </a>
      </div>

      <!-- Section 2: Content Breakdown -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <!-- Node Distribution -->
        <div class="rounded-lg border border-border bg-surface p-4 space-y-3">
          <h2 class="text-sm font-medium">Node Distribution</h2>
          <div v-if="nodeDist.length === 0" class="text-sm text-muted-foreground/50 py-2 text-center">
            No flow nodes yet
          </div>
          <div v-else class="space-y-1.5">
            <div
              v-for="item in nodeDist"
              :key="item.label"
              class="flex items-center justify-between text-sm"
            >
              <span class="text-muted-foreground">{{ item.label }}</span>
              <div class="flex items-center gap-2">
                <span class="tabular-nums font-medium">{{ item.count }}</span>
                <span class="text-xs text-muted-foreground/60 tabular-nums w-10 text-right">
                  {{ item.percentage }}%
                </span>
              </div>
            </div>
          </div>
        </div>

        <!-- Top Speakers -->
        <div class="rounded-lg border border-border bg-surface p-4 space-y-3">
          <h2 class="text-sm font-medium">Top Speakers</h2>
          <div v-if="speakers.length === 0" class="text-sm text-muted-foreground/50 py-2 text-center">
            No dialogue with speakers yet
          </div>
          <div v-else class="space-y-1.5">
            <div
              v-for="item in speakers"
              :key="item.name"
              class="flex items-center justify-between text-sm"
            >
              <a
                v-if="item.href"
                :href="item.href"
                class="text-muted-foreground hover:text-foreground hover:underline transition-colors"
              >
                {{ item.name }}
              </a>
              <span v-else class="text-muted-foreground">{{ item.name }}</span>
              <span class="tabular-nums font-medium">{{ item.count }}</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Section 3: Issues & Warnings -->
      <div v-if="issues.length > 0" class="space-y-2">
        <h2 class="text-sm font-medium">Issues & Warnings</h2>
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

      <!-- Section 4: Localization Progress (conditional) -->
      <div v-if="localization.length > 0" class="rounded-lg border border-border bg-surface p-4 space-y-3">
        <h2 class="text-sm font-medium">Localization Progress</h2>
        <div class="space-y-2">
          <a
            v-for="lang in localization"
            :key="lang.name"
            :href="`/workspaces/${workspaceSlug}/projects/${projectSlug}/localization`"
            class="flex items-center gap-3 group hover:bg-muted/30 -mx-2 px-2 py-1 rounded transition-colors"
          >
            <span class="text-sm text-muted-foreground w-28 shrink-0 truncate group-hover:text-foreground transition-colors">
              {{ lang.name }}
            </span>
            <div class="flex-1 h-2 rounded-full bg-muted overflow-hidden">
              <div
                class="h-full rounded-full bg-primary transition-all"
                :style="{ width: `${lang.percentage}%` }"
              />
            </div>
            <span class="text-xs text-muted-foreground tabular-nums shrink-0">
              {{ lang.final }} / {{ lang.total }}
            </span>
          </a>
        </div>
      </div>

      <!-- Section 5: Recent Activity -->
      <div class="rounded-lg border border-border bg-surface p-4 space-y-3">
        <h2 class="text-sm font-medium">Recent Activity</h2>
        <div v-if="activity.length === 0" class="text-sm text-muted-foreground/50 py-2 text-center">
          No activity yet
        </div>
        <div v-else class="space-y-0.5">
          <div
            v-for="(item, i) in activity"
            :key="i"
            class="flex items-center gap-3 py-1.5"
          >
            <component :is="activityIcon(item.type)" class="size-4 text-muted-foreground/40 shrink-0" />
            <span class="text-sm flex-1 min-w-0">
              <span class="font-medium truncate">{{ item.name }}</span>
              <span class="text-muted-foreground/50">
                &middot; {{ activityTypeLabel(item.type) }}
              </span>
            </span>
            <span class="text-xs text-muted-foreground/40 shrink-0">
              {{ formatRelativeTime(item.updated_at) }}
            </span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
