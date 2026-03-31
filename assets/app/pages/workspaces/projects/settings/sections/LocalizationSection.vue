<script setup>
import { ref, watch } from "vue";
import { Button } from "@components/ui/button/index.js";
import { Input } from "@components/ui/input/index.js";
import { Label } from "@components/ui/label/index.js";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select/index.js";
import { useLive } from "@composables/useLive.js";

const props = defineProps({
  providerApiEndpoint: { type: String, default: "https://api-free.deepl.com" },
  hasApiKey: { type: Boolean, default: false },
  providerUsage: { type: Object, default: null },
});

const live = useLive();

const providerApiKey = ref("");
const providerEndpoint = ref(props.providerApiEndpoint);

watch(
  () => props.providerApiEndpoint,
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

function formatNumber(n) {
  if (typeof n !== "number") return String(n);
  return n.toLocaleString();
}
</script>

<template>
  <div>
    <div class="rounded-lg border border-border bg-muted/30 p-4">
      <h4 class="font-medium mb-3">Translation Provider (DeepL)</h4>

      <form @submit.prevent="saveProviderConfig" class="space-y-4">
        <div class="space-y-1.5">
          <Label for="api-key">API Key</Label>
          <Input
            id="api-key"
            type="password"
            v-model="providerApiKey"
            :placeholder="hasApiKey ? '••••••••' : ''"
          />
        </div>

        <div class="space-y-1.5">
          <Label for="api-tier">API Tier</Label>
          <Select v-model="providerEndpoint">
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="https://api-free.deepl.com">Free (api-free.deepl.com)</SelectItem>
              <SelectItem value="https://api.deepl.com">Pro (api.deepl.com)</SelectItem>
            </SelectContent>
          </Select>
        </div>

        <div class="flex justify-end gap-3 pt-1">
          <Button v-if="hasApiKey" type="button" variant="outline" @click="testProviderConnection">
            Test Connection
          </Button>
          <Button type="submit">Save</Button>
        </div>
      </form>

      <div v-if="providerUsage" class="mt-3 text-sm text-muted-foreground">
        Usage: {{ formatNumber(providerUsage.characterCount) }} /
        {{ formatNumber(providerUsage.characterLimit) }} characters
      </div>
    </div>
  </div>
</template>
