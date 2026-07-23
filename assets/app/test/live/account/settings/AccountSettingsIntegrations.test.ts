import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it } from "vitest";
import AccountSettingsIntegrations from "../../../../live/account/settings/AccountSettingsIntegrations.vue";
import type { IntegrationCardData } from "../../../../live/account/settings/integrations/IntegrationCard.vue";
import { setTestLocale } from "../../../setup";

function card(provider: string, overrides: Partial<IntegrationCardData> = {}): IntegrationCardData {
  return {
    provider,
    name: provider,
    status: "not_connected",
    account_email: null,
    account_display_name: null,
    key_last_four: null,
    workspace_count: 0,
    compatible_model_count: 2,
    catalog_status: "not_connected",
    detail_path: `/users/settings/integrations/${provider}?sudo_grant=valid`,
    ...overrides,
  };
}

describe("AccountSettingsIntegrations", () => {
  beforeEach(() => {
    setTestLocale("en");
  });

  it("separates connected providers from the available provider grid", () => {
    const wrapper = mount(AccountSettingsIntegrations, {
      props: {
        cards: [
          card("anthropic"),
          card("openai", {
            status: "connected",
            key_last_four: "dQ0A",
            workspace_count: 2,
            catalog_status: "ready",
          }),
          card("google"),
        ],
      },
    });

    const connectedSection = wrapper.get("#connected-integrations");
    const availableSection = wrapper.get("#available-integrations");

    expect(connectedSection.text()).toContain("Connected providers");
    expect(connectedSection.find('[data-provider="openai"]').exists()).toBe(true);
    expect(connectedSection.find('[data-provider="anthropic"]').exists()).toBe(false);

    expect(availableSection.text()).toContain("Available providers");
    expect(availableSection.find('[data-provider="anthropic"]').exists()).toBe(true);
    expect(availableSection.find('[data-provider="google"]').exists()).toBe(true);
    expect(availableSection.find('[data-provider="openai"]').exists()).toBe(false);
    expect(availableSection.get(".grid").classes()).toContain("lg:grid-cols-3");
  });

  it("keeps the catalog read-only and links every provider to its detail screen", () => {
    const wrapper = mount(AccountSettingsIntegrations, {
      props: {
        cards: [
          card("anthropic"),
          card("openai", {
            status: "connected",
            catalog_status: "ready",
          }),
        ],
      },
    });

    expect(wrapper.findAll("button")).toHaveLength(0);

    const links = wrapper.findAll("a");
    expect(links.map((link) => link.attributes("href"))).toEqual([
      "/users/settings/integrations/openai?sudo_grant=valid",
      "/users/settings/integrations/anthropic?sudo_grant=valid",
    ]);

    expect(wrapper.text()).not.toContain("Model status");
    expect(wrapper.text()).not.toContain("Connection only");
  });

  it("renders an empty state when no providers are exposed", () => {
    const wrapper = mount(AccountSettingsIntegrations, { props: { cards: [] } });

    expect(wrapper.text()).toContain("No AI providers are available yet");
    expect(wrapper.find("#connected-integrations").exists()).toBe(false);
    expect(wrapper.find("#available-integrations").exists()).toBe(false);
  });
});
