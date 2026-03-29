<script setup>
import { computed } from "vue";
import { Database, GitBranch, Play, Upload } from "lucide-vue-next";
import { useRevealOnScroll } from "../composables/useRevealOnScroll.js";

const props = defineProps({
	translations: { type: Object, required: true },
});

const steps = computed(() => [
	{
		num: "01",
		icon: Database,
		title: props.translations.workflow_step_1_title,
		desc: props.translations.workflow_step_1_desc,
	},
	{
		num: "02",
		icon: GitBranch,
		title: props.translations.workflow_step_2_title,
		desc: props.translations.workflow_step_2_desc,
	},
	{
		num: "03",
		icon: Play,
		title: props.translations.workflow_step_3_title,
		desc: props.translations.workflow_step_3_desc,
	},
	{
		num: "04",
		icon: Upload,
		title: props.translations.workflow_step_4_title,
		desc: props.translations.workflow_step_4_desc,
	},
]);

const { elementRef: sectionRef, isRevealed } = useRevealOnScroll();
</script>

<template>
	<section
		id="workflow"
		ref="sectionRef"
		class="relative py-28"
		:class="{ 'opacity-0 translate-y-7': !isRevealed, 'opacity-100 translate-y-0': isRevealed }"
		style="transition: opacity 1s cubic-bezier(0.22, 1, 0.36, 1), transform 1s cubic-bezier(0.22, 1, 0.36, 1)"
	>
		<div class="mx-auto w-[min(calc(100%-48px),1280px)]">
			<!-- Section header -->
			<div class="mb-10 max-w-[56rem]">
				<h2
					class="text-[clamp(2.2rem,3vw,3.8rem)] font-bold leading-[0.97] tracking-[-0.06em] text-foreground"
				>
					{{ translations.workflow_title }}
				</h2>
				<p class="mt-4 max-w-[36rem] text-base leading-relaxed text-muted-foreground">
					{{ translations.workflow_subtitle }}
				</p>
			</div>

			<!-- Step cards -->
			<div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
				<article
					v-for="(step, i) in steps"
					:key="step.num"
					class="rounded-2xl border border-border bg-muted/40 p-6 backdrop-blur-sm"
					:style="{ transitionDelay: `${i * 100}ms` }"
				>
					<div class="mb-4 flex items-center gap-3">
						<span class="text-xs font-bold uppercase tracking-widest text-primary/60">
							{{ step.num }}
						</span>
						<component :is="step.icon" class="size-4 text-muted-foreground" />
					</div>
					<h3 class="mb-2 text-lg font-bold tracking-tight text-foreground">
						{{ step.title }}
					</h3>
					<p class="text-sm leading-relaxed text-muted-foreground">{{ step.desc }}</p>
				</article>
			</div>
		</div>
	</section>
</template>
