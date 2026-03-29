<script setup>
import { computed } from "vue";
import {
	Table2,
	GitBranch,
	Map,
	Bug,
	Languages,
	Package,
} from "lucide-vue-next";
import { useRevealOnScroll } from "../composables/useRevealOnScroll.js";

const props = defineProps({
	translations: { type: Object, required: true },
});

const features = computed(() => [
	{
		num: "01",
		icon: Table2,
		title: props.translations.feature_1_title,
		desc: props.translations.feature_1_desc,
		color: "primary",
	},
	{
		num: "02",
		icon: GitBranch,
		title: props.translations.feature_2_title,
		desc: props.translations.feature_2_desc,
		color: "accent",
	},
	{
		num: "03",
		icon: Map,
		title: props.translations.feature_3_title,
		desc: props.translations.feature_3_desc,
		color: "secondary",
	},
	{
		num: "04",
		icon: Bug,
		title: props.translations.feature_4_title,
		desc: props.translations.feature_4_desc,
		color: "primary",
	},
	{
		num: "05",
		icon: Languages,
		title: props.translations.feature_5_title,
		desc: props.translations.feature_5_desc,
		color: "accent",
	},
	{
		num: "06",
		icon: Package,
		title: props.translations.feature_6_title,
		desc: props.translations.feature_6_desc,
		color: "secondary",
	},
]);

const { elementRef: sectionRef, isRevealed } = useRevealOnScroll();
</script>

<template>
	<section
		id="features-section"
		ref="sectionRef"
		class="relative z-20 flex min-h-svh items-center bg-linear-to-b from-background via-background to-background"
	>
		<div class="relative z-10 mx-auto w-[min(calc(100%-48px),1280px)] py-28">
			<!-- Section header -->
			<div class="mb-8 max-w-4xl">
				<h2
					class="text-[clamp(2.2rem,3vw,3.8rem)] font-bold leading-[0.97] tracking-[-0.06em] text-foreground"
				>
					{{ translations.features_title }}
				</h2>
				<p class="mt-4 max-w-xl text-base leading-relaxed text-muted-foreground">
					{{ translations.features_subtitle }}
				</p>
			</div>

			<!-- Feature cards -->
			<div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
				<article
					v-for="feature in features"
					:key="feature.num"
					class="rounded-3xl border border-border bg-muted/60 p-5 backdrop-blur-lg transition-all sm:p-6"
				>
					<em
						class="mb-4 inline-flex size-11.5 items-center justify-center rounded-xl not-italic"
						:class="`bg-${feature.color}/10 text-${feature.color}`"
					>
						<component :is="feature.icon" class="size-5" />
					</em>
					<h3 class="mb-3 text-xl font-bold tracking-tight text-foreground">
						{{ feature.title }}
					</h3>
					<p class="leading-relaxed text-muted-foreground">{{ feature.desc }}</p>
				</article>
			</div>
		</div>
	</section>
</template>
