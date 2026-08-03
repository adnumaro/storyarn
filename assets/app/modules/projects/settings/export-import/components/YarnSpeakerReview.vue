<script setup lang="ts">
import { AlertTriangle, ArrowLeftRight, CheckCircle, Eye } from "@lucide/vue";
import { RadioGroup, RadioGroupItem } from "@components/ui/radio-group";
import { useI18n } from "vue-i18n";
import type { YarnImportReviewApi } from "@modules/projects/settings/export-import/composables/useYarnImportReview";
import type {
  SpeakerActionOption,
  YarnSpeakerAction,
  YarnSpeakerConfidence,
} from "@modules/projects/settings/export-import/types";

/**
 * Presentational half of the Yarn prefix review. Every decision, count and
 * blocking state comes from `useYarnImportReview`; nothing is derived here.
 */
const { review } = defineProps<{ review: YarnImportReviewApi }>();

const { t } = useI18n();

const REVIEW_REASON_KEYS = new Set([
  "literal_character_name",
  "repeated_scoped_presentation_channel",
  "single_adjacent_transposition_with_dominant_frequency",
  "dynamic_speaker_expression",
  "same_nfkc_casefold",
]);

function occurrencesLabel(count: number) {
  return t("project_settings.import.review_occurrences", { count }, count);
}

function reasonLabel(reason: string) {
  const key = REVIEW_REASON_KEYS.has(reason) ? reason : "unspecified";
  return t(`project_settings.import.review_evidence.${key}`);
}

function confidenceLabel(confidence: YarnSpeakerConfidence) {
  return t(`project_settings.import.review_confidence.${confidence}`);
}

function actionOptionClasses(speaker: string, option: SpeakerActionOption) {
  const selected = review.selectedActionValue(speaker) === option.value;
  const selectedClasses = {
    primary: "border-primary/45 bg-primary/5",
    warning: "border-amber-500/45 bg-amber-500/5",
    info: "border-sky-500/45 bg-sky-500/5",
  };

  return [
    "flex cursor-pointer items-start gap-2.5 rounded-lg border p-3 transition-colors",
    selected ? selectedClasses[option.accent] : "border-border bg-background hover:bg-muted/40",
  ];
}

function actionTestId(action: YarnSpeakerAction) {
  return `yarn-import-action-${action.replaceAll("_", "-")}`;
}
</script>

<template>
  <section
    v-if="review.review.value"
    id="yarn-import-review"
    class="space-y-3 rounded-xl border border-border bg-muted/25 p-4"
  >
    <div class="space-y-1">
      <h4 class="text-sm font-semibold">
        {{ $t("project_settings.import.review_title") }}
      </h4>
      <p class="text-xs text-muted-foreground">
        {{ $t("project_settings.import.review_description") }}
      </p>
    </div>

    <dl class="grid grid-cols-2 gap-2 text-center lg:grid-cols-4">
      <div class="rounded-lg border border-border bg-background px-2 py-2">
        <dt class="text-[11px] text-muted-foreground">
          {{ $t("project_settings.import.review_variables") }}
        </dt>
        <dd data-testid="yarn-import-variable-count" class="text-lg font-semibold tabular-nums">
          {{ review.review.value.variable_count }}
        </dd>
      </div>
      <div class="rounded-lg border border-border bg-background px-2 py-2">
        <dt class="text-[11px] text-muted-foreground">
          {{ $t("project_settings.import.review_sheet_speakers") }}
        </dt>
        <dd
          data-testid="yarn-import-sheet-speaker-count"
          class="text-lg font-semibold tabular-nums"
        >
          {{ review.sheetSpeakerCount.value ?? "—" }}
        </dd>
      </div>
      <div class="rounded-lg border border-border bg-background px-2 py-2">
        <dt class="text-[11px] text-muted-foreground">
          {{ $t("project_settings.import.review_preserved_channels") }}
        </dt>
        <dd
          data-testid="yarn-import-preserved-channel-count"
          class="text-lg font-semibold tabular-nums"
        >
          {{ review.preservedChannelCount.value ?? "—" }}
        </dd>
      </div>
      <div class="rounded-lg border border-border bg-background px-2 py-2">
        <dt class="text-[11px] text-muted-foreground">
          {{ $t("project_settings.import.review_mapped_aliases") }}
        </dt>
        <dd data-testid="yarn-import-mapped-alias-count" class="text-lg font-semibold tabular-nums">
          {{ review.mappedAliasCount.value }}
        </dd>
      </div>
    </dl>

    <details
      v-if="review.review.value.speaker_decision_count > 0"
      open
      class="group rounded-lg border border-border"
    >
      <summary
        class="cursor-pointer select-none px-3 py-2 text-sm font-medium transition-colors hover:bg-muted/60"
      >
        {{ $t("project_settings.import.review_speaker_decisions") }}
        <span class="ml-1 text-xs font-normal text-muted-foreground">
          ({{ review.review.value.speaker_decision_count }})
        </span>
      </summary>
      <ul class="max-h-72 divide-y divide-border overflow-y-auto border-t border-border">
        <li
          v-for="(decision, decisionIndex) in review.decisions.value"
          :key="decision.speaker"
          :data-decision="review.selectedAction(decision.speaker) ?? 'missing'"
          :data-suggested-action="decision.suggested_action"
          data-testid="yarn-import-speaker-decision"
          class="space-y-3 px-3 py-3"
        >
          <div class="flex flex-wrap items-center justify-between gap-2">
            <div class="min-w-0">
              <p
                :id="`yarn-speaker-${decisionIndex}-label`"
                class="break-words text-sm font-semibold"
              >
                {{ decision.speaker }}
              </p>
              <p class="text-xs text-muted-foreground">
                {{ occurrencesLabel(decision.occurrences) }}
              </p>
            </div>
            <span
              data-testid="yarn-import-speaker-confidence"
              class="rounded-full border border-border bg-muted px-2 py-0.5 text-[11px] font-medium text-muted-foreground"
            >
              {{
                $t("project_settings.import.review_confidence_label", {
                  confidence: confidenceLabel(decision.confidence),
                })
              }}
            </span>
          </div>
          <ul class="space-y-1 text-xs text-muted-foreground">
            <li v-for="reason in decision.reasons" :key="reason" class="flex items-start gap-1.5">
              <span aria-hidden="true" class="mt-1.5 size-1 shrink-0 rounded-full bg-current" />
              <span>{{ reasonLabel(reason) }}</span>
            </li>
          </ul>
          <RadioGroup
            :model-value="review.selectedActionValue(decision.speaker)"
            :aria-labelledby="`yarn-speaker-${decisionIndex}-label`"
            class="grid gap-2 lg:grid-cols-3"
            @update:model-value="review.setAction(decision.speaker, $event)"
          >
            <label
              v-for="(option, optionIndex) in review.actionOptions(decision)"
              :key="option.value"
              :for="`yarn-speaker-${decisionIndex}-action-${optionIndex}`"
              :class="actionOptionClasses(decision.speaker, option)"
            >
              <RadioGroupItem
                :id="`yarn-speaker-${decisionIndex}-action-${optionIndex}`"
                :value="option.value"
                :data-testid="actionTestId(option.action)"
                :data-target-speaker="option.targetSpeaker"
                class="mt-0.5"
              />
              <span class="min-w-0">
                <span class="flex flex-wrap items-center gap-1.5 text-sm font-medium">
                  {{ $t(option.labelKey, { target: option.targetSpeaker }) }}
                  <span
                    v-if="option.suggested"
                    class="rounded-full bg-primary/10 px-1.5 py-0.5 text-[10px] font-semibold text-primary"
                  >
                    {{ $t("project_settings.import.review_suggested") }}
                  </span>
                </span>
                <span class="mt-0.5 block text-xs text-muted-foreground">
                  {{ $t(option.descriptionKey, { target: option.targetSpeaker }) }}
                </span>
              </span>
            </label>
          </RadioGroup>
        </li>
      </ul>
      <p
        v-if="review.review.value.speaker_decisions_truncated"
        data-testid="yarn-import-speaker-review-truncated"
        class="border-t border-border px-3 py-2 text-xs text-muted-foreground"
      >
        {{
          $t("project_settings.import.review_truncated_blocking", {
            shown: review.decisions.value.length,
            total: review.review.value.speaker_decision_count,
          })
        }}
      </p>
    </details>

    <div
      v-if="review.review.value.possible_speaker_alias_count > 0"
      id="yarn-import-alias-review"
      class="space-y-2 rounded-lg border border-amber-500/30 bg-amber-500/5 p-3"
    >
      <div>
        <h5 class="text-sm font-medium">
          {{ $t("project_settings.import.review_aliases_title") }}
          <span class="ml-1 text-xs font-normal text-muted-foreground">
            ({{ review.review.value.possible_speaker_alias_count }})
          </span>
        </h5>
        <p class="text-xs text-muted-foreground">
          {{ $t("project_settings.import.review_aliases_description") }}
        </p>
      </div>
      <ul class="max-h-56 space-y-2 overflow-y-auto">
        <li
          v-for="alias in review.aliases.value"
          :key="`${alias.left}:${alias.right}`"
          data-testid="yarn-import-speaker-alias"
          class="rounded-md border border-border bg-background px-3 py-2"
        >
          <div class="flex flex-wrap items-center gap-x-2 gap-y-1 text-sm">
            <span class="font-medium">{{ alias.left }}</span>
            <span class="text-xs text-muted-foreground">
              {{ occurrencesLabel(alias.left_occurrences) }}
            </span>
            <ArrowLeftRight aria-hidden="true" class="size-3.5 text-muted-foreground" />
            <span class="font-medium">{{ alias.right }}</span>
            <span class="text-xs text-muted-foreground">
              {{ occurrencesLabel(alias.right_occurrences) }}
            </span>
          </div>
          <p class="mt-1 text-xs text-muted-foreground">
            {{ reasonLabel(alias.evidence) }}
          </p>
          <p
            data-testid="yarn-import-alias-mapping-status"
            :data-mapping-enabled="review.aliasCanMap(alias)"
            class="mt-2 text-xs font-medium"
            :class="
              review.aliasCanMap(alias) ? 'text-sky-700 dark:text-sky-300' : 'text-muted-foreground'
            "
          >
            {{
              review.aliasCanMap(alias)
                ? $t("project_settings.import.review_alias_mapping_available", {
                    alias: alias.less_frequent,
                    target: alias.more_frequent,
                  })
                : $t("project_settings.import.review_alias_mapping_requires_target", {
                    target: alias.more_frequent,
                  })
            }}
          </p>
        </li>
      </ul>
      <p
        v-if="review.review.value.possible_speaker_aliases_truncated"
        data-testid="yarn-import-alias-review-truncated"
        class="text-xs text-muted-foreground"
      >
        {{
          $t("project_settings.import.review_truncated_blocking", {
            shown: review.aliases.value.length,
            total: review.review.value.possible_speaker_alias_count,
          })
        }}
      </p>
    </div>

    <div
      v-if="!review.structurallyComplete.value"
      data-testid="yarn-import-review-incomplete"
      class="flex items-start gap-2 rounded-lg border border-destructive/30 bg-destructive/5 p-3 text-sm text-destructive"
    >
      <AlertTriangle aria-hidden="true" class="mt-0.5 size-4 shrink-0" />
      <span>
        {{
          review.isTruncated.value
            ? $t("project_settings.import.review_incomplete_truncated")
            : $t("project_settings.import.review_incomplete")
        }}
      </span>
    </div>

    <div
      v-else-if="!review.allDecisionsSelected.value"
      data-testid="yarn-import-review-undecided"
      class="flex items-start gap-2 rounded-lg border border-destructive/30 bg-destructive/5 p-3 text-sm text-destructive"
    >
      <AlertTriangle aria-hidden="true" class="mt-0.5 size-4 shrink-0" />
      <span>{{ $t("project_settings.import.review_undecided") }}</span>
    </div>

    <div
      v-else-if="review.hasCompatibilityErrors.value"
      data-testid="yarn-import-review-compatibility-errors"
      class="flex items-start gap-2 rounded-lg border border-destructive/30 bg-destructive/5 p-3 text-sm text-destructive"
    >
      <AlertTriangle aria-hidden="true" class="mt-0.5 size-4 shrink-0" />
      <span>
        {{
          review.issueSummaryMalformed.value
            ? $t("project_settings.import.compatibility_summary_invalid")
            : $t("project_settings.import.compatibility_errors_blocking")
        }}
      </span>
    </div>

    <div
      v-else-if="review.matchesResolution.value"
      data-testid="yarn-import-review-validated"
      class="flex items-start gap-2 rounded-lg border border-emerald-500/30 bg-emerald-500/5 p-3 text-sm text-emerald-700 dark:text-emerald-300"
    >
      <CheckCircle aria-hidden="true" class="mt-0.5 size-4 shrink-0" />
      <span>{{ $t("project_settings.import.review_validated") }}</span>
    </div>

    <div
      v-else
      data-testid="yarn-import-review-needs-validation"
      class="flex items-start gap-2 rounded-lg border border-sky-500/30 bg-sky-500/5 p-3 text-sm text-sky-700 dark:text-sky-300"
    >
      <Eye aria-hidden="true" class="mt-0.5 size-4 shrink-0" />
      <span>{{ $t("project_settings.import.review_needs_validation") }}</span>
    </div>
  </section>

  <div
    v-else
    data-testid="yarn-import-review-missing"
    class="flex items-start gap-2 rounded-lg border border-destructive/30 bg-destructive/5 p-3 text-sm text-destructive"
  >
    <AlertTriangle aria-hidden="true" class="mt-0.5 size-4 shrink-0" />
    <span>{{ $t("project_settings.import.review_missing") }}</span>
  </div>
</template>
