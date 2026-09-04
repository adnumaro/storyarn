<script setup lang="ts">
import { Lock } from "@lucide/vue";

/**
 * A titled card of rows. `locked` dims the section and makes it inert until
 * the user re-authenticates; `tone="danger"` is the danger zone.
 */
const {
  title,
  hint = null,
  tone = "default",
  locked = false,
  lockedLabel = null,
} = defineProps<{
  title: string;
  hint?: string | null;
  tone?: "default" | "danger";
  locked?: boolean;
  lockedLabel?: string | null;
}>();
</script>

<template>
  <section :class="['flex flex-col gap-2.5', locked && 'opacity-60']">
    <div class="flex flex-wrap items-baseline gap-x-2 gap-y-1">
      <h2
        :class="[
          'flex items-center gap-2 text-[15px] font-medium',
          tone === 'danger' && 'text-destructive',
        ]"
      >
        {{ title }}
        <Lock
          v-if="locked"
          class="size-[13px] text-muted-foreground"
          :aria-label="lockedLabel ?? undefined"
          :title="lockedLabel ?? undefined"
        />
      </h2>
      <span v-if="hint" class="text-xs text-muted-foreground">{{ hint }}</span>
      <slot name="title-extra" />
    </div>

    <div
      :class="[
        'divide-y divide-border rounded-lg border bg-card',
        tone === 'danger' ? 'border-destructive/40' : 'border-border',
      ]"
      :inert="locked || undefined"
    >
      <slot />
    </div>

    <p v-if="$slots.footer" class="text-xs text-muted-foreground">
      <slot name="footer" />
    </p>
  </section>
</template>
