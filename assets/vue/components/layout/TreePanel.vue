<script setup>
import { ref, watch, onMounted, computed, nextTick, defineAsyncComponent } from "vue"
import { useLive } from "@/vue/composables/useLive"
import { Pin, X, LayoutDashboard } from "lucide-vue-next"

const treeComponents = {
  sheets: defineAsyncComponent(() => import("@/vue/components/sheets/SheetTree.vue")),
}

const props = defineProps({
  treePanelOpen: { type: Boolean, default: false },
  treePanelPinned: { type: Boolean, default: true },
  showPin: { type: Boolean, default: true },
  activeTool: { type: String, default: "sheets" },
  dashboardUrl: { type: String, default: null },
  onDashboard: { type: Boolean, default: false },
  treeData: { type: [Array, Object], default: null },
  treeProps: { type: Object, default: () => ({}) },
})

const activeTreeComponent = computed(() => treeComponents[props.activeTool] || null)

const live = useLive()
const panelRef = ref(null)
const pendingInit = ref(false)
const internalOpen = ref(false)

// ── localStorage persistence (same keys as v1 TreePanel hook) ──
const KEY_PREFIX = "storyarn:tree_panel:pinned:"
const DEFAULTS = { sheets: true, screenplays: true, flows: false, scenes: false }

function storageKey(tool) {
  return `${KEY_PREFIX}${tool}`
}

function readPinned(tool) {
  const stored = localStorage.getItem(storageKey(tool))
  if (stored !== null) return stored === "true"
  return DEFAULTS[tool] ?? true
}

// ── Animation constants (matching v1 hook exactly) ──
const OPEN_DURATION = 280
const CLOSE_DURATION = 180
const EASING = "ease-out"
const SLIDE_OFFSET = "-20px"

function animateIn() {
  if (window.innerWidth < 1280) return
  const el = panelRef.value
  if (!el) return

  el.style.opacity = "0"
  el.style.transform = `translateX(${SLIDE_OFFSET})`
  el.style.transition = ""

  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      el.style.transition = `transform ${OPEN_DURATION}ms ${EASING}, opacity ${OPEN_DURATION}ms ${EASING}`
      el.style.opacity = "1"
      el.style.transform = "translateX(0)"

      setTimeout(() => {
        el.style.transition = ""
        el.style.opacity = ""
        el.style.transform = ""
      }, OPEN_DURATION)
    })
  })
}

function animateOut() {
  if (window.innerWidth < 1280) return
  const el = panelRef.value
  if (!el) return

  el.style.opacity = "1"
  el.style.transform = "translateX(0)"

  requestAnimationFrame(() => {
    el.style.transition = `transform ${CLOSE_DURATION}ms ${EASING}, opacity ${CLOSE_DURATION}ms ${EASING}`
    el.style.opacity = "0"
    el.style.transform = `translateX(${SLIDE_OFFSET})`

    setTimeout(() => {
      el.style.transition = ""
      el.style.opacity = ""
      el.style.transform = `translateX(${SLIDE_OFFSET})`
    }, CLOSE_DURATION)
  })
}

// ── Lifecycle: mirror v1 hook mounted() ──
onMounted(() => {
  // Migrate: remove old shared key
  localStorage.removeItem("storyarn:tree_panel:pinned")

  const tool = props.activeTool
  const pinned = readPinned(tool)

  if (pinned || props.treePanelOpen) {
    const el = panelRef.value
    if (el) {
      el.style.opacity = "1"
      el.style.pointerEvents = "auto"
    }
    internalOpen.value = true
    pendingInit.value = true
  } else {
    internalOpen.value = false
    const el = panelRef.value
    if (el) {
      el.style.transform = `translateX(${SLIDE_OFFSET})`
    }
  }

  live.pushEvent("tree_panel_init", { pinned })
})

// ── Watch for server-driven open/close changes (mirrors v1 hook updated()) ──
watch(
  () => [props.treePanelOpen, props.treePanelPinned],
  ([nowOpen, pinned]) => {
    const tool = props.activeTool

    if (pendingInit.value) {
      if (nowOpen) {
        // Server confirmed open — persist and clear init state
        localStorage.setItem(storageKey(tool), String(pinned))
        pendingInit.value = false
        const el = panelRef.value
        if (el) {
          el.style.opacity = ""
          el.style.pointerEvents = ""
        }
        internalOpen.value = true
      }
      return
    }

    // Normal operation: persist pin state, animate on change
    localStorage.setItem(storageKey(tool), String(pinned))

    if (nowOpen !== internalOpen.value) {
      internalOpen.value = nowOpen
      nextTick(() => {
        nowOpen ? animateIn() : animateOut()
      })
    }
  },
)

// ── Dashboard link label (matches v1: "Sheets dashboard", "Flows dashboard") ──
const toolLabels = {
  dashboard: "Dashboard",
  sheets: "Sheets",
  flows: "Flows",
  scenes: "Scenes",
  screenplays: "Screenplays",
  assets: "Assets",
  localization: "Localization",
}

const dashboardLabel = computed(() => {
  const label = toolLabels[props.activeTool] || ""
  return `${label} dashboard`
})

// ── Panel classes (mobile: CSS transition, desktop: JS animation) ──
const panelClasses = computed(() => [
  "fixed left-3 top-[76px] bottom-3 z-[1010] w-64 flex flex-col v2-surface-panel overflow-hidden",
  "max-md:transition-transform max-md:duration-200",
  props.treePanelOpen
    ? "max-md:translate-x-0"
    : "max-md:-translate-x-[calc(100%+0.75rem)] md:opacity-0 md:pointer-events-none",
])

function togglePanel() {
  live.pushEvent("tree_panel_toggle", {})
}

function togglePin() {
  live.pushEvent("tree_panel_pin", {})
}
</script>

<template>
  <div ref="panelRef" :class="panelClasses">
    <!-- Navigation header -->
    <div v-if="dashboardUrl" class="px-2 pt-2 pb-2 border-b border-border">
      <a
        :href="dashboardUrl"
        :class="[
          'flex items-center gap-2 px-2 py-1.5 rounded-md text-sm transition-colors',
          onDashboard
            ? 'bg-accent text-accent-foreground font-medium'
            : 'text-muted-foreground hover:text-foreground hover:bg-accent/50',
        ]"
      >
        <LayoutDashboard class="size-4" />
        {{ dashboardLabel }}
      </a>
    </div>

    <!-- Tree content (scrollable) -->
    <div class="flex-1 overflow-y-auto p-2">
      <component
        v-if="activeTreeComponent"
        :is="activeTreeComponent"
        v-bind="treeProps"
      />
      <slot v-else />
    </div>

    <!-- Footer: Pin / Close (hidden on mobile, matches v1) -->
    <div v-if="showPin" class="hidden md:flex items-center justify-end gap-1 px-2 py-1.5 border-t border-border">
      <button
        type="button"
        :class="[
          'inline-flex items-center gap-1 px-2 py-1 rounded-md text-xs transition-colors hover:bg-accent',
          treePanelPinned ? 'text-primary' : 'text-muted-foreground',
        ]"
        :title="treePanelPinned ? 'Unpin panel' : 'Pin panel'"
        @click="togglePin"
      >
        <Pin class="size-3" />
        {{ treePanelPinned ? "Pinned" : "Pin" }}
      </button>
      <button
        type="button"
        class="inline-flex items-center justify-center size-6 rounded-md text-muted-foreground hover:text-foreground hover:bg-accent transition-colors"
        title="Close panel"
        @click="togglePanel"
      >
        <X class="size-3" />
      </button>
    </div>
  </div>
</template>
