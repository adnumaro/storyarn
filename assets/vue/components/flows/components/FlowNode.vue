<script setup>
import { computed } from "vue";
import { Ref } from "rete-vue-plugin";
import { NODE_CONFIGS } from "@/js/flow_canvas/node_config.js";

const props = defineProps({
	data: { type: Object, required: true },
	emit: { type: Function, required: true },
	sheetsMap: { type: Object, default: () => ({}) },
	hubsMap: { type: Object, default: () => ({}) },
	labels: { type: Object, default: () => ({}) },
	lod: { type: String, default: "full" },
});

const nodeType = computed(() => props.data?.nodeType || "dialogue");
const config = computed(() => NODE_CONFIGS[nodeType.value] || NODE_CONFIGS.dialogue);
const nodeData = computed(() => props.data?.nodeData || {});
const selected = computed(() => props.data?.selected || false);

const nodeColor = computed(() => {
	const d = nodeData.value;
	if (nodeType.value === "dialogue" && d.speaker_sheet_id) {
		const sheet = props.sheetsMap[String(d.speaker_sheet_id)];
		if (sheet?.color) return sheet.color;
	}
	if ((nodeType.value === "hub" || nodeType.value === "exit") && d.color_hex) {
		return d.color_hex;
	}
	if (nodeType.value === "annotation") return d.color || "#fbbf24";
	return config.value.color;
});

const borderColor = computed(() => `${nodeColor.value}40`);

const inputs = computed(() => Object.entries(props.data?.inputs || {}));
const outputs = computed(() => Object.entries(props.data?.outputs || {}));

const previewText = computed(() => {
	const d = nodeData.value;
	if (nodeType.value === "dialogue") {
		const raw = d.text || "";
		const stripped = raw.replace(/<[^>]*>/g, "").trim();
		return stripped.length > 60 ? `${stripped.slice(0, 60)}…` : stripped;
	}
	return "";
});
</script>

<template>
  <div
    class="node relative bg-background rounded-xl min-w-[120px] border-[1.5px] shadow-md"
    :class="{ selected }"
    :style="{ borderColor }"
    data-testid="node"
  >
    <!-- Header -->
    <div
      class="px-3 py-2 rounded-t-[10px] flex items-center gap-2 text-white font-medium text-[13px]"
      :style="{ backgroundColor: nodeColor }"
    >
      <span class="flex items-center shrink-0" v-html="config.icon" />
      <span class="truncate" data-testid="title">{{ config.label }}</span>
    </div>

    <!-- Preview text -->
    <div v-if="previewText" class="px-3 py-1.5 text-[11px] text-muted-foreground leading-snug line-clamp-2">
      {{ previewText }}
    </div>

    <!-- Sockets -->
    <div class="py-1">
      <!-- Single row layout (1 input + 1 output) -->
      <template v-if="inputs.length <= 1 && outputs.length <= 1">
        <div class="flex items-center justify-between">
          <div v-for="[key, input] in inputs" :key="'i-' + key" class="flex items-center py-0.5">
            <Ref
              class="input-socket"
              :data="{ type: 'socket', side: 'input', key, nodeId: data.id, payload: input.socket }"
              :emit="emit"
              data-testid="input-socket"
            />
          </div>
          <div v-for="[key, output] in outputs" :key="'o-' + key" class="flex items-center py-0.5">
            <Ref
              class="output-socket"
              :data="{ type: 'socket', side: 'output', key, nodeId: data.id, payload: output.socket }"
              :emit="emit"
              data-testid="output-socket"
            />
          </div>
        </div>
      </template>

      <!-- Multi-row layout -->
      <template v-else>
        <div v-for="[key, input] in inputs" :key="'i-' + key" class="flex items-center py-0.5 text-[11px] text-muted-foreground justify-start">
          <Ref
            class="input-socket"
            :data="{ type: 'socket', side: 'input', key, nodeId: data.id, payload: input.socket }"
            :emit="emit"
            data-testid="input-socket"
          />
          <span class="ml-2">{{ input.label || key }}</span>
        </div>
        <div v-for="[key, output] in outputs" :key="'o-' + key" class="flex items-center py-0.5 text-[11px] text-muted-foreground justify-end">
          <span class="mr-2">{{ output.label || key }}</span>
          <Ref
            class="output-socket"
            :data="{ type: 'socket', side: 'output', key, nodeId: data.id, payload: output.socket }"
            :emit="emit"
            data-testid="output-socket"
          />
        </div>
      </template>
    </div>
  </div>
</template>
