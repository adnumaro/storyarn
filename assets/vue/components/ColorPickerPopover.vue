<script setup>
/**
 * Color picker using vanilla-colorful web components inside shadcn Popover.
 * Web component events are attached imperatively via a container ref.
 */
import { ref, watch, onBeforeUnmount } from "vue";
import { ChevronDown, Pipette } from "lucide-vue-next";
import {
	Popover,
	PopoverContent,
	PopoverTrigger,
} from "@/vue/components/ui/popover";

import "vanilla-colorful/hex-color-picker.js";
import "vanilla-colorful/hex-input.js";

const props = defineProps({
	color: { type: String, default: "#3b82f6" },
	disabled: { type: Boolean, default: false },
	variant: { type: String, default: "swatch" },
});

const emit = defineEmits(["update:color"]);

const localColor = ref(props.color);
const containerRef = ref(null);
let debounceTimer = null;
let picker = null;
let hexInput = null;

watch(
	() => props.color,
	(v) => {
		localColor.value = v;
	},
);

function pushColor(hex) {
	localColor.value = hex;
	clearTimeout(debounceTimer);
	debounceTimer = setTimeout(() => {
		emit("update:color", hex);
	}, 150);
}

function onPopoverOpen(open) {
	if (!open) return;
	// Wait for DOM to be ready, then build picker imperatively
	requestAnimationFrame(() => {
		requestAnimationFrame(() => {
			buildPicker();
		});
	});
}

function buildPicker() {
	const container = containerRef.value;
	if (!container) return;

	// Clear previous
	container.innerHTML = "";

	// Create hex-color-picker
	picker = document.createElement("hex-color-picker");
	picker.setAttribute("color", localColor.value);
	picker.style.width = "100%";
	picker.style.setProperty("--hcp-height", "140px");
	picker.addEventListener("color-changed", onPickerChanged);
	container.appendChild(picker);

	// Bottom row
	const row = document.createElement("div");
	row.style.cssText =
		"display:flex;align-items:center;gap:8px;margin-top:10px;";

	// Eyedropper
	if (window.EyeDropper) {
		const eyeBtn = document.createElement("button");
		eyeBtn.type = "button";
		eyeBtn.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m2 22 1-1h3l9-9"/><path d="M3 21v-3l9-9"/><path d="m15 6 3.4-3.4a2.1 2.1 0 1 1 3 3L18 9l.4.4a2.1 2.1 0 1 1-3 3l-3.8-3.8a2.1 2.1 0 1 1 3-3l.4.4Z"/></svg>`;
		eyeBtn.style.cssText =
			"display:flex;align-items:center;justify-content:center;width:28px;height:28px;border-radius:0.375rem;border:1px solid hsl(var(--border));background:hsl(var(--muted));cursor:pointer;color:hsl(var(--muted-foreground));flex-shrink:0;";
		eyeBtn.title = "Pick color from screen";
		eyeBtn.addEventListener("click", async () => {
			try {
				const dropper = new EyeDropper();
				const result = await dropper.open();
				setColor(result.sRGBHex);
			} catch {
				/* cancelled */
			}
		});
		row.appendChild(eyeBtn);
	}

	// Swatch preview
	const swatch = document.createElement("div");
	swatch.style.cssText = `width:22px;height:22px;border-radius:5px;border:1px solid hsl(var(--border));background:${localColor.value};flex-shrink:0;`;
	row.appendChild(swatch);

	// # label
	const hash = document.createElement("span");
	hash.textContent = "#";
	hash.style.cssText =
		"font-family:monospace;font-size:11px;color:hsl(var(--muted-foreground));opacity:0.4;flex-shrink:0;";
	row.appendChild(hash);

	// hex-input
	hexInput = document.createElement("hex-input");
	hexInput.setAttribute("color", localColor.value);
	hexInput.setAttribute("alpha", "");
	hexInput.style.cssText = "flex:1;min-width:0;";
	const innerInput = document.createElement("input");
	innerInput.style.cssText =
		"width:100%;font-family:monospace;font-size:11px;border:1px solid hsl(var(--border));border-radius:0.25rem;padding:3px 6px;background:hsl(var(--muted));color:hsl(var(--foreground));outline:none;";
	hexInput.appendChild(innerInput);
	hexInput.addEventListener("color-changed", onHexChanged);
	row.appendChild(hexInput);

	container.appendChild(row);

	// Store swatch ref for updates
	container._swatch = swatch;
}

function onPickerChanged(e) {
	const hex = e.detail.value;
	pushColor(hex);
	if (hexInput) hexInput.color = hex;
	if (containerRef.value?._swatch)
		containerRef.value._swatch.style.background = hex;
}

function onHexChanged(e) {
	const hex = e.detail.value;
	pushColor(hex);
	if (picker) picker.color = hex;
	if (containerRef.value?._swatch)
		containerRef.value._swatch.style.background = hex;
}

function setColor(hex) {
	pushColor(hex);
	if (picker) picker.color = hex;
	if (hexInput) hexInput.color = hex;
	if (containerRef.value?._swatch)
		containerRef.value._swatch.style.background = hex;
}

onBeforeUnmount(() => {
	clearTimeout(debounceTimer);
});
</script>

<template>
  <Popover @update:open="onPopoverOpen">
    <!-- Trigger: swatch circle or full (swatch+hex+chevron) -->
    <PopoverTrigger as-child>
      <button
        v-if="variant === 'swatch'"
        :disabled="disabled"
        class="size-7 rounded-full border-2 border-white/50 shadow-sm hover:scale-110 transition-transform"
        :style="{ backgroundColor: localColor }"
        title="Change color"
      />
      <div
        v-else
        class="inline-flex items-center gap-1.5 px-2 py-1 border border-border rounded-md bg-card cursor-pointer hover:bg-accent/50 transition-colors"
      >
        <div class="size-4 rounded shrink-0 border border-border" :style="{ backgroundColor: localColor }" />
        <span class="font-mono text-[11px] text-muted-foreground/60 flex-1">{{ localColor }}</span>
        <ChevronDown class="size-2.5 opacity-35 shrink-0" />
      </div>
    </PopoverTrigger>

    <PopoverContent align="end" :side-offset="8" class="w-[252px] p-3">
      <!-- Container for imperatively built picker -->
      <div ref="containerRef" />
    </PopoverContent>
  </Popover>
</template>

<style>
/* Style vanilla-colorful to match dark theme */
hex-color-picker {
  --hcp-background: transparent;
  --hcp-border: 0;
}

hex-color-picker::part(saturation) {
  border-radius: 0.375rem;
  border-bottom: none;
}

hex-color-picker::part(hue) {
  border-radius: 9999px;
  height: 10px;
  margin-top: 0.5rem;
}

hex-color-picker::part(saturation-pointer),
hex-color-picker::part(hue-pointer) {
  width: 16px;
  height: 16px;
  border: 2px solid white;
  box-shadow: 0 0 0 1px rgba(0, 0, 0, 0.3);
}
</style>
