<script setup lang="ts">
import {
  AudioLines,
  Bot,
  CircleAlert,
  Clock3,
  Image,
  Loader2,
  PenLine,
  Sparkles,
  Trash2,
} from "lucide-vue-next";
import { computed, ref, watch, type Component } from "vue";
import { useI18n } from "vue-i18n";
import { Button } from "@components/ui/button";
import PreferenceCombobox, { type PreferenceComboboxOption } from "./PreferenceCombobox.vue";

export interface PreferenceOptionData {
  integration_id: number;
  assignment_id: number;
  provider: string;
  provider_name: string;
  model: string;
  capabilities: string[];
  implementation_status: "executable" | "configuration_only";
  payer: "personal_provider_account";
}

export interface PersonalPreferenceData {
  id: number;
  slot: string;
  integration_id: number;
  provider: string;
  provider_name: string;
  model: string;
  implementation_status: "executable" | "configuration_only" | null;
  status:
    | "ready"
    | "configured"
    | "workspace_policy_denied"
    | "provider_disconnected"
    | "assignment_required"
    | "model_unavailable"
    | "model_deprecated"
    | "capability_mismatch";
  payer: "personal_provider_account";
}

export interface PreferenceSlotData {
  slot: "general_assistant" | "writing_assistant" | "illustrator" | "voice";
  kind: "role";
  required_capabilities: string[];
  preference: PersonalPreferenceData | null;
  options: PreferenceOptionData[];
}

const {
  slotData,
  pending = false,
  disabled = false,
} = defineProps<{
  slotData: PreferenceSlotData;
  pending?: boolean;
  disabled?: boolean;
}>();

const emit = defineEmits<{
  save: [payload: { slot: string; integration_id: number; model: string }];
  remove: [slot: string];
}>();

const { t } = useI18n();
const selectedIntegrationId = ref("");
const selectedModel = ref("");

const iconMap: Record<PreferenceSlotData["slot"], Component> = {
  general_assistant: Bot,
  writing_assistant: PenLine,
  illustrator: Image,
  voice: AudioLines,
};

const slotIcon = computed(() => iconMap[slotData.slot]);

const providers = computed(() => {
  const unique = new Map<number, PreferenceOptionData>();

  for (const option of slotData.options) {
    if (!unique.has(option.integration_id)) unique.set(option.integration_id, option);
  }

  return [...unique.values()];
});

const providerOptions = computed<PreferenceComboboxOption[]>(() =>
  providers.value.map((provider) => ({
    value: String(provider.integration_id),
    label: provider.provider_name,
    searchText: provider.provider,
  })),
);

const models = computed(() =>
  slotData.options.filter(
    (option) => String(option.integration_id) === selectedIntegrationId.value,
  ),
);

const modelOptions = computed<PreferenceComboboxOption[]>(() =>
  models.value.map((option) => ({
    value: option.model,
    label: option.model,
    searchText: option.capabilities.join(" "),
    badge:
      option.implementation_status === "configuration_only"
        ? t("integrations.team.configuration_only.badge")
        : undefined,
  })),
);

const selectedOption = computed(() =>
  models.value.find((option) => option.model === selectedModel.value),
);

const canSave = computed(() => {
  if (pending || disabled || !selectedOption.value) return false;

  return (
    !slotData.preference ||
    slotData.preference.integration_id !== selectedOption.value.integration_id ||
    slotData.preference.model !== selectedOption.value.model
  );
});

const statusTone = computed(() => {
  if (!slotData.preference) return "bg-muted text-muted-foreground";
  if (slotData.preference.status === "ready") {
    return "bg-emerald-500/10 text-emerald-700 dark:text-emerald-300";
  }
  if (slotData.preference.status === "configured") {
    return "bg-sky-500/10 text-sky-700 dark:text-sky-300";
  }
  return "bg-amber-500/10 text-amber-700 dark:text-amber-300";
});

const preferenceNeedsRepair = computed(
  () => slotData.preference && !["ready", "configured"].includes(slotData.preference.status),
);

function resetSelection(): void {
  const current = slotData.preference;
  const matching =
    current &&
    slotData.options.find(
      (option) =>
        option.integration_id === current.integration_id && option.model === current.model,
    );

  selectedIntegrationId.value = matching ? String(matching.integration_id) : "";
  selectedModel.value = matching?.model ?? "";
}

function chooseProvider(value: string): void {
  selectedIntegrationId.value = value;
  const providerModels = slotData.options.filter(
    (option) => String(option.integration_id) === value,
  );
  selectedModel.value = providerModels.length === 1 ? providerModels[0]!.model : "";
}

function chooseModel(value: string): void {
  selectedModel.value = value;
}

function save(): void {
  const option = selectedOption.value;
  if (!option) return;

  emit("save", {
    slot: slotData.slot,
    integration_id: option.integration_id,
    model: option.model,
  });
}

watch(() => slotData, resetSelection, { deep: true, immediate: true });
</script>

<template>
  <article
    class="overflow-hidden rounded-xl border border-border/70 bg-card shadow-sm"
    :data-preference-slot="slotData.slot"
    :data-preference-status="slotData.preference?.status ?? 'unconfigured'"
    :data-policy-disabled="disabled"
    :aria-busy="pending"
    :aria-labelledby="`preference-title-${slotData.slot}`"
  >
    <header class="flex flex-col gap-4 p-5 sm:flex-row sm:items-start sm:justify-between">
      <div class="flex min-w-0 items-start gap-3">
        <div
          class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary"
        >
          <component :is="slotIcon" class="size-4.5" aria-hidden="true" />
        </div>
        <div class="min-w-0">
          <h2
            :id="`preference-title-${slotData.slot}`"
            class="text-sm font-semibold text-foreground"
          >
            {{ t(`integrations.team.slots.${slotData.slot}.title`) }}
          </h2>
          <p class="mt-1 text-xs leading-relaxed text-muted-foreground">
            {{ t(`integrations.team.slots.${slotData.slot}.description`) }}
          </p>
        </div>
      </div>

      <span
        class="w-fit shrink-0 rounded-full px-2.5 py-1 text-[11px] font-medium"
        :class="statusTone"
      >
        {{
          slotData.preference
            ? t(`integrations.team.status.${slotData.preference.status}`)
            : t("integrations.team.status.unconfigured")
        }}
      </span>
    </header>

    <div
      v-if="slotData.preference"
      class="mx-5 mb-4 flex items-start justify-between gap-4 rounded-lg border border-border/60 bg-muted/20 px-3 py-3"
    >
      <div class="min-w-0">
        <p class="truncate text-xs font-medium text-foreground">
          {{
            t("integrations.team.primary_summary", {
              provider: slotData.preference.provider_name,
              model: slotData.preference.model,
            })
          }}
        </p>
        <p
          v-if="slotData.preference.status !== 'configured'"
          class="mt-0.5 text-[11px] text-muted-foreground"
        >
          {{
            t("integrations.team.personal_billing", {
              provider: slotData.preference.provider_name,
            })
          }}
        </p>
        <p
          v-if="slotData.preference.status === 'configured'"
          data-configuration-only-preference
          class="mt-1.5 flex items-start gap-1.5 text-[11px] leading-relaxed text-sky-700 dark:text-sky-300"
        >
          <Clock3 class="mt-0.5 size-3 shrink-0" aria-hidden="true" />
          {{ t("integrations.team.configuration_only.saved_description") }}
        </p>
        <p
          v-else-if="preferenceNeedsRepair"
          class="mt-1.5 flex items-start gap-1.5 text-[11px] leading-relaxed text-amber-700 dark:text-amber-300"
        >
          <CircleAlert class="mt-0.5 size-3 shrink-0" aria-hidden="true" />
          {{ t(`integrations.team.repairs.${slotData.preference.status}`) }}
        </p>
      </div>
      <Button
        type="button"
        variant="ghost"
        size="icon-sm"
        :aria-label="
          t('integrations.team.remove_for_role', {
            role: t(`integrations.team.slots.${slotData.slot}.title`),
          })
        "
        :disabled="pending"
        @click="emit('remove', slotData.slot)"
      >
        <Trash2 class="size-3.5" aria-hidden="true" />
      </Button>
    </div>

    <div class="grid gap-4 border-t border-border/60 bg-muted/10 p-5 sm:grid-cols-2">
      <div class="space-y-1.5">
        <label :for="`preference-provider-${slotData.slot}`" class="text-xs font-medium">
          {{ t("integrations.team.provider") }}
        </label>
        <PreferenceCombobox
          :id="`preference-provider-${slotData.slot}`"
          :model-value="selectedIntegrationId"
          :options="providerOptions"
          :label="t('integrations.team.provider')"
          :placeholder="t('integrations.team.choose_provider')"
          :search-placeholder="t('common.search')"
          :empty-label="t('common.no_results')"
          :disabled="disabled || pending || providers.length === 0"
          @update:model-value="chooseProvider(String($event))"
        />
      </div>

      <div class="space-y-1.5">
        <label :for="`preference-model-${slotData.slot}`" class="text-xs font-medium">
          {{ t("integrations.team.primary_model") }}
        </label>
        <PreferenceCombobox
          :id="`preference-model-${slotData.slot}`"
          :model-value="selectedModel"
          :options="modelOptions"
          :label="t('integrations.team.primary_model')"
          :placeholder="t('integrations.team.choose_model')"
          :search-placeholder="t('common.search')"
          :empty-label="t('common.no_results')"
          :disabled="disabled || pending || !selectedIntegrationId || models.length === 0"
          :aria-describedby="
            selectedOption?.implementation_status === 'configuration_only'
              ? `configuration-only-help-${slotData.slot}`
              : undefined
          "
          @update:model-value="chooseModel(String($event))"
        />
      </div>

      <div class="flex flex-col gap-3 sm:col-span-2 sm:flex-row sm:items-center sm:justify-between">
        <p
          v-if="slotData.options.length === 0"
          class="text-xs leading-relaxed text-muted-foreground"
        >
          {{ t("integrations.team.no_compatible_options") }}
        </p>
        <div
          v-else-if="selectedOption?.implementation_status === 'configuration_only'"
          :id="`configuration-only-help-${slotData.slot}`"
          data-selected-implementation-status="configuration_only"
          role="status"
          aria-live="polite"
          class="flex max-w-xl items-start gap-2 text-xs leading-relaxed text-sky-700 dark:text-sky-300"
        >
          <Sparkles class="mt-0.5 size-3.5 shrink-0" aria-hidden="true" />
          <p>
            <span class="font-medium">
              {{ t("integrations.team.configuration_only.badge") }}.
            </span>
            {{ t("integrations.team.configuration_only.option_description") }}
          </p>
        </div>
        <p v-else-if="selectedOption" class="text-xs text-muted-foreground">
          {{
            t("integrations.team.personal_billing", {
              provider: selectedOption.provider_name,
            })
          }}
        </p>
        <p v-else class="text-xs text-muted-foreground">
          {{ t("integrations.team.selection_help") }}
        </p>

        <Button
          type="button"
          size="sm"
          class="shrink-0"
          :aria-label="
            t(
              slotData.preference
                ? 'integrations.team.update_for_role'
                : 'integrations.team.assign_for_role',
              {
                role: t(`integrations.team.slots.${slotData.slot}.title`),
              },
            )
          "
          :aria-describedby="
            selectedOption?.implementation_status === 'configuration_only'
              ? `configuration-only-help-${slotData.slot}`
              : undefined
          "
          :disabled="!canSave"
          @click="save"
        >
          <Loader2 v-if="pending" class="mr-1.5 size-3.5 animate-spin" aria-hidden="true" />
          {{ t(slotData.preference ? "integrations.team.update" : "integrations.team.assign") }}
        </Button>
      </div>
    </div>
  </article>
</template>
