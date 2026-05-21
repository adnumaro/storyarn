<script setup lang="ts">
import { computed, reactive, watch } from "vue";
import { useLiveVue } from "live_vue";
import { AlertCircle, AlertTriangle, Info, LoaderCircle, X } from "lucide-vue-next";

type FlashKind = "info" | "warning" | "error";

interface FlashMessages {
  info?: string | null;
  warning?: string | null;
  error?: string | null;
}

interface NetworkFlash {
  clientTitle: string;
  serverTitle: string;
  reconnecting: string;
}

const { flash = {}, network } = defineProps<{
  flash?: FlashMessages;
  network: NetworkFlash;
}>();

const live = useLiveVue();
const dismissed = reactive<Record<FlashKind, string | null>>({
  info: null,
  warning: null,
  error: null,
});

watch(
  () => flash.info,
  () => {
    dismissed.info = null;
  },
);

watch(
  () => flash.error,
  () => {
    dismissed.error = null;
  },
);

watch(
  () => flash.warning,
  () => {
    dismissed.warning = null;
  },
);

const flashes = computed(() =>
  (["info", "warning", "error"] as FlashKind[])
    .map((kind) => ({ kind, message: flash[kind] ?? null }))
    .filter(({ kind, message }) => message && dismissed[kind] !== message),
);

function dismiss(kind: FlashKind, message: string | null): void {
  dismissed[kind] = message;
  live.pushEvent("lv:clear-flash", { key: kind });
}
</script>

<template>
  <div
    aria-live="polite"
    data-slot="toaster"
    class="fixed bottom-4 right-4 flex w-full max-w-sm flex-col gap-2 pointer-events-none *:pointer-events-auto"
    style="z-index: 2000"
  >
    <div
      v-for="{ kind, message } in flashes"
      :id="`flash-${kind}`"
      class="bg-background rounded-lg"
    >
      <button
        :key="kind"
        type="button"
        role="alert"
        data-slot="toast"
        :class="[
          'group relative flex w-full cursor-pointer items-start gap-3 overflow-hidden rounded-lg border p-4 text-left shadow-lg transition-all',
          'data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0',
          kind === 'info' && 'border-border bg-background text-foreground',
          kind === 'warning' && 'border-amber-700 bg-amber-500/20 text-amber-200',
          kind === 'error' && 'border-red-700 bg-red-500/20 text-red-200',
        ]"
        @click="dismiss(kind, message)"
      >
        <Info v-if="kind === 'info'" class="mt-0.5 size-4 shrink-0" />
        <AlertTriangle v-else-if="kind === 'warning'" class="mt-0.5 size-4 shrink-0" />
        <AlertCircle v-else class="mt-0.5 size-4 shrink-0" />
        <p
          data-slot="toast-description"
          :class="['min-w-0 flex-1 text-sm', kind === 'info' && 'text-muted-foreground']"
        >
          {{ message }}
        </p>
        <span
          data-slot="toast-close"
          class="absolute top-3 right-3 rounded-md p-1 opacity-0 transition-opacity group-hover:opacity-100 group-focus:opacity-100"
          aria-hidden="true"
        >
          <X class="size-3.5" />
        </span>
      </button>
    </div>

    <div
      id="client-error"
      role="alert"
      data-slot="toast"
      class="group relative flex w-full items-start gap-3 overflow-hidden rounded-lg border border-red-300 bg-red-50 p-4 text-red-700 shadow-lg dark:border-red-800 dark:bg-red-950 dark:text-red-300"
      hidden
    >
      <AlertCircle class="mt-0.5 size-4 shrink-0" />
      <div class="min-w-0 flex-1">
        <p data-slot="toast-title" class="text-sm font-semibold">{{ network.clientTitle }}</p>
        <p data-slot="toast-description" class="mt-1 flex items-center gap-1.5 text-sm">
          {{ network.reconnecting }}
          <LoaderCircle class="size-4 motion-safe:animate-spin" />
        </p>
      </div>
    </div>

    <div
      id="server-error"
      role="alert"
      data-slot="toast"
      class="group relative flex w-full items-start gap-3 overflow-hidden rounded-lg border border-red-300 bg-red-50 p-4 text-red-700 shadow-lg dark:border-red-800 dark:bg-red-950 dark:text-red-300"
      hidden
    >
      <AlertCircle class="mt-0.5 size-4 shrink-0" />
      <div class="min-w-0 flex-1">
        <p data-slot="toast-title" class="text-sm font-semibold">{{ network.serverTitle }}</p>
        <p data-slot="toast-description" class="mt-1 flex items-center gap-1.5 text-sm">
          {{ network.reconnecting }}
          <LoaderCircle class="size-4 motion-safe:animate-spin" />
        </p>
      </div>
    </div>
  </div>
</template>
