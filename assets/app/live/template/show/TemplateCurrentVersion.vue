<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { Badge } from "@components/ui/badge";
import { formatTemplateDate } from "../templateFormat";
import type { TemplateCurrentVersion } from "../types";

const { version } = defineProps<{ version: TemplateCurrentVersion | null }>();
const { t, te, locale } = useI18n();
// A snapshot counts what it holds by record name; one it does not name keeps that name.
const countLabel = (key: string) =>
  te(`templates.show.counts.${key}`) ? t(`templates.show.counts.${key}`) : key;
const published = computed(() =>
  version ? formatTemplateDate(version.publishedAt, locale.value) : "",
);
const previewGroups = computed(() =>
  version
    ? (["sheets", "flows", "scenes"] as const)
        .map((key) => ({ key, items: version.preview[key] }))
        .filter((group) => group.items.length)
    : [],
);
</script>
<template>
  <section
    id="template-version-panel"
    class="flex flex-col gap-5 rounded-xl border border-border bg-card p-5"
  >
    <div class="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
      <div>
        <h2 class="text-base font-semibold">{{ $t("templates.show.current_version") }}</h2>
        <p class="mt-1 text-sm text-muted-foreground">
          {{
            version
              ? $t("templates.version", { version: version.versionNumber })
              : $t("templates.no_version")
          }}
        </p>
      </div>
      <p v-if="published" class="text-sm text-muted-foreground">
        {{ $t("templates.show.published_on", { date: published }) }}
      </p>
    </div>

    <div v-if="version?.entityCounts.length" class="flex flex-wrap gap-2">
      <Badge v-for="[key, count] in version.entityCounts" :key="key" variant="secondary">
        {{ countLabel(key) }} <span class="font-semibold">{{ count }}</span>
      </Badge>
    </div>

    <p v-if="version?.notes" class="text-sm text-muted-foreground">{{ version.notes }}</p>

    <div
      v-if="previewGroups.length"
      id="template-current-preview"
      class="grid gap-3 md:grid-cols-3"
    >
      <div
        v-for="group in previewGroups"
        :key="group.key"
        class="rounded-lg border border-border bg-muted/40 p-3"
      >
        <p class="text-xs font-semibold tracking-wider text-muted-foreground uppercase">
          {{ $t(`templates.show.preview.${group.key}`) }}
        </p>
        <ul class="mt-2 space-y-1 text-sm">
          <li v-for="item in group.items" :key="item" class="truncate">{{ item }}</li>
        </ul>
      </div>
    </div>
  </section>
</template>
