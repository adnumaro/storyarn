<script setup lang="ts">
import { CheckCircle2, CircleAlert, ExternalLink, LoaderCircle } from "@lucide/vue";
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import PasswordInput from "@components/forms/PasswordInput.vue";
import {
  SettingsMeterRow,
  SettingsPage,
  SettingsRow,
  SettingsSection,
  type SettingsMeterStatus,
} from "@components/settings";
import { Badge } from "@components/ui/badge";
import { Button } from "@components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select";
import { useLive } from "@shared/composables/useLive";

interface ProviderUsage {
  characterCount: number;
  characterLimit: number;
}

const {
  providerApiEndpoint = "https://api-free.deepl.com",
  hasApiKey = false,
  providerUsage = null,
} = defineProps<{
  providerApiEndpoint?: string;
  hasApiKey?: boolean;
  providerUsage?: ProviderUsage | null;
}>();

const live = useLive();
const { locale, t } = useI18n();

const providerApiKey = ref("");
const providerEndpoint = ref(providerApiEndpoint);
const effectiveUsage = ref<ProviderUsage | null>(providerUsage);
const saving = ref(false);
const testing = ref(false);
const connectionState = ref<"idle" | "success" | "error">("idle");
const connectionError = ref("");

watch(
  () => providerApiEndpoint,
  (v) => {
    providerEndpoint.value = v;
  },
);

watch(
  () => providerUsage,
  (value) => {
    effectiveUsage.value = value;
  },
);

function saveProviderConfig(): void {
  saving.value = true;
  connectionState.value = "idle";
  live.pushEvent(
    "save_provider_config",
    {
      provider: {
        api_key_encrypted: providerApiKey.value,
        api_endpoint: providerEndpoint.value,
      },
    },
    (response: { ok?: boolean; errors?: Record<string, string> }) => {
      saving.value = false;
      if (response?.ok) {
        providerApiKey.value = "";
        effectiveUsage.value = null;
      } else {
        connectionState.value = "error";
        connectionError.value = response?.errors
          ? Object.values(response.errors).join(" · ")
          : "save_failed";
      }
    },
    () => {
      saving.value = false;
      connectionState.value = "error";
      connectionError.value = "save_failed";
    },
  );
}

function testProviderConnection(): void {
  testing.value = true;
  connectionState.value = "idle";
  connectionError.value = "";

  live.pushEvent(
    "test_provider_connection",
    {},
    (response: { ok?: boolean; error?: string; usage?: ProviderUsage }) => {
      testing.value = false;
      if (response?.ok) {
        connectionState.value = "success";
        effectiveUsage.value = response.usage ?? null;
      } else {
        connectionState.value = "error";
        connectionError.value = response?.error || "connection_failed";
      }
    },
    () => {
      testing.value = false;
      connectionState.value = "error";
      connectionError.value = "connection_failed";
    },
  );
}

function formatCount(value: number): string {
  return new Intl.NumberFormat(locale.value).format(value);
}

const usagePercent = computed<number | null>(() => {
  if (!effectiveUsage.value || effectiveUsage.value.characterLimit <= 0) return null;

  return Math.min(
    100,
    Math.round((effectiveUsage.value.characterCount / effectiveUsage.value.characterLimit) * 100),
  );
});

const usageStatus = computed<SettingsMeterStatus>(() => {
  if (!effectiveUsage.value || effectiveUsage.value.characterLimit <= 0) return "unknown";

  const ratio = effectiveUsage.value.characterCount / effectiveUsage.value.characterLimit;
  if (ratio >= 1) return "reached";
  if (ratio >= 0.8) return "warning";

  return "available";
});
</script>

<template>
  <SettingsPage :title="t('project_settings.localization.page_title')">
    <SettingsSection
      :title="t('project_settings.localization.provider_section')"
      :hint="t('project_settings.localization.provider_hint')"
    >
      <template #title-extra>
        <Badge :variant="hasApiKey ? 'secondary' : 'outline'">
          {{
            hasApiKey
              ? t("project_settings.localization.configured")
              : t("project_settings.localization.not_configured")
          }}
        </Badge>
      </template>

      <form @submit.prevent="saveProviderConfig">
        <SettingsRow
          :label="t('project_settings.localization.api_key')"
          :hint="
            hasApiKey
              ? t('project_settings.localization.api_key_preserved')
              : t('project_settings.localization.api_key_required')
          "
          html-for="api-key"
          control="input"
        >
          <PasswordInput
            id="api-key"
            v-model="providerApiKey"
            :placeholder="hasApiKey ? '••••••••' : ''"
            autocomplete="off"
          />
        </SettingsRow>

        <SettingsRow
          :label="t('project_settings.localization.api_tier')"
          :hint="t('project_settings.localization.tier_help')"
        >
          <Select v-model="providerEndpoint">
            <SelectTrigger id="api-tier" class="w-[220px] max-w-full">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="https://api-free.deepl.com">
                {{ t("project_settings.localization.tier_free") }}
              </SelectItem>
              <SelectItem value="https://api.deepl.com">
                {{ t("project_settings.localization.tier_pro") }}
              </SelectItem>
            </SelectContent>
          </Select>
        </SettingsRow>

        <SettingsRow :label="t('project_settings.localization.connection_row')">
          <template #hint>
            <a
              href="https://developers.deepl.com/docs/getting-started/auth"
              target="_blank"
              rel="noreferrer"
              class="inline-flex items-center gap-1 underline underline-offset-2"
            >
              {{ t("project_settings.localization.api_key_help") }}
              <ExternalLink class="size-3" aria-hidden="true" />
            </a>
          </template>
          <Button
            v-if="hasApiKey"
            type="button"
            data-testid="localization-test-connection"
            variant="outline"
            size="sm"
            :disabled="testing || saving"
            @click="testProviderConnection"
          >
            <LoaderCircle v-if="testing" class="size-4 animate-spin" aria-hidden="true" />
            {{ t("project_settings.localization.test_connection") }}
          </Button>
          <Button
            type="submit"
            size="sm"
            data-testid="localization-save-provider"
            :disabled="saving || testing"
          >
            <LoaderCircle v-if="saving" class="size-4 animate-spin" aria-hidden="true" />
            {{ t("project_settings.localization.save") }}
          </Button>
        </SettingsRow>

        <p
          v-if="connectionState !== 'idle'"
          role="status"
          data-testid="localization-connection-status"
          :class="[
            'mx-4 mb-3.5 flex items-center gap-2 rounded-lg border px-3 py-2 text-sm',
            connectionState === 'success'
              ? 'border-emerald-500/30 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300'
              : 'border-destructive/30 bg-destructive/10 text-destructive',
          ]"
        >
          <CheckCircle2 v-if="connectionState === 'success'" class="size-4" aria-hidden="true" />
          <CircleAlert v-else class="size-4" aria-hidden="true" />
          <span>
            {{
              connectionState === "success"
                ? t("project_settings.localization.connection_success")
                : t("project_settings.localization.connection_error", { error: connectionError })
            }}
          </span>
        </p>
      </form>
    </SettingsSection>

    <SettingsSection
      v-if="effectiveUsage"
      :title="t('project_settings.localization.usage_section')"
      :hint="t('project_settings.localization.usage_description')"
    >
      <SettingsMeterRow
        data-testid="localization-usage-meter"
        :label="t('project_settings.localization.usage_row')"
        :hint="t('project_settings.localization.usage_row_hint')"
        :used="formatCount(effectiveUsage.characterCount)"
        :limit="formatCount(effectiveUsage.characterLimit)"
        :percent="usagePercent"
        :status="usageStatus"
        :status-label="t(`project_settings.usage_limits.meter_status.${usageStatus}`)"
      />
    </SettingsSection>
  </SettingsPage>
</template>
