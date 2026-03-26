<script setup>
import { onMounted, ref, watch } from "vue";
import { useLive } from "@/vue/composables/useLive";
import { useFlowEditor } from "./composables/useFlowEditor";

const props = defineProps({
	flowData: { type: String, default: null },
	sheetsMap: { type: String, default: null },
	labels: { type: String, default: "{}" },
	loading: { type: Boolean, default: true },
	readonly: { type: Boolean, default: false },
	userId: { type: [Number, String], default: 0 },
	userColor: { type: String, default: "#3b82f6" },
	canvasId: { type: String, default: "flow-canvas" },
});

const containerRef = ref(null);
const live = useLive();
let initialized = false;

const { init } = useFlowEditor({
	pushEvent: live.pushEvent,
	handleEvent: live.handleEvent,
});

async function initCanvas() {
	if (initialized || !containerRef.value || !props.flowData) return;
	initialized = true;

	const flowData = JSON.parse(props.flowData);
	const sheetsMap = props.sheetsMap ? JSON.parse(props.sheetsMap) : {};
	const labels = JSON.parse(props.labels);

	await init(containerRef.value, flowData, {
		sheetsMap,
		labels,
		readonly: props.readonly,
		userId: Number(props.userId),
		userColor: props.userColor,
	});
}

// Init when flowData becomes available (loading → loaded transition)
watch(() => props.flowData, (val) => {
	if (val && !initialized) initCanvas();
});

onMounted(() => {
	if (props.flowData) initCanvas();
});
</script>

<template>
  <div v-if="loading" class="w-full h-full flex items-center justify-center text-muted-foreground text-sm">
    Loading...
  </div>
  <div
    v-show="!loading"
    ref="containerRef"
    :id="canvasId"
    class="w-full h-full"
  />
</template>
