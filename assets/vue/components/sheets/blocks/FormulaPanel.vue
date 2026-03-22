<script setup>
import { ref, watch, computed } from "vue";
import { useLive } from "@/vue/composables/useLive";
import { Sigma, X, ChevronRight, AlertCircle } from "lucide-vue-next";
import Sidebar from "@/vue/components/layout/Sidebar.vue";
import FormulaBindingSelect from "./FormulaBindingSelect.vue";
import katex from "katex";

const props = defineProps({
	formulaEditing: { type: Object, default: null },
});

const live = useLive();

// ── Local expression state ──
const localExpression = ref("");
const expressionDirty = ref(false);

watch(
	() => props.formulaEditing?.expression,
	(expr) => {
		if (!expressionDirty.value) {
			localExpression.value = expr || "";
		}
	},
	{ immediate: true },
);

// ── LaTeX rendering via v-html ──
function safeRenderToString(latex) {
	if (!latex) return "";
	try {
		return katex.renderToString(latex, {
			displayMode: true,
			throwOnError: false,
		});
	} catch {
		return `<span class="text-sm text-muted-foreground">${latex}</span>`;
	}
}

const previewHtml = computed(() =>
	safeRenderToString(props.formulaEditing?.preview_latex),
);
const resultHtml = computed(() =>
	safeRenderToString(props.formulaEditing?.result_latex),
);

// ── Actions ──
const isOpen = computed(() => props.formulaEditing != null);

function close() {
	expressionDirty.value = false;
	live.pushEvent("close_formula_sidebar", {});
}

function saveExpression() {
	expressionDirty.value = false;
	const fe = props.formulaEditing;
	if (!fe) return;
	live.pushEvent("save_formula_expression", {
		value: localExpression.value,
		"row-id": fe.row_id,
		"column-slug": fe.column_slug,
	});
}

function onExpressionInput() {
	expressionDirty.value = true;
}

function saveBinding(symbol, value) {
	const fe = props.formulaEditing;
	if (!fe) return;
	live.pushEvent("save_formula_binding", {
		symbol,
		binding_value: value,
		"row-id": fe.row_id,
		"column-slug": fe.column_slug,
	});
}
</script>

<template>
	<Sidebar side="right" :open="isOpen" @close="close">
		<template #header>
			<div class="flex items-center gap-2 px-3 py-2.5">
				<Sigma class="size-3.5 text-primary" />
				<span class="font-medium text-sm flex-1">Formula Editor</span>
				<button
					type="button"
					class="inline-flex items-center justify-center size-6 rounded-md text-muted-foreground hover:text-foreground hover:bg-accent transition-colors"
					title="Close panel"
					@click="close"
				>
					<X class="size-3" />
				</button>
			</div>
		</template>

		<div v-if="formulaEditing" class="space-y-3">
			<!-- Breadcrumb -->
			<div class="flex items-center gap-1 text-xs text-muted-foreground flex-wrap">
				<span v-if="formulaEditing.table_name" class="truncate max-w-24">{{ formulaEditing.table_name }}</span>
				<ChevronRight v-if="formulaEditing.table_name" class="size-3 shrink-0 opacity-40" />
				<span v-if="formulaEditing.row_name" class="truncate max-w-24">{{ formulaEditing.row_name }}</span>
				<ChevronRight v-if="formulaEditing.row_name" class="size-3 shrink-0 opacity-40" />
				<span class="truncate max-w-24 font-medium text-foreground">{{ formulaEditing.column_name || formulaEditing.column_slug }}</span>
			</div>

			<!-- LaTeX Preview -->
			<div v-if="previewHtml" class="bg-muted/50 rounded-lg p-3 overflow-x-auto">
				<!-- eslint-disable-next-line vue/no-v-html -->
				<div class="text-center" v-html="previewHtml" />
			</div>

			<!-- Expression Input -->
			<div>
				<label class="text-xs font-medium text-muted-foreground mb-1 block">Expression</label>
				<input
					v-model="localExpression"
					type="text"
					class="w-full px-2 py-1.5 text-xs bg-transparent border border-border rounded-md outline-none focus:border-ring font-mono"
					placeholder="e.g. (a + b) * 2"
					spellcheck="false"
					autocomplete="off"
					@input="onExpressionInput"
					@blur="saveExpression"
					@keydown.enter.prevent="saveExpression"
				/>
				<div v-if="formulaEditing.parse_error" class="flex items-center gap-1.5 mt-1.5 text-xs text-destructive">
					<AlertCircle class="size-3 shrink-0" />
					<span>{{ formulaEditing.parse_error }}</span>
				</div>
			</div>

			<!-- Symbol Bindings -->
			<div v-if="formulaEditing.symbols?.length > 0">
				<label class="text-xs font-medium text-muted-foreground mb-2 block">Variable Bindings</label>
				<div class="space-y-2">
					<div v-for="symbol in formulaEditing.symbols" :key="symbol" class="flex items-center gap-2">
						<span class="font-mono text-sm text-primary/80 w-8 shrink-0 text-right">{{ symbol }}</span>
						<span class="text-muted-foreground/40 text-xs">=</span>
						<FormulaBindingSelect
							:model-value="formulaEditing.symbol_bindings?.[symbol] || ''"
							:same-row-options="formulaEditing.same_row_options || []"
							:search-results="formulaEditing.search_results || []"
							:has-more="formulaEditing.has_more || false"
							@update:model-value="(v) => saveBinding(symbol, v)"
						/>
					</div>
				</div>
			</div>

			<!-- Result -->
			<div v-if="resultHtml">
				<label class="text-xs font-medium text-muted-foreground mb-1 block">Result</label>
				<div class="bg-muted/50 rounded-lg p-3 overflow-x-auto">
					<!-- eslint-disable-next-line vue/no-v-html -->
					<div class="text-center" v-html="resultHtml" />
				</div>
			</div>

			<div v-else-if="formulaEditing.result != null">
				<label class="text-xs font-medium text-muted-foreground mb-1 block">Result</label>
				<div class="bg-muted/50 rounded-lg p-3 text-center text-sm font-mono">
					{{ formulaEditing.result }}
				</div>
			</div>
		</div>
	</Sidebar>
</template>
