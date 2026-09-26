<script setup lang="ts">
import { Lock } from "@lucide/vue";
import LiveLink from "@components/navigation/LiveLink.vue";

/**
 * The workspace is read-only: its owner's account is over its plan's limits.
 * The owner reads which limits and what to do; everyone else who could edit
 * reads whom to ask, and nothing about the plan.
 */
export type ReadOnlyNotice =
  | { owner: true; reasons: string[]; planPath: string | null }
  | { owner: false; ownerName: string };

const { notice } = defineProps<{ notice: ReadOnlyNotice }>();

const knownReasons = new Set([
  "workspaces_per_user",
  "projects_per_workspace",
  "items_per_project",
  "storage_bytes_per_workspace",
  "editors_per_account",
]);
</script>

<template>
  <div
    role="status"
    data-testid="read-only-banner"
    class="flex shrink-0 items-start gap-2.5 border-b border-warning/30 bg-warning/10 px-4 py-2.5 text-sm"
  >
    <Lock class="mt-0.5 size-4 shrink-0 text-warning" aria-hidden="true" />
    <div class="min-w-0 space-y-1">
      <p class="font-medium text-foreground">{{ $t("layout.read_only.title") }}</p>

      <template v-if="notice.owner">
        <p class="text-muted-foreground">{{ $t("layout.read_only.owner_intro") }}</p>
        <ul class="list-disc pl-5 text-muted-foreground">
          <template v-for="reason in notice.reasons" :key="reason">
            <li v-if="knownReasons.has(reason)">{{ $t(`layout.read_only.reasons.${reason}`) }}</li>
          </template>
        </ul>
        <p class="text-muted-foreground">
          {{ $t("layout.read_only.owner_action") }}
          <LiveLink
            v-if="notice.planPath"
            :to="notice.planPath"
            class="ml-1 font-medium text-foreground underline underline-offset-2"
            data-testid="read-only-banner-plan-link"
          >
            {{ $t("layout.read_only.view_plans") }}
          </LiveLink>
        </p>
      </template>

      <p v-else class="text-muted-foreground">
        {{ $t("layout.read_only.member", { owner: notice.ownerName }) }}
      </p>
    </div>
  </div>
</template>
