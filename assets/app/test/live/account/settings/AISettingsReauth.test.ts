import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import AccountSettingsIntegrations from "../../../../live/account/settings/AccountSettingsIntegrations.vue";
import MyAITeam from "../../../../live/account/settings/MyAITeam.vue";
import MyAITeamOverview from "../../../../live/account/settings/MyAITeamOverview.vue";
import ProviderIntegrationDetail from "../../../../live/account/settings/ProviderIntegrationDetail.vue";
import { createMockLive } from "../../../setup";

const reauth = {
  confirmAction: "/users/confirm-access",
  csrfToken: "csrf",
  returnTo: "/users/settings/integrations",
  sudoHandoff: null,
  triggerSubmit: false,
};

const lockedCard = {
  integration_id: null,
  provider: "openai",
  name: "OpenAI",
  key_generation_url: "https://platform.openai.com/api-keys",
  docs_url: "https://platform.openai.com/docs",
  key_placeholder: "sk-…",
  status: "not_connected" as const,
  account_email: null,
  account_display_name: null,
  key_last_four: null,
  connected_at: null,
  last_validated_at: null,
  catalog_status: "not_connected",
  capabilities: ["text"],
  models: [],
  workspace_assignments: [],
  preference_impacts: [],
};

function global() {
  return { provide: { _live_vue: createMockLive() } };
}

describe("AI settings pages outside the sudo window", () => {
  it("lock the integrations catalog behind the re-authentication banner", () => {
    const wrapper = mount(AccountSettingsIntegrations, {
      props: { cards: [], sudoActive: false, reauth },
      global: global(),
    });

    expect(wrapper.find('[data-testid="settings-reauth"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="settings-reauth-locked"]').exists()).toBe(true);
    expect(wrapper.find("#connected-integrations").exists()).toBe(false);
    expect(wrapper.text()).not.toContain("No AI providers are available yet");
  });

  it("lock the provider detail without rendering connection controls", () => {
    const wrapper = mount(ProviderIntegrationDetail, {
      props: { card: lockedCard, sudoActive: false, reauth },
      global: global(),
    });

    expect(wrapper.find('[data-testid="settings-reauth"]').exists()).toBe(true);
    expect(wrapper.find("#provider-connection").exists()).toBe(false);
    expect(wrapper.find("#provider-workspaces").exists()).toBe(false);
    expect(wrapper.get("h1").text()).toContain("OpenAI");
  });

  it("lock the AI team overview and editor", () => {
    const overview = mount(MyAITeamOverview, {
      props: { workspaces: [], sudoActive: false, reauth },
      global: global(),
    });
    const editor = mount(MyAITeam, {
      props: {
        workspace: { id: 1, name: "Narrative Games", slug: "narrative-games" },
        policyAllowed: true,
        slots: [],
        providersPath: "/users/settings/integrations",
        overviewPath: "/users/settings/ai-team",
        sudoActive: false,
        reauth,
      },
      global: global(),
    });

    expect(overview.find('[data-testid="settings-reauth"]').exists()).toBe(true);
    expect(overview.find("#ai-team-workspace-overviews").exists()).toBe(false);
    expect(overview.find("#ai-team-overview-empty").exists()).toBe(false);

    expect(editor.find('[data-testid="settings-reauth"]').exists()).toBe(true);
    expect(editor.find("#manage-ai-integrations").exists()).toBe(false);
    expect(editor.text()).not.toContain("No configurable AI roles are available yet");
  });

  it("render normally inside the sudo window", () => {
    const wrapper = mount(AccountSettingsIntegrations, {
      props: { cards: [], sudoActive: true, reauth },
      global: global(),
    });

    expect(wrapper.find('[data-testid="settings-reauth"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="settings-reauth-locked"]').exists()).toBe(false);
    expect(wrapper.text()).toContain("No AI providers are available yet");
  });
});
