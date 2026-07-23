import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it } from "vitest";
import { defineComponent, type App } from "vue";
import AccountSettingsIntegrations from "../../../../live/account/settings/AccountSettingsIntegrations.vue";
import type { IntegrationCardData } from "../../../../live/account/settings/integrations/IntegrationCard.vue";
import type { LiveInterface } from "../../../../shared/composables/useLive";
import { createMockLive, setTestLocale } from "../../../setup";

type ReplyCallback = (reply: { status?: string; error?: string }) => void;

const IntegrationCardStub = defineComponent({
  name: "IntegrationCard",
  props: { card: { type: Object, required: true } },
  emits: ["connect", "disconnect", "toggle-workspace"],
  template: `<div :data-testid="'card-' + card.provider" />`,
});

const ConnectKeyDialogStub = defineComponent({
  name: "ConnectKeyDialog",
  props: {
    open: { type: Boolean, required: true },
    card: { type: Object, required: true },
    submitting: { type: Boolean, default: false },
  },
  emits: ["submit", "cancel"],
  template: `<div data-testid="connect-dialog" :data-provider="card.provider" />`,
});

const ConfirmDialogStub = defineComponent({
  name: "ConfirmDialog",
  props: {
    open: { type: Boolean, required: true },
    title: { type: String, default: "" },
    description: { type: String, default: "" },
    confirmText: { type: String, default: "" },
    cancelText: { type: String, default: "" },
    variant: { type: String, default: "default" },
  },
  emits: ["confirm", "cancel", "update:open"],
  template: `<div data-testid="confirm-dialog" />`,
});

function card(provider: string): IntegrationCardData {
  return {
    integration_id: null,
    provider,
    name: provider,
    key_generation_url: `https://example.com/${provider}/keys`,
    docs_url: `https://example.com/${provider}/docs`,
    key_placeholder: "sk-...",
    status: "not_connected",
    account_email: null,
    account_display_name: null,
    key_last_four: null,
    connected_at: null,
    catalog_status: "connection_only",
    models: [],
    workspace_assignments: [],
  };
}

function livePlugin(live: LiveInterface) {
  return {
    install(app: App) {
      app.config.globalProperties.$live = live;
    },
  };
}

function mountPage() {
  const live = createMockLive();
  const wrapper = mount(AccountSettingsIntegrations, {
    props: { cards: [card("anthropic"), card("openai")] },
    global: {
      plugins: [livePlugin(live)],
      provide: { _live_vue: live },
      stubs: {
        IntegrationCard: IntegrationCardStub,
        ConnectKeyDialog: ConnectKeyDialogStub,
        ConfirmDialog: ConfirmDialogStub,
      },
    },
  });

  return { live, wrapper };
}

describe("AccountSettingsIntegrations", () => {
  beforeEach(() => {
    setTestLocale("en");
  });

  it("opens the connect dialog for the card that emitted connect", async () => {
    const { wrapper } = mountPage();

    await wrapper.findAllComponents(IntegrationCardStub)[0]!.vm.$emit("connect");

    const dialog = wrapper.find('[data-testid="connect-dialog"]');
    expect(dialog.exists()).toBe(true);
    expect(dialog.attributes("data-provider")).toBe("anthropic");
  });

  it("ignores a stale connect reply after cancel + reopening for another provider", async () => {
    const { live, wrapper } = mountPage();
    const cards = wrapper.findAllComponents(IntegrationCardStub);

    // Open and submit for anthropic — reply intentionally not delivered yet.
    await cards[0]!.vm.$emit("connect");
    await wrapper
      .findComponent(ConnectKeyDialogStub)
      .vm.$emit("submit", "sk-ant-first", () => undefined);

    const pushEventMock = live.pushEvent as unknown as {
      mock: { calls: [string, unknown, ReplyCallback][] };
    };
    const staleReply = pushEventMock.mock.calls[0]![2];

    // Cancel the pending dialog, then open a fresh one for openai.
    await wrapper.findComponent(ConnectKeyDialogStub).vm.$emit("cancel");
    await cards[1]!.vm.$emit("connect");

    // The late success reply from the first request must not close it.
    staleReply({ status: "ok" });
    await wrapper.vm.$nextTick();

    const dialog = wrapper.find('[data-testid="connect-dialog"]');
    expect(dialog.exists()).toBe(true);
    expect(dialog.attributes("data-provider")).toBe("openai");
  });

  it("closes the dialog when the current request succeeds", async () => {
    const { live, wrapper } = mountPage();

    await wrapper.findAllComponents(IntegrationCardStub)[0]!.vm.$emit("connect");
    await wrapper
      .findComponent(ConnectKeyDialogStub)
      .vm.$emit("submit", "sk-ant-valid", () => undefined);

    const pushEventMock = live.pushEvent as unknown as {
      mock: { calls: [string, unknown, ReplyCallback][] };
    };
    pushEventMock.mock.calls[0]![2]({ status: "ok" });
    await wrapper.vm.$nextTick();

    expect(wrapper.find('[data-testid="connect-dialog"]').exists()).toBe(false);
  });

  it("assigns and unassigns the connected provider for the selected workspace", async () => {
    const { live, wrapper } = mountPage();
    const connected = card("openai");
    connected.integration_id = 42;
    connected.status = "connected";
    connected.workspace_assignments = [
      {
        workspace_id: 9,
        workspace_name: "Narrative team",
        workspace_slug: "narrative-team",
        role: "owner",
        assigned: false,
        assignment_id: null,
        can_assign: true,
        state: "available",
        reason: "owner_allowed",
      },
    ];

    await wrapper.setProps({ cards: [card("anthropic"), connected] });

    const openaiCard = wrapper.findAllComponents(IntegrationCardStub)[1]!;
    await openaiCard.vm.$emit("toggle-workspace", connected.workspace_assignments[0]);

    const pushEventMock = live.pushEvent as unknown as {
      mock: { calls: [string, unknown, ReplyCallback][] };
    };

    expect(pushEventMock.mock.calls[0]![0]).toBe("assign_workspace");
    expect(pushEventMock.mock.calls[0]![1]).toEqual({
      integration_id: 42,
      workspace_id: 9,
    });

    pushEventMock.mock.calls[0]![2]({ status: "ok" });

    connected.workspace_assignments[0] = {
      ...connected.workspace_assignments[0]!,
      assigned: true,
      assignment_id: 81,
      state: "assigned",
    };
    await wrapper.setProps({ cards: [card("anthropic"), { ...connected }] });
    await wrapper
      .findAllComponents(IntegrationCardStub)[1]!
      .vm.$emit("toggle-workspace", connected.workspace_assignments[0]);

    expect(pushEventMock.mock.calls[1]![0]).toBe("unassign_workspace");
    expect(pushEventMock.mock.calls[1]![1]).toEqual({
      integration_id: 42,
      workspace_id: 9,
    });
  });
});
