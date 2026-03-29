<script setup>
import {
	ArrowLeft,
	ChevronLeft,
	ChevronRight,
	Columns2,
} from "lucide-vue-next";
import { Button } from "@/vue/components/ui/button";

const props = defineProps({
	backUrl: { type: String, required: true },
	versionLabel: { type: String, default: "" },
	prevVersionUrl: { type: String, default: null },
	nextVersionUrl: { type: String, default: null },
	currentUrl: { type: String, default: "" },
	versionUrl: { type: String, default: "" },
});
</script>

<template>
	<div class="h-screen w-screen flex flex-col bg-background">
		<!-- Compare header bar -->
		<header
			class="h-11 shrink-0 flex items-center justify-between px-4 bg-muted border-b border-border"
		>
			<div class="flex items-center gap-3">
				<a
					:href="backUrl"
					data-phx-link="redirect"
					data-phx-link-state="push"
					aria-label="Back to editor"
				>
					<Button variant="ghost" size="icon-sm">
						<ArrowLeft class="size-4" />
					</Button>
				</a>
				<div
					class="flex items-center gap-1.5 text-sm text-muted-foreground"
				>
					<Columns2 class="size-4" />
					<span class="font-medium">Comparing versions</span>
				</div>
			</div>
			<div class="flex items-center gap-1">
				<a
					v-if="prevVersionUrl"
					:href="prevVersionUrl"
					data-phx-link="patch"
					data-phx-link-state="push"
					aria-label="Previous version"
				>
					<Button variant="ghost" size="xs">
						<ChevronLeft class="size-3.5" />
					</Button>
				</a>
				<span class="text-xs text-muted-foreground/60 px-1">{{
					versionLabel
				}}</span>
				<a
					v-if="nextVersionUrl"
					:href="nextVersionUrl"
					data-phx-link="patch"
					data-phx-link-state="push"
					aria-label="Next version"
				>
					<Button variant="ghost" size="xs">
						<ChevronRight class="size-3.5" />
					</Button>
				</a>
			</div>
		</header>

		<!-- Split panes -->
		<div
			class="flex-1 overflow-hidden grid grid-cols-2 divide-x divide-border"
		>
			<!-- Left: current state -->
			<div class="flex flex-col overflow-hidden">
				<div
					class="h-8 shrink-0 flex items-center justify-center bg-muted/50 border-b border-border text-xs font-medium text-muted-foreground/50"
				>
					Current
				</div>
				<iframe
					:src="currentUrl"
					class="flex-1 w-full border-0"
					title="Current"
				/>
			</div>

			<!-- Right: historical version -->
			<div class="flex flex-col overflow-hidden">
				<div
					class="h-8 shrink-0 flex items-center justify-center bg-muted/50 border-b border-border text-xs font-medium text-muted-foreground/50"
				>
					{{ versionLabel }}
				</div>
				<iframe
					:src="versionUrl"
					class="flex-1 w-full border-0"
					:title="versionLabel"
				/>
			</div>
		</div>
	</div>
</template>
