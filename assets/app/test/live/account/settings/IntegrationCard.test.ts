import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it } from "vitest";
import IntegrationCard, {
  type IntegrationCardData,
} from "../../../../live/account/settings/integrations/IntegrationCard.vue";
import { setTestLocale } from "../../../setup";

function cardData(overrides: Partial<IntegrationCardData> = {}): IntegrationCardData {
  return {
    integration_id: null,
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
    catalog_status: "connection_only",
    models: [],
    workspace_assignments: [],
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
    const wrapper = mountCard({
      integration_id: 12,
      status: "connected",
      key_last_four: "abcd",
    });

    expect(wrapper.text()).toContain("Key ending in abcd");
    expect(wrapper.get("button").text()).toBe("Disconnect");
    expect(wrapper.attributes("data-status")).toBe("connected");
  });

  it("prefers the account email over the masked key when available", () => {
    const wrapper = mountCard({
      integration_id: 12,
      status: "connected",
      key_last_four: "abcd",
      account_email: "dev@example.com",
    });

    expect(wrapper.text()).toContain("Connected as dev@example.com");
    expect(wrapper.text()).not.toContain("Key ending in");
  });

  it("emits disconnect when the Disconnect button is clicked", async () => {
    const wrapper = mountCard({
      integration_id: 12,
      status: "connected",
      key_last_four: "abcd",
    });

    await wrapper.get("button").trigger("click");

    expect(wrapper.emitted("disconnect")).toHaveLength(1);
  });

  it("shows model readiness and emits a workspace assignment toggle", async () => {
    const workspace = {
      workspace_id: 7,
      workspace_name: "Narrative team",
      workspace_slug: "narrative-team",
      role: "owner",
      assigned: false,
      assignment_id: null,
      can_assign: true,
      state: "available" as const,
      reason: "owner_allowed" as const,
    };

    const wrapper = mountCard({
      integration_id: 12,
      status: "connected",
      key_last_four: "abcd",
      catalog_status: "ready",
      models: [
        {
          provider: "openai",
          model: "gpt-test",
          catalog_version: 1,
          capabilities: ["suggestions"],
          modalities: ["text"],
          structured_output: "json_schema",
          context_window: 128_000,
          max_output_tokens: 8_192,
          processing_locations: ["provider-controlled"],
          pricing_version: null,
          deprecated: false,
        },
      ],
      workspace_assignments: [workspace],
    });

    expect(wrapper.text()).toContain("Available for AI routing");
    expect(wrapper.text()).toContain("gpt-test");
    expect(wrapper.text()).toContain("0 of 1 workspaces enabled");

    await wrapper.get('[data-workspace-id="7"] button').trigger("click");

    expect(wrapper.emitted("toggleWorkspace")).toEqual([[workspace]]);
  });

  it("explains a workspace policy block without exposing an enable control", () => {
    const wrapper = mountCard({
      integration_id: 12,
      status: "connected",
      key_last_four: "abcd",
      workspace_assignments: [
        {
          workspace_id: 8,
          workspace_name: "Locked team",
          workspace_slug: "locked-team",
          role: "member",
          assigned: false,
          assignment_id: null,
          can_assign: false,
          state: "blocked",
          reason: "member_policy_disabled",
        },
      ],
    });

    const row = wrapper.get('[data-workspace-id="8"]');
    expect(row.text()).toContain("The workspace owner has disabled personal AI keys");
    expect(row.text()).toContain("Blocked");
    expect(row.find("button").exists()).toBe(false);
  });

  it("links to the provider docs", () => {
    const wrapper = mountCard();

    const link = wrapper.get("a");
    expect(link.attributes("href")).toBe("https://docs.claude.com/en/api/getting-started");
    expect(link.attributes("rel")).toContain("noopener");
  });
});
