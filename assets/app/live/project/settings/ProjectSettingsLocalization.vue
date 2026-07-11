<script setup lang="ts">
import {
  CheckCircle2,
  CircleAlert,
  ExternalLink,
  Gauge,
  KeyRound,
  LoaderCircle,
} from "lucide-vue-next";
import { computed, ref, watch } from "vue";
import PasswordInput from "@components/forms/PasswordInput.vue";
import { Button } from "@components/ui/button";
import { Label } from "@components/ui/label";
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

const providerApiKey = ref("");
const providerEndpoint = ref(providerApiEndpoint);
const effectiveUsage = ref<ProviderUsage | null>(providerUsage);
const saving = ref(false);
const testing = ref(false);
const connectionState = ref<"idle" | "success" | "error">("idle");
const connectionError = ref("");

const usagePercent = computed(() => {
  if (!effectiveUsage.value || effectiveUsage.value.characterLimit === 0) return 0;
  return Math.min(
    100,
    Math.round((effectiveUsage.value.characterCount / effectiveUsage.value.characterLimit) * 100),
  );
});

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

function saveProviderConfig() {
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

function testProviderConnection() {
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

function formatNumber(n: number | string) {
  if (typeof n !== "number") return String(n);
  return n.toLocaleString();
}
</script>

<template>
  <div class="space-y-4">
    <div class="overflow-hidden rounded-xl border border-base-300 bg-base-100 shadow-sm">
      <header
        class="flex flex-col gap-3 border-b border-base-300 bg-base-200/40 px-5 py-4 sm:flex-row sm:items-center"
      >
        <div class="flex size-11 items-center justify-center rounded-xl bg-primary/10 text-primary">
          <KeyRound class="size-5" />
        </div>
        <div class="min-w-0 flex-1">
          <div class="flex flex-wrap items-center gap-2">
            <h4 class="font-semibold">{{ $t("project_settings.localization.provider_title") }}</h4>
            <span
              :class="[
                'badge badge-sm',
                hasApiKey ? 'badge-success badge-outline' : 'badge-warning badge-outline',
              ]"
            >
              {{
                hasApiKey
                  ? $t("project_settings.localization.configured")
                  : $t("project_settings.localization.not_configured")
              }}
            </span>
          </div>
          <p class="mt-1 text-sm text-base-content/55">
            {{ $t("project_settings.localization.provider_description") }}
          </p>
        </div>
        <a
          href="https://developers.deepl.com/docs/getting-started/auth"
          target="_blank"
          rel="noreferrer"
          class="btn btn-ghost btn-sm"
        >
          {{ $t("project_settings.localization.api_key_help") }}
          <ExternalLink class="size-3.5" />
        </a>
      </header>

      <form class="space-y-5 p-5" @submit.prevent="saveProviderConfig">
        <div class="space-y-1.5">
          <Label for="api-key">{{ $t("project_settings.localization.api_key") }}</Label>
          <PasswordInput
            id="api-key"
            v-model="providerApiKey"
            :placeholder="hasApiKey ? '••••••••' : ''"
            autocomplete="off"
          />
          <p class="text-xs text-base-content/50">
            {{
              hasApiKey
                ? $t("project_settings.localization.api_key_preserved")
                : $t("project_settings.localization.api_key_required")
            }}
          </p>
        </div>

        <div class="space-y-1.5">
          <Label for="api-tier">{{ $t("project_settings.localization.api_tier") }}</Label>
          <Select v-model="providerEndpoint">
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="https://api-free.deepl.com">{{
                $t("project_settings.localization.tier_free")
              }}</SelectItem>
              <SelectItem value="https://api.deepl.com">{{
                $t("project_settings.localization.tier_pro")
              }}</SelectItem>
            </SelectContent>
          </Select>
          <p class="text-xs text-base-content/50">
            {{ $t("project_settings.localization.tier_help") }}
          </p>
        </div>

        <div
          v-if="connectionState !== 'idle'"
          :class="[
            'alert py-2.5 text-sm',
            connectionState === 'success' ? 'alert-success' : 'alert-error',
          ]"
          role="status"
        >
          <CheckCircle2 v-if="connectionState === 'success'" class="size-4" />
          <CircleAlert v-else class="size-4" />
          <span>
            {{
              connectionState === "success"
                ? $t("project_settings.localization.connection_success")
                : $t("project_settings.localization.connection_error", { error: connectionError })
            }}
          </span>
        </div>

        <div
          class="flex flex-col-reverse gap-2 border-t border-base-300 pt-4 sm:flex-row sm:justify-end"
        >
          <Button
            v-if="hasApiKey"
            type="button"
            data-testid="localization-test-connection"
            variant="outline"
            :disabled="testing || saving"
            @click="testProviderConnection"
          >
            <LoaderCircle v-if="testing" class="size-4 animate-spin" />
            {{ $t("project_settings.localization.test_connection") }}
          </Button>
          <Button
            type="submit"
            data-testid="localization-save-provider"
            :disabled="saving || testing"
          >
            <LoaderCircle v-if="saving" class="size-4 animate-spin" />
            {{ $t("project_settings.localization.save") }}
          </Button>
        </div>
      </form>
    </div>

    <div v-if="effectiveUsage" class="rounded-xl border border-base-300 bg-base-100 p-5 shadow-sm">
      <div class="flex items-start gap-3">
        <div class="flex size-9 items-center justify-center rounded-lg bg-info/10 text-info">
          <Gauge class="size-4" />
        </div>
        <div class="min-w-0 flex-1">
          <div class="flex items-center justify-between gap-3">
            <div>
              <h4 class="font-medium">{{ $t("project_settings.localization.usage_title") }}</h4>
              <p class="text-xs text-base-content/50">
                {{ $t("project_settings.localization.usage_description") }}
              </p>
            </div>
            <span class="text-sm font-semibold tabular-nums">{{ usagePercent }}%</span>
          </div>
          <progress
            class="progress progress-info mt-3 h-2 w-full"
            :value="usagePercent"
            max="100"
          />
          <div class="mt-2 flex items-center justify-between text-xs text-base-content/55">
            <span
              >{{ formatNumber(effectiveUsage.characterCount) }}
              {{ $t("project_settings.localization.used") }}</span
            >
            <span
              >{{ formatNumber(effectiveUsage.characterLimit) }}
              {{ $t("project_settings.localization.limit") }}</span
            >
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
