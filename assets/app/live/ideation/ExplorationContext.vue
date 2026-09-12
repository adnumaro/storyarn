<script setup lang="ts">
import { computed, onUnmounted, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { ArrowLeft, Info, Link2, Loader2 } from "@lucide/vue";
import { Button } from "@components/ui/button";
import { Popover, PopoverAnchor, PopoverContent } from "@components/ui/popover";
import { useLive } from "@shared/composables/useLive";
import type { BrainstormingReference } from "./referenceTypes";

const {
  reference,
  sessionId,
  epoch,
  compact = false,
} = defineProps<{
  reference: BrainstormingReference | null;
  sessionId: number;
  epoch: string;
  compact?: boolean;
}>();

const { t, locale } = useI18n();
const live = useLive();
const pending = ref(false);
const error = ref(false);
const available = computed(() => reference?.status !== "unavailable" && !!reference?.current);
const returnLabel = computed(() => {
  const label = t("brainstormingExplorations.return");
  return available.value
    ? `${label}: ${reference?.current?.name}`
    : `${label}: ${t("brainstormingExplorations.contextStatus.unavailable")}`;
});
const detailsLabel = computed(() => {
  const label = t("brainstormingExplorations.details");
  return available.value
    ? label
    : `${label}: ${t("brainstormingExplorations.contextStatus.unavailable")}`;
});
let token: symbol | null = null;
const identity = () => JSON.stringify([epoch, sessionId, reference?.id, reference?.status]);

function reset() {
  token = null;
  pending.value = false;
  error.value = false;
}

watch(identity, reset);
onUnmounted(reset);

function capturedAt(value: string) {
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime())
    ? value
    : new Intl.DateTimeFormat(locale.value, { dateStyle: "medium" }).format(parsed);
}

function request(action: "return" | "details") {
  if (pending.value || !reference || !available.value) return;
  const at = Symbol();
  const source = identity();
  token = at;
  pending.value = true;
  error.value = false;
  const finish = (failed: boolean) => {
    if (token !== at || identity() !== source) return;
    token = null;
    pending.value = false;
    error.value = failed;
  };
  live.pushEvent(
    action === "return" ? "exploration_return" : "references_open",
    { session_id: sessionId, epoch, reference_id: reference.id },
    (reply) => finish(reply?.status !== "ok"),
    () => finish(true),
  );
}
</script>

<template>
  <Popover
    v-if="reference"
    :open="compact && error"
    @update:open="
      (open) => {
        if (!open) error = false;
      }
    "
  >
    <PopoverAnchor as-child>
      <div
        id="brainstorming-origins"
        :class="
          compact
            ? 'relative flex h-8 shrink-0 items-center gap-1'
            : 'flex min-w-0 flex-wrap items-center gap-2'
        "
      >
        <div
          :id="`brainstorming-origin-${reference.id}`"
          :data-status="reference.status"
          :class="compact ? 'sr-only' : 'flex min-w-0 items-center gap-2'"
        >
          <Link2 class="size-3.5 shrink-0 text-muted-foreground" />
          <div class="min-w-0">
            <p class="max-w-64 truncate text-xs font-medium">
              {{
                available
                  ? reference.current?.name
                  : t("brainstormingExplorations.contextStatus.unavailable")
              }}
            </p>
            <template v-if="available">
              <p v-if="reference.status === 'changed'" class="text-[10px] text-muted-foreground">
                {{ t("brainstormingExplorations.contextStatus.changed") }}
              </p>
              <p v-if="reference.base" class="max-w-64 truncate text-[10px] text-muted-foreground">
                {{ t("brainstormingExplorations.savedContext", { name: reference.base.name })
                }}<span v-if="reference.capturedAt"> · {{ capturedAt(reference.capturedAt) }}</span>
              </p>
            </template>
          </div>
        </div>
        <Button
          :id="`brainstorming-origin-details-${reference.id}`"
          variant="ghost"
          size="icon-sm"
          :disabled="pending || !available"
          :aria-label="detailsLabel"
          :title="detailsLabel"
          :class="reference.status === 'changed' ? 'text-primary' : ''"
          @click="request('details')"
          ><Info class="size-3.5"
        /></Button>
        <Button
          :id="`brainstorming-origin-return-${reference.id}`"
          :variant="compact ? 'ghost' : 'outline'"
          :size="compact ? 'icon-sm' : 'sm'"
          class="shrink-0 text-xs"
          :aria-label="returnLabel"
          :aria-describedby="`brainstorming-origin-${reference.id}`"
          :title="returnLabel"
          :disabled="pending || !available"
          @click="request('return')"
          ><Loader2 v-if="pending" class="size-3.5 animate-spin" /><ArrowLeft
            v-else
            class="size-3.5"
          /><span :class="compact ? 'sr-only' : ''">{{
            t("brainstormingExplorations.return")
          }}</span></Button
        >
        <p v-if="error && !compact" role="alert" class="text-xs text-destructive">
          {{ t("brainstormingExplorations.error") }}
        </p>
      </div>
    </PopoverAnchor>
    <PopoverContent
      v-if="compact"
      :aria-label="t('brainstormingExplorations.context')"
      side="bottom"
      align="start"
      :side-offset="8"
      class="w-64 p-3 text-xs text-destructive"
      @open-auto-focus.prevent
      @close-auto-focus.prevent
    >
      <p role="alert">{{ t("brainstormingExplorations.error") }}</p>
    </PopoverContent>
  </Popover>
</template>
