<script setup lang="ts">
import type { ReferenceOverview } from "./referenceTypes";

defineProps<{ overview: ReferenceOverview }>();
</script>

<template>
  <div class="min-w-0 space-y-2 text-xs">
    <p class="break-words font-medium">{{ overview.name }}</p>
    <dl class="space-y-2">
      <div v-for="field in overview.fields" :key="field.key">
        <dt class="text-muted-foreground">
          {{ $t(`brainstormingReferences.fields.${field.key}`) }}
        </dt>
        <dd class="whitespace-pre-wrap break-words">
          {{
            field.key === "is_main"
              ? $t(`brainstormingReferences.${field.value === "true" ? "yes" : "no"}`)
              : field.value
          }}
          <span v-if="field.truncated" class="text-muted-foreground">{{
            $t("brainstormingReferences.excerpt")
          }}</span>
        </dd>
      </div>
    </dl>
  </div>
</template>
