<script setup>
import { computed } from "@/vue/index.js";
import { TriangleAlert, Zap } from "lucide-vue-next";
import NodeHeader from "../components/NodeHeader.vue";
import NodeShell from "../components/NodeShell.vue";
import NodeSockets from "../components/NodeSockets.vue";

const props = defineProps({
	data: { type: Object, required: true },
	emit: { type: Function, required: true },
	config: { type: Object, required: true },
	color: { type: String, required: true },
});

const nodeData = computed(() => props.data.nodeData || {});

// --- Formatting (matching V1 instruction.js exactly) ---

function formatAssignment(assignment) {
	if (!assignment.sheet || !assignment.variable) return null;
	const ref = `${assignment.sheet}.${assignment.variable}`;
	const op = assignment.operator || "set";

	if (op === "set_true") return `Set ${ref} to true`;
	if (op === "set_false") return `Set ${ref} to false`;
	if (op === "toggle") return `Toggle ${ref}`;
	if (op === "clear") return `Clear ${ref}`;

	let valueDisplay;
	if (assignment.value_type === "variable_ref" && assignment.value_sheet && assignment.value) {
		valueDisplay = `${assignment.value_sheet}.${assignment.value}`;
	} else {
		valueDisplay = assignment.value || "?";
	}

	if (op === "set") return `Set ${ref} to ${valueDisplay}`;
	if (op === "add") return `Add ${valueDisplay} to ${ref}`;
	if (op === "subtract") return `Subtract ${valueDisplay} from ${ref}`;

	return `Set ${ref} to ${valueDisplay}`;
}

const summary = computed(() => {
	const assignments = nodeData.value.assignments || [];
	if (assignments.length === 0) return "";
	return assignments
		.slice(0, 3)
		.map(formatAssignment)
		.filter(Boolean)
		.join("\n");
});

const hasWarnings = computed(() =>
	nodeData.value.has_stale_refs || nodeData.value.has_type_warnings,
);
const hasStaleRefs = computed(() => nodeData.value.has_stale_refs);
</script>

<template>
  <NodeShell :color="color" :selected="data.selected">
    <NodeHeader :color="color" :icon="Zap" :label="config.label">
      <div
        v-if="hasWarnings"
        class="ml-auto inline-flex items-center justify-center size-3.5 text-[10px] font-bold rounded-full bg-destructive text-destructive-foreground"
        title="Type mismatch in assignments"
      >!</div>
    </NodeHeader>

    <div v-if="summary || hasStaleRefs" class="text-[11px] text-muted-foreground px-3 py-2 max-w-[200px] border-b border-border/10 break-words">
      <div class="line-clamp-4 leading-[1.4] whitespace-pre-line">
        <span v-if="hasStaleRefs" class="inline-flex items-center gap-0.5 text-destructive mr-1">
          <TriangleAlert class="size-3" />
        </span>
        {{ summary || 'Stale references' }}
      </div>
    </div>

    <NodeSockets :data="data" :emit="emit" />
  </NodeShell>
</template>
