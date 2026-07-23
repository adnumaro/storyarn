<script setup lang="ts">
import { AlertTriangle, Braces, ChevronDown, CircleCheck, Database } from "lucide-vue-next";
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { Badge } from "@components/ui/badge";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@components/ui/collapsible";

export interface ContextDisclosureData {
  version: string;
  context_version: string;
  scope: string;
  serialized_bytes: number;
  token_count: number | null;
  included_count: number;
  excluded_count: number;
  truncated: boolean;
  warnings: string[];
}

const { disclosure } = defineProps<{
  disclosure: ContextDisclosureData;
}>();

const { locale, t, te } = useI18n();

const warningLabels = computed(() =>
  disclosure.warnings.map((warning) => {
    const key = `integrations.context_disclosure.warnings.${warning}`;
    return te(key) ? t(key) : warning.replaceAll("_", " ");
  }),
);

const formattedBytes = computed(() => {
  const bytes = disclosure.serialized_bytes;
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1_048_576) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1_048_576).toFixed(1)} MB`;
});

const formattedTokens = computed(() =>
  disclosure.token_count === null
    ? t("integrations.context_disclosure.not_available")
    : new Intl.NumberFormat(locale.value).format(disclosure.token_count),
);

const scopeLabel = computed(() => {
  const key = `integrations.context_disclosure.scopes.${disclosure.scope}`;
  return te(key) ? t(key) : disclosure.scope.replaceAll("_", " ");
});
</script>

<template>
  <Collapsible
    class="group overflow-hidden rounded-xl border border-border/70 bg-card shadow-sm"
    data-testid="ai-context-disclosure"
  >
    <CollapsibleTrigger
      data-testid="ai-context-disclosure-trigger"
      class="flex w-full items-center gap-3 px-4 py-3 text-left transition-colors hover:bg-muted/40"
    >
      <span
        class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary"
      >
        <Database class="size-4" />
      </span>

      <span class="min-w-0 flex-1">
        <span class="flex flex-wrap items-center gap-2">
          <span class="text-sm font-semibold">
            {{ $t("integrations.context_disclosure.title") }}
          </span>
          <Badge v-if="disclosure.truncated" variant="outline" class="gap-1 text-warning">
            <AlertTriangle class="size-3" />
            {{ $t("integrations.context_disclosure.truncated") }}
          </Badge>
          <Badge v-else variant="outline" class="gap-1 text-success">
            <CircleCheck class="size-3" />
            {{ $t("integrations.context_disclosure.complete") }}
          </Badge>
        </span>
        <span class="mt-0.5 block text-xs text-muted-foreground">
          {{
            $t("integrations.context_disclosure.summary", {
              included: disclosure.included_count,
              size: formattedBytes,
            })
          }}
        </span>
      </span>

      <ChevronDown
        class="size-4 shrink-0 text-muted-foreground transition-transform duration-200 group-data-[state=open]:rotate-180"
      />
    </CollapsibleTrigger>

    <CollapsibleContent>
      <div class="border-t border-border/60 px-4 py-3">
        <dl class="grid grid-cols-2 gap-x-6 gap-y-3 text-xs sm:grid-cols-4">
          <div>
            <dt class="text-muted-foreground">
              {{ $t("integrations.context_disclosure.scope") }}
            </dt>
            <dd class="mt-0.5 font-medium">{{ scopeLabel }}</dd>
          </div>
          <div>
            <dt class="text-muted-foreground">
              {{ $t("integrations.context_disclosure.included") }}
            </dt>
            <dd class="mt-0.5 font-medium">{{ disclosure.included_count }}</dd>
          </div>
          <div>
            <dt class="text-muted-foreground">
              {{ $t("integrations.context_disclosure.excluded") }}
            </dt>
            <dd class="mt-0.5 font-medium">{{ disclosure.excluded_count }}</dd>
          </div>
          <div>
            <dt class="text-muted-foreground">
              {{ $t("integrations.context_disclosure.tokens") }}
            </dt>
            <dd class="mt-0.5 font-medium">{{ formattedTokens }}</dd>
          </div>
        </dl>

        <div
          v-if="warningLabels.length > 0"
          data-testid="ai-context-disclosure-warnings"
          class="mt-3 rounded-lg border border-warning/25 bg-warning/5 px-3 py-2"
        >
          <p class="flex items-center gap-1.5 text-xs font-medium text-warning">
            <AlertTriangle class="size-3.5" />
            {{ $t("integrations.context_disclosure.warning_title") }}
          </p>
          <ul class="mt-1 space-y-1 pl-5 text-xs text-muted-foreground">
            <li v-for="warning in warningLabels" :key="warning" class="list-disc">
              {{ warning }}
            </li>
          </ul>
        </div>

        <p class="mt-3 flex items-start gap-1.5 text-[11px] leading-4 text-muted-foreground">
          <Braces class="mt-0.5 size-3 shrink-0" />
          {{ $t("integrations.context_disclosure.explanation") }}
        </p>
      </div>
    </CollapsibleContent>
  </Collapsible>
</template>
