import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { defineComponent, type App } from "vue";
import ProviderIntegrationDetail, {
  type ProviderIntegrationDetailData,
  type ProviderModelData,
} from "../../../../live/account/settings/ProviderIntegrationDetail.vue";
import type { LiveInterface } from "../../../../shared/composables/useLive";
import { createMockLive, setTestLocale } from "../../../setup";

type ReplyCallback = (reply: { status?: string; error?: string }) => void;

const ConnectKeyDialogStub = defineComponent({
  name: "ConnectKeyDialog",
  props: {
    open: { type: Boolean, required: true },
    card: { type: Object, required: true },
    mode: { type: String, default: "connect" },
    submitting: { type: Boolean, default: false },
  },
  emits: ["submit", "cancel"],
  template: `<div
    data-testid="credential-dialog"
    :data-mode="mode"
    :data-submitting="submitting"
  />`,
});

const ConfirmDialogStub = defineComponent({
  name: "ConfirmDialog",
  props: {
    open: { type: Boolean, required: true },
    title: { type: String, default: "" },
    description: { type: String, default: "" },
  },
  emits: ["confirm", "cancel", "update:open"],
  template: `<div data-testid="confirm-dialog" :data-open="open" />`,
});

function model(
  name: string,
  availability: "available" | "unavailable" | "unknown" | "deprecated" = "available",
  overrides: Partial<ProviderModelData> = {},
): ProviderModelData {
  return {
    provider: "openai",
    model: name,
    catalog_version: 1,
    capabilities: ["suggestions", "tasks"],
    input_modalities: ["text"],
    output_modalities: ["text"],
    api_family: "structured_text",
    implementation_status: "executable",
    release_stage: "stable",
    structured_output: "json_schema",
    context_window: 128_000,
    max_output_tokens: 8_192,
    processing_locations: ["provider-controlled"],
    pricing_version: null,
    deprecated: availability === "deprecated",
    availability,
    ...overrides,
  };
}

function detail(
  overrides: Partial<ProviderIntegrationDetailData> = {},
): ProviderIntegrationDetailData {
  return {
    integration_id: 42,
    provider: "openai",
    name: "OpenAI",
    key_generation_url: "https://platform.openai.com/api-keys",
    docs_url: "https://platform.openai.com/docs",
    key_placeholder: "sk-...",
    status: "connected",
    account_email: null,
    account_display_name: null,
    key_last_four: "dQ0A",
    connected_at: "2026-07-21T10:00:00Z",
    last_validated_at: "2026-07-23T10:00:00Z",
    catalog_status: "ready",
    capabilities: ["suggestions", "tasks"],
    models: [
      model("gpt-ready"),
      model("gpt-unknown", "unknown"),
      model("gpt-retired", "deprecated"),
      model("gpt-future-voice", "available", {
        capabilities: ["speech"],
        output_modalities: ["audio"],
        api_family: "openai_speech",
        implementation_status: "configuration_only",
        release_stage: "preview",
      }),
    ],
    workspace_assignments: [
      {
        workspace_id: 2,
        workspace_name: "Zebra games",
        workspace_slug: "zebra-games",
        role: "owner",
        assigned: false,
        assignment_id: null,
        can_assign: true,
        state: "available",
        reason: "owner_allowed",
      },
      {
        workspace_id: 1,
        workspace_name: "Alpha films",
        workspace_slug: "alpha-films",
        role: "owner",
        assigned: true,
        assignment_id: 12,
        can_assign: true,
        state: "assigned",
        reason: "owner_allowed",
      },
    ],
    preference_impacts: [],
    ...overrides,
  };
}

function livePlugin(live: LiveInterface) {
  return {
    install(app: App) {
      app.config.globalProperties.$live = live;
    },
  };
}

function mountDetail(overrides: Partial<ProviderIntegrationDetailData> = {}) {
  const live = createMockLive();
  const wrapper = mount(ProviderIntegrationDetail, {
    props: {
      card: detail(overrides),
      providersPath: "/users/settings/integrations?sudo_grant=valid",
    },
    global: {
      plugins: [livePlugin(live)],
      provide: { _live_vue: live },
      stubs: {
        ConnectKeyDialog: ConnectKeyDialogStub,
        ConfirmDialog: ConfirmDialogStub,
      },
    },
  });

  return { live, wrapper };
}

describe("ProviderIntegrationDetail", () => {
  beforeEach(() => {
    setTestLocale("en");
  });

  it("keeps connection, models, and workspace access on a dedicated provider screen", () => {
    const { wrapper } = mountDetail();

    expect(wrapper.get("#back-to-integrations").attributes("href")).toBe(
      "/users/settings/integrations?sudo_grant=valid",
    );
    expect(wrapper.get("#provider-connection").text()).toContain("Key ending in dQ0A");
    expect(wrapper.get('[data-model="gpt-ready"]').text()).toContain("Available");
    expect(wrapper.get('[data-model="gpt-unknown"]').text()).toContain("Availability to confirm");
    expect(wrapper.get('[data-model="gpt-retired"]').text()).toContain("Deprecated");
    expect(wrapper.get('[data-model="gpt-future-voice"]').text()).toContain("Configuration only");
    expect(wrapper.get('[data-model="gpt-future-voice"]').text()).toContain("Preview");
    expect(wrapper.get('[data-model="gpt-future-voice"]').text()).toContain("Speech");
    expect(wrapper.get('[data-model="gpt-future-voice"]').text()).toContain(
      "no provider charge occurs",
    );
    expect(
      wrapper.get('[data-model="gpt-future-voice"]').attributes("data-model-implementation"),
    ).toBe("configuration_only");
    expect(wrapper.get("#provider-models").text()).toContain("1 available for this key");
    expect(wrapper.get("#provider-models > div").classes()).toContain("sm:flex-row");
    expect(wrapper.find("#provider-workspaces").exists()).toBe(true);
    expect(wrapper.text()).not.toContain("Model status");
    expect(wrapper.text()).not.toContain("Connection only");
  });

  it("sorts enabled workspaces first and filters a long workspace list locally", async () => {
    const { wrapper } = mountDetail();
    const rows = wrapper.findAll("[data-workspace-id]");

    expect(rows.map((row) => row.attributes("data-workspace-id"))).toEqual(["1", "2"]);
    expect(wrapper.get("#workspace-assignment-search").attributes("aria-label")).toBe(
      "Search workspaces",
    );
    expect(wrapper.get('[data-workspace-id="1"] button').attributes("aria-label")).toBe(
      "Disable this connection for Alpha films",
    );
    expect(wrapper.get('[data-workspace-id="2"] button').attributes("aria-label")).toBe(
      "Enable this connection for Zebra games",
    );

    await wrapper.get("#workspace-assignment-search").setValue("Zebra");

    const filteredRows = wrapper.findAll("[data-workspace-id]");
    expect(filteredRows).toHaveLength(1);
    expect(filteredRows[0]!.attributes("data-workspace-id")).toBe("2");
  });

  it("explains when project-only access cannot enable a provider connection", () => {
    const { wrapper } = mountDetail({
      workspace_assignments: [
        {
          workspace_id: 3,
          workspace_name: "Project access only",
          workspace_slug: "project-access-only",
          role: null,
          assigned: false,
          assignment_id: null,
          can_assign: false,
          state: "blocked",
          reason: "workspace_membership_required",
        },
      ],
    });

    expect(wrapper.get('[data-workspace-id="3"]').text()).toContain(
      "Direct workspace membership is required",
    );
  });

  it("sends only the selected workspace id when changing access", async () => {
    const { live, wrapper } = mountDetail();

    await wrapper.get('[data-workspace-id="2"] button').trigger("click");

    const pushEventMock = live.pushEvent as unknown as {
      mock: { calls: [string, unknown, ReplyCallback][] };
    };

    expect(pushEventMock.mock.calls[0]![0]).toBe("assign_workspace");
    expect(pushEventMock.mock.calls[0]![1]).toEqual({ workspace_id: 2 });
  });

  it("tracks simultaneous workspace mutations independently", async () => {
    const { live, wrapper } = mountDetail();

    await wrapper.get('[data-workspace-id="2"] button').trigger("click");
    await wrapper.get('[data-workspace-id="1"] button').trigger("click");

    const pushEventMock = live.pushEvent as unknown as {
      mock: { calls: [string, unknown, ReplyCallback][] };
    };

    expect(wrapper.get('[data-workspace-id="2"] button').attributes()).toHaveProperty("disabled");
    expect(wrapper.get('[data-workspace-id="1"] button').attributes()).toHaveProperty("disabled");

    pushEventMock.mock.calls[0]![2]({ status: "ok" });
    await wrapper.vm.$nextTick();

    expect(wrapper.get('[data-workspace-id="2"] button').attributes()).not.toHaveProperty(
      "disabled",
    );
    expect(wrapper.get('[data-workspace-id="1"] button').attributes()).toHaveProperty("disabled");

    pushEventMock.mock.calls[1]![2]({ status: "ok" });
    await wrapper.vm.$nextTick();

    expect(wrapper.get('[data-workspace-id="1"] button').attributes()).not.toHaveProperty(
      "disabled",
    );
  });

  it("validates a replacement before asking the server to rotate the key", async () => {
    const { live, wrapper } = mountDetail();

    await wrapper.get("#replace-provider-key").trigger("click");
    const dialog = wrapper.getComponent(ConnectKeyDialogStub);
    expect(dialog.props("mode")).toBe("replace");

    const onResult = vi.fn();
    await dialog.vm.$emit("submit", "sk-replacement", onResult);

    const pushEventMock = live.pushEvent as unknown as {
      mock: { calls: [string, unknown, ReplyCallback][] };
    };

    expect(pushEventMock.mock.calls[0]![0]).toBe("replace_key");
    expect(pushEventMock.mock.calls[0]![1]).toEqual({
      provider: "openai",
      api_key: "sk-replacement",
    });

    pushEventMock.mock.calls[0]![2]({ status: "ok" });
    await wrapper.vm.$nextTick();

    expect(onResult).toHaveBeenCalledWith(null);
    expect(wrapper.text()).toContain("new key was validated before replacing");
  });

  it("revalidates the key and discovered model availability", async () => {
    const { live, wrapper } = mountDetail();

    await wrapper.get("#revalidate-provider").trigger("click");

    const pushEventMock = live.pushEvent as unknown as {
      mock: { calls: [string, unknown, ReplyCallback][] };
    };

    expect(pushEventMock.mock.calls[0]![0]).toBe("revalidate");
    expect(pushEventMock.mock.calls[0]![1]).toEqual({ provider: "openai" });

    pushEventMock.mock.calls[0]![2]({ status: "ok" });
    await wrapper.vm.$nextTick();

    expect(wrapper.text()).toContain("model availability refreshed");
  });

  it("disconnects only after confirming the destructive impact", async () => {
    const { live, wrapper } = mountDetail();

    await wrapper.get("#disconnect-provider").trigger("click");
    const confirmation = wrapper.getComponent(ConfirmDialogStub);
    expect(confirmation.props("open")).toBe(true);

    await confirmation.vm.$emit("confirm");

    const pushEventMock = live.pushEvent as unknown as {
      mock: { calls: [string, unknown, ReplyCallback][] };
    };

    expect(pushEventMock.mock.calls[0]![0]).toBe("disconnect");
    expect(pushEventMock.mock.calls[0]![1]).toEqual({ provider: "openai" });
  });

  it("shows impacted workspace roles and puts repairs before healthy assignments", () => {
    const { wrapper } = mountDetail({
      preference_impacts: [
        {
          workspace_id: 1,
          workspace_name: "Alpha films",
          workspace_slug: "alpha-films",
          slot: "general_assistant",
          model: "gpt-ready",
          implementation_status: "executable",
          status: "ready",
        },
        {
          workspace_id: 2,
          workspace_name: "Zebra games",
          workspace_slug: "zebra-games",
          slot: "illustrator",
          model: "gpt-retired",
          implementation_status: null,
          status: "model_unavailable",
        },
        {
          workspace_id: 3,
          workspace_name: "Beta audio",
          workspace_slug: "beta-audio",
          slot: "voice",
          model: "gpt-future-voice",
          implementation_status: "configuration_only",
          status: "configured",
        },
      ],
    });

    const impacts = wrapper.findAll("[data-impact-slot]");
    expect(impacts.map((impact) => impact.attributes("data-impact-status"))).toEqual([
      "model_unavailable",
      "ready",
      "configured",
    ]);
    expect(impacts[0]!.text()).toContain("Zebra games");
    expect(impacts[0]!.text()).toContain("Choose an available model");
    expect(impacts[1]!.text()).toContain("General assistant");
    expect(impacts[2]!.text()).toContain("Configuration saved");
    expect(impacts[2]!.text()).toContain("no provider charge occurs");
  });

  it("renders honest empty states for models, workspaces, and local search", async () => {
    const { wrapper } = mountDetail({
      models: [],
      workspace_assignments: [],
    });

    expect(wrapper.get("#provider-models").text()).toContain("does not currently support a model");
    expect(wrapper.get("#provider-workspaces").text()).toContain(
      "do not currently have an eligible workspace",
    );
    expect(wrapper.find("#workspace-assignment-search").exists()).toBe(false);

    await wrapper.setProps({ card: detail() });
    await wrapper.get("#workspace-assignment-search").setValue("No matching workspace");

    expect(wrapper.get("#provider-workspaces").text()).toContain("No workspaces match this search");
  });

  it("connects an available provider from its detail screen", async () => {
    const { live, wrapper } = mountDetail({
      integration_id: null,
      status: "not_connected",
      key_last_four: null,
      connected_at: null,
      last_validated_at: null,
      workspace_assignments: [],
    });

    expect(wrapper.find("#provider-workspaces").exists()).toBe(false);
    await wrapper.get("#connect-provider").trigger("click");

    const dialog = wrapper.getComponent(ConnectKeyDialogStub);
    expect(dialog.props("mode")).toBe("connect");

    await dialog.vm.$emit("submit", "sk-new", vi.fn());

    const pushEventMock = live.pushEvent as unknown as {
      mock: { calls: [string, unknown, ReplyCallback][] };
    };

    expect(pushEventMock.mock.calls[0]![0]).toBe("connect");
    expect(pushEventMock.mock.calls[0]![1]).toEqual({
      provider: "openai",
      api_key: "sk-new",
    });
  });
});
