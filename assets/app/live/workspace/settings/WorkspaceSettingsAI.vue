<script setup lang="ts">
import { Sparkles } from "@lucide/vue";
import { useI18n } from "vue-i18n";
import LiveLink from "@components/navigation/LiveLink.vue";
import {
  SettingsEmptyState,
  SettingsPage,
  SettingsRow,
  SettingsSection,
} from "@components/settings";
import { Badge } from "@components/ui/badge";
import { Button } from "@components/ui/button";
import { Switch } from "@components/ui/switch";
import { useLive } from "@shared/composables/useLive";

interface AiSettings {
  visible?: boolean;
  managedAllowed?: boolean;
  personalMembersAllowed?: boolean;
  allowance?: {
    status?: string;
    availableUnits?: number;
    reservedUnits?: number;
    committedUnits?: number;
  };
  provenance?: {
    provider?: string;
    model?: string;
    region?: string;
    dataRetention?: string;
    trainingUsage?: string;
  } | null;
}

const {
  isOwner,
  ai = {},
  integrationsPath,
} = defineProps<{
  isOwner: boolean;
  ai?: AiSettings;
  integrationsPath: string;
}>();

const { t } = useI18n();
const live = useLive();

function updateManagedAiPolicy(enabled: boolean): void {
  if (!isOwner) return;
  live.pushEvent("update_managed_ai_policy", { enabled });
}

function updatePersonalAiMembersPolicy(enabled: boolean): void {
  if (!isOwner) return;
  live.pushEvent("update_personal_ai_members_policy", { enabled });
}
</script>

<template>
  <SettingsPage :title="t('settings.workspace.ai.title')">
    <template v-if="!ai.visible">
      <SettingsSection :title="t('settings.workspace.storyarn_ai.title')">
        <SettingsEmptyState
          :icon="Sparkles"
          :title="t('settings.workspace.ai.unavailable.title')"
          :text="t('settings.workspace.ai.unavailable.text')"
        />
      </SettingsSection>
    </template>

    <template v-else>
      <SettingsSection
        id="storyarn-ai-settings"
        :title="t('settings.workspace.storyarn_ai.title')"
        :locked="!isOwner"
        :locked-label="t('settings.workspace.storyarn_ai.owner_only')"
      >
        <template #title-extra>
          <Badge variant="outline">{{ t("settings.workspace.storyarn_ai.beta_badge") }}</Badge>
        </template>

        <SettingsRow
          :label="t('settings.workspace.storyarn_ai.toggle_label')"
          :hint="t('settings.workspace.storyarn_ai.description')"
        >
          <Switch
            id="storyarn-ai-policy-toggle"
            :model-value="ai.managedAllowed"
            :disabled="!isOwner"
            :aria-label="t('settings.workspace.storyarn_ai.toggle_label')"
            @update:model-value="updateManagedAiPolicy"
          />
        </SettingsRow>

        <SettingsRow :label="t('settings.workspace.storyarn_ai.allowance')">
          <template #hint>
            <template v-if="ai.provenance">
              {{
                t("settings.workspace.storyarn_ai.disclosure", {
                  provider: ai.provenance.provider,
                  model: ai.provenance.model,
                  region: ai.provenance.region,
                })
              }}
            </template>
            <template v-else>{{ t("settings.workspace.storyarn_ai.route_unavailable") }}</template>
          </template>
          <Badge :variant="ai.allowance?.status === 'active' ? 'default' : 'secondary'">
            {{
              t("settings.workspace.storyarn_ai.units_left", {
                count: ai.allowance?.availableUnits ?? 0,
              })
            }}
          </Badge>
          <Badge variant="outline">
            {{
              t(`settings.workspace.storyarn_ai.states.${ai.allowance?.status ?? "unavailable"}`)
            }}
          </Badge>
        </SettingsRow>
      </SettingsSection>

      <SettingsSection
        id="personal-ai-members-policy"
        :title="t('settings.workspace.personal_ai.title')"
        :locked="!isOwner"
        :locked-label="t('settings.workspace.personal_ai.owner_only')"
      >
        <SettingsRow
          :label="t('settings.workspace.personal_ai.toggle_label')"
          :hint="t('settings.workspace.personal_ai.description')"
        >
          <Switch
            id="personal-ai-members-policy-toggle"
            :model-value="ai.personalMembersAllowed"
            :disabled="!isOwner"
            :aria-label="t('settings.workspace.personal_ai.toggle_label')"
            @update:model-value="updatePersonalAiMembersPolicy"
          />
        </SettingsRow>

        <SettingsRow
          :label="t('settings.workspace.personal_ai.data_handling')"
          :hint="t('settings.workspace.personal_ai.disclosure')"
        >
          <Button as-child variant="ghost" size="sm">
            <LiveLink :to="integrationsPath">
              {{ t("settings.workspace.personal_ai.manage_keys") }}
            </LiveLink>
          </Button>
        </SettingsRow>
      </SettingsSection>
    </template>
  </SettingsPage>
</template>
