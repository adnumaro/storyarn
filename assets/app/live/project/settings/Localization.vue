<script setup lang="ts">
import { ref, watch } from "vue";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
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

watch(
  () => providerApiEndpoint,
  (v) => {
    providerEndpoint.value = v;
  },
);

function saveProviderConfig() {
  live.pushEvent("save_provider_config", {
    provider: {
      api_key_encrypted: providerApiKey.value,
      api_endpoint: providerEndpoint.value,
    },
  });
  providerApiKey.value = "";
}

function testProviderConnection() {
  live.pushEvent("test_provider_connection", {});
}

function formatNumber(n: number | string) {
  if (typeof n !== "number") return String(n);
  return n.toLocaleString();
}
</script>

<template>
  <div>
    <div class="rounded-lg border border-border bg-muted/30 p-4">
      <h4 class="font-medium mb-3">{{ $t("project_settings.localization.provider_title") }}</h4>

      <form @submit.prevent="saveProviderConfig" class="space-y-4">
        <div class="space-y-1.5">
          <Label for="api-key">{{ $t("project_settings.localization.api_key") }}</Label>
          <Input
            id="api-key"
            type="password"
            v-model="providerApiKey"
            :placeholder="hasApiKey ? '••••••••' : ''"
          />
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
        </div>

        <div class="flex justify-end gap-3 pt-1">
          <Button v-if="hasApiKey" type="button" variant="outline" @click="testProviderConnection">
            {{ $t("project_settings.localization.test_connection") }}
          </Button>
          <Button type="submit">{{ $t("project_settings.localization.save") }}</Button>
        </div>
      </form>

      <div v-if="providerUsage" class="mt-3 text-sm text-muted-foreground">
        {{ $t("project_settings.localization.usage_prefix")
        }}{{ formatNumber(providerUsage.characterCount) }} /
        {{ formatNumber(providerUsage.characterLimit)
        }}{{ $t("project_settings.localization.usage_characters") }}
      </div>
    </div>
  </div>
</template>
