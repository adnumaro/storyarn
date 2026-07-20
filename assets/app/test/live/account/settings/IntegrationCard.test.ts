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
    key_generation_url: "https://platform.claude.com/settings/keys",
    docs_url: "https://docs.claude.com/en/api/getting-started",
    key_placeholder: "sk-ant-api03-...",
    status: "not_connected",
    account_email: null,
    account_display_name: null,
    key_last_four: null,
    connected_at: null,
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

  it("renders the not-connected state with a Connect button", () => {
    const wrapper = mountCard();

    expect(wrapper.text()).toContain("Anthropic Claude");
    expect(wrapper.text()).toContain("Not connected");
    expect(wrapper.get("button").text()).toBe("Connect");
    expect(wrapper.attributes("data-status")).toBe("not_connected");
  });

  it("emits connect when the Connect button is clicked", async () => {
    const wrapper = mountCard();

    await wrapper.get("button").trigger("click");

    expect(wrapper.emitted("connect")).toHaveLength(1);
    expect(wrapper.emitted("disconnect")).toBeUndefined();
  });

  it("renders the connected state with the masked key when no account info exists", () => {
    const wrapper = mountCard({ status: "connected", key_last_four: "abcd" });

    expect(wrapper.text()).toContain("Key ending in abcd");
    expect(wrapper.get("button").text()).toBe("Disconnect");
    expect(wrapper.attributes("data-status")).toBe("connected");
  });

  it("prefers the account email over the masked key when available", () => {
    const wrapper = mountCard({
      status: "connected",
      key_last_four: "abcd",
      account_email: "dev@example.com",
    });

    expect(wrapper.text()).toContain("Connected as dev@example.com");
    expect(wrapper.text()).not.toContain("Key ending in");
  });

  it("emits disconnect when the Disconnect button is clicked", async () => {
    const wrapper = mountCard({ status: "connected", key_last_four: "abcd" });

    await wrapper.get("button").trigger("click");

    expect(wrapper.emitted("disconnect")).toHaveLength(1);
  });

  it("links to the provider docs", () => {
    const wrapper = mountCard();

    const link = wrapper.get("a");
    expect(link.attributes("href")).toBe("https://docs.claude.com/en/api/getting-started");
    expect(link.attributes("rel")).toContain("noopener");
  });
});
