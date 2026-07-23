import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it } from "vitest";
import IntegrationCard, {
  type IntegrationCardData,
} from "../../../../live/account/settings/integrations/IntegrationCard.vue";
import { setTestLocale } from "../../../setup";

function cardData(overrides: Partial<IntegrationCardData> = {}): IntegrationCardData {
  return {
    provider: "anthropic",
    name: "Anthropic Claude",
    status: "not_connected",
    account_email: null,
    account_display_name: null,
    key_last_four: null,
    workspace_count: 0,
    compatible_model_count: 3,
    catalog_status: "not_connected",
    detail_path: "/users/settings/integrations/anthropic?sudo_grant=valid",
    ...overrides,
  };
}

function mountCard(overrides: Partial<IntegrationCardData> = {}) {
  return mount(IntegrationCard, { props: { card: cardData(overrides) } });
}

describe("IntegrationCard", () => {
  beforeEach(() => {
    setTestLocale("en");
  });

  it("renders an available provider as a compact link to configuration", () => {
    const wrapper = mountCard();

    expect(wrapper.text()).toContain("Anthropic Claude");
    expect(wrapper.text()).toContain("Not connected");
    expect(wrapper.text()).toContain("3 supported models");
    expect(wrapper.text()).toContain("Configure provider");
    expect(wrapper.attributes("href")).toBe(
      "/users/settings/integrations/anthropic?sudo_grant=valid",
    );
    expect(wrapper.attributes("data-layout")).toBe("available");
    expect(wrapper.find("button").exists()).toBe(false);
  });

  it("summarizes a healthy connected provider without embedding its settings", () => {
    const wrapper = mountCard({
      status: "connected",
      key_last_four: "abcd",
      workspace_count: 2,
      compatible_model_count: 1,
      catalog_status: "ready",
    });

    expect(wrapper.text()).toContain("Key ending in abcd");
    expect(wrapper.text()).toContain("2 workspaces");
    expect(wrapper.text()).toContain("1 supported model");
    expect(wrapper.find('[data-testid="catalog-warning"]').exists()).toBe(false);
    expect(wrapper.attributes("data-layout")).toBe("connected");
  });

  it("prefers account identity over the masked key", () => {
    const wrapper = mountCard({
      status: "connected",
      account_email: "dev@example.com",
      key_last_four: "abcd",
      catalog_status: "ready",
    });

    expect(wrapper.text()).toContain("dev@example.com");
    expect(wrapper.text()).not.toContain("Key ending in");
  });

  it("shows only a concise warning when a connected provider needs repair", () => {
    const wrapper = mountCard({
      status: "connected",
      key_last_four: "abcd",
      catalog_status: "model_unavailable",
    });

    expect(wrapper.get('[data-testid="catalog-warning"]').text()).toBe("Model unavailable");
    expect(wrapper.text()).not.toContain("Model status");
    expect(wrapper.text()).not.toContain("Connection only");
  });
});
