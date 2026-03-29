<script setup>
import { onMounted, onUnmounted } from "@/vue/index.js";
import HeroSection from "./sections/hero/HeroSection.vue";
import FeatureGrid from "./sections/FeatureGrid.vue";
import DiscoverSection from "./sections/discovery/DiscoverSection.vue";
import ExplorationSpotlight from "./sections/ExplorationSpotlight.vue";
import VersionSpotlight from "./sections/VersionSpotlight.vue";
import WorkflowGrid from "./sections/WorkflowGrid.vue";
import CtaWaitlist from "./sections/CtaWaitlist.vue";
import LandingFooter from "./LandingFooter.vue";

const props = defineProps({
	isLoggedIn: { type: Boolean, default: false },
	translations: { type: Object, required: true },
});

// Force dark mode + smooth scroll on the landing page
onMounted(() => {
	document.documentElement.classList.add("dark");
	document.documentElement.style.scrollBehavior = "smooth";
});

onUnmounted(() => {
	document.documentElement.classList.remove("dark");
	document.documentElement.style.scrollBehavior = "";
});
</script>

<template>
	<div class="landing-page">
		<HeroSection :translations="translations" />
		<FeatureGrid :translations="translations" />
		<DiscoverSection :translations="translations" />
		<ExplorationSpotlight :translations="translations" />
		<VersionSpotlight :translations="translations" />
		<WorkflowGrid :translations="translations" />
		<div class="lp-cta-footer-section">
			<CtaWaitlist :translations="translations" />
			<LandingFooter :translations="translations" />
		</div>
	</div>
</template>
