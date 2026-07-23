import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it } from "vitest";
import { defineComponent, type App } from "vue";
import MyAITeam from "../../../../live/account/settings/MyAITeam.vue";
import type { PreferenceSlotData } from "../../../../live/account/settings/integrations/PreferenceCard.vue";
import type { LiveInterface } from "../../../../shared/composables/useLive";
import { createMockLive, setTestLocale } from "../../../setup";

type ReplyCallback = (reply: { status?: string; error?: string }) => void;

const PreferenceCardStub = defineComponent({
  name: "PreferenceCard",
  props: {
    slotData: { type: Object, required: true },
    pending: { type: Boolean, default: false },
    disabled: { type: Boolean, default: false },
  },
  emits: ["save", "remove"],
  template: `<div
    :data-testid="'slot-' + slotData.slot"
    :data-pending="pending"
    :data-disabled="disabled"
  />`,
});

function option() {
  return {
    integration_id: 42,
    assignment_id: 9,
    provider: "openai",
    provider_name: "OpenAI",
    model: "personal-deterministic-v1",
    capabilities: ["suggestions", "tasks"],
    implementation_status: "executable" as const,
    payer: "personal_provider_account" as const,
  };
}

function slots(): PreferenceSlotData[] {
  return [
    {
      slot: "general_assistant",
      kind: "role",
      required_capabilities: ["tasks"],
      preference: null,
      options: [option()],
    },
    {
      slot: "writing_assistant",
      kind: "role",
      required_capabilities: ["suggestions"],
      preference: null,
      options: [option()],
    },
    {
      slot: "illustrator",
      kind: "role",
      required_capabilities: ["images"],
      preference: null,
      options: [],
    },
    {
      slot: "voice",
      kind: "role",
      required_capabilities: ["speech"],
      preference: null,
      options: [],
    },
  ];
}

function livePlugin(live: LiveInterface) {
  return {
    install(app: App) {
      app.config.globalProperties.$live = live;
    },
  };
}

function mountPage(policyAllowed = true, pageSlots = slots()) {
  const live = createMockLive();
  const wrapper = mount(MyAITeam, {
    props: {
      workspace: { id: 7, name: "Narrative team", slug: "narrative-team" },
      policyAllowed,
      slots: pageSlots,
      providersPath: "/users/settings/integrations?sudo_grant=valid",
      overviewPath: "/users/settings/ai-team?sudo_grant=valid",
    },
    global: {
      plugins: [livePlugin(live)],
      provide: { _live_vue: live },
      stubs: {
        PreferenceCard: PreferenceCardStub,
      },
    },
  });

  return { live, wrapper };
}

describe("MyAITeam", () => {
  beforeEach(() => {
    setTestLocale("en");
  });

  it("renders the four workspace-scoped roles without a workspace switch", () => {
    const { live, wrapper } = mountPage();

    expect(wrapper.findAllComponents(PreferenceCardStub)).toHaveLength(4);
    expect(wrapper.find('[data-testid="slot-general_assistant"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="slot-writing_assistant"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="slot-illustrator"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="slot-voice"]').exists()).toBe(true);
    expect(wrapper.text()).not.toContain("Default personal AI");
    expect(wrapper.find("#ai-integrations-subnav").exists()).toBe(false);
    expect(wrapper.find("#ai-team-workspace-selector").exists()).toBe(false);
    expect(live.pushEvent).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain("only offered as an explicit continuation");
  });

  it("links back to account-level provider connections", () => {
    const { wrapper } = mountPage();

    expect(wrapper.get("#manage-ai-integrations").attributes("href")).toBe(
      "/users/settings/integrations?sudo_grant=valid",
    );
    expect(wrapper.text()).toContain("can be reused in other workspaces with different models");
  });

  it("presents the workspace editor as a detail of the all-workspaces overview", () => {
    const { wrapper } = mountPage();

    expect(wrapper.get("#back-to-ai-team-overview").attributes("href")).toBe(
      "/users/settings/ai-team?sudo_grant=valid",
    );
    expect(wrapper.get("h1").text()).toBe("Configure Narrative team");
  });

  it("sends the chosen primary provider and model for one role", async () => {
    const { live, wrapper } = mountPage();

    await wrapper
      .findAllComponents(PreferenceCardStub)
      .find((component) => component.props("slotData").slot === "writing_assistant")!
      .vm.$emit("save", {
        slot: "writing_assistant",
        integration_id: 42,
        model: "personal-deterministic-v1",
      });

    const pushEventMock = live.pushEvent as unknown as {
      mock: { calls: [string, unknown, ReplyCallback][] };
    };

    expect(pushEventMock.mock.calls[0]![0]).toBe("save_preference");
    expect(pushEventMock.mock.calls[0]![1]).toEqual({
      slot: "writing_assistant",
      integration_id: 42,
      model: "personal-deterministic-v1",
    });
    expect(
      wrapper
        .findAllComponents(PreferenceCardStub)
        .find((component) => component.props("slotData").slot === "writing_assistant")!
        .props("pending"),
    ).toBe(true);

    pushEventMock.mock.calls[0]![2]({ status: "ok" });
    await wrapper.vm.$nextTick();

    expect(
      wrapper
        .findAllComponents(PreferenceCardStub)
        .find((component) => component.props("slotData").slot === "writing_assistant")!
        .props("pending"),
    ).toBe(false);
  });

  it("removes only the selected role configuration", async () => {
    const { live, wrapper } = mountPage();

    await wrapper
      .findAllComponents(PreferenceCardStub)
      .find((component) => component.props("slotData").slot === "voice")!
      .vm.$emit("remove", "voice");

    const pushEventMock = live.pushEvent as unknown as {
      mock: { calls: [string, unknown, ReplyCallback][] };
    };

    expect(pushEventMock.mock.calls[0]![0]).toBe("delete_preference");
    expect(pushEventMock.mock.calls[0]![1]).toEqual({ slot: "voice" });
  });

  it("tracks simultaneous mutations independently by role", async () => {
    const { live, wrapper } = mountPage();
    const cards = wrapper.findAllComponents(PreferenceCardStub);
    const general = cards.find(
      (component) => component.props("slotData").slot === "general_assistant",
    )!;
    const writing = cards.find(
      (component) => component.props("slotData").slot === "writing_assistant",
    )!;

    await general.vm.$emit("save", {
      slot: "general_assistant",
      integration_id: 42,
      model: "personal-deterministic-v1",
    });
    await writing.vm.$emit("save", {
      slot: "writing_assistant",
      integration_id: 42,
      model: "personal-deterministic-v1",
    });

    const pushEventMock = live.pushEvent as unknown as {
      mock: { calls: [string, unknown, ReplyCallback][] };
    };

    expect(general.props("pending")).toBe(true);
    expect(writing.props("pending")).toBe(true);

    pushEventMock.mock.calls[0]![2]({ status: "ok" });
    await wrapper.vm.$nextTick();

    expect(general.props("pending")).toBe(false);
    expect(writing.props("pending")).toBe(true);

    pushEventMock.mock.calls[1]![2]({ status: "ok" });
    await wrapper.vm.$nextTick();

    expect(writing.props("pending")).toBe(false);
  });

  it("keeps repairable roles visible but disables configuration when workspace policy blocks AI", () => {
    const { wrapper } = mountPage(false);

    expect(wrapper.find("#ai-team-policy-warning").exists()).toBe(true);
    expect(wrapper.findAllComponents(PreferenceCardStub)).toHaveLength(4);
    expect(
      wrapper
        .findAllComponents(PreferenceCardStub)
        .every((component) => component.props("disabled") === true),
    ).toBe(true);
  });

  it("renders an informative empty state when no role definitions are available", () => {
    const { wrapper } = mountPage(true, []);

    expect(wrapper.findAllComponents(PreferenceCardStub)).toHaveLength(0);
    expect(wrapper.text()).toContain("No configurable AI roles are available yet");
  });
});
