<script setup>
import { onMounted, onUnmounted } from "vue";
import HeroSection from "./HeroSection.vue";
import FeatureGrid from "./FeatureGrid.vue";
import DiscoverSection from "./DiscoverSection.vue";
import ExplorationSpotlight from "./ExplorationSpotlight.vue";
import VersionSpotlight from "./VersionSpotlight.vue";
import WorkflowGrid from "./WorkflowGrid.vue";
import CtaWaitlist from "./CtaWaitlist.vue";
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
