import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it } from "vitest";
import PreferenceCard, {
  type PreferenceSlotData,
} from "../../../../live/account/settings/integrations/PreferenceCard.vue";
import PreferenceCombobox from "../../../../live/account/settings/integrations/PreferenceCombobox.vue";
import { setTestLocale } from "../../../setup";

function slot(overrides: Partial<PreferenceSlotData> = {}): PreferenceSlotData {
  return {
    slot: "writing_assistant",
    kind: "role",
    required_capabilities: ["suggestions"],
    preference: null,
    options: [
      {
        integration_id: 42,
        assignment_id: 8,
        provider: "openai",
        provider_name: "OpenAI",
        model: "personal-deterministic-v1",
        capabilities: ["suggestions", "tasks"],
        implementation_status: "executable",
        payer: "personal_provider_account",
      },
    ],
    ...overrides,
  };
}

describe("PreferenceCard", () => {
  beforeEach(() => {
    setTestLocale("en");
  });

  it("renders separate provider and model selectors", () => {
    const wrapper = mount(PreferenceCard, { props: { slotData: slot() } });

    expect(wrapper.find("#preference-provider-writing_assistant").exists()).toBe(true);
    expect(wrapper.find("#preference-model-writing_assistant").exists()).toBe(true);
    expect(wrapper.findAllComponents(PreferenceCombobox)).toHaveLength(2);
    expect(wrapper.text()).toContain("Writing assistant");
    expect(wrapper.text()).toContain("Not configured");
    expect(wrapper.attributes("aria-labelledby")).toBe("preference-title-writing_assistant");
    expect(wrapper.attributes("aria-busy")).toBe("false");
  });

  it("shows personal billing and the active provider/model", () => {
    const wrapper = mount(PreferenceCard, {
      props: {
        slotData: slot({
          preference: {
            id: 11,
            slot: "writing_assistant",
            integration_id: 42,
            provider: "openai",
            provider_name: "OpenAI",
            model: "personal-deterministic-v1",
            implementation_status: "executable",
            status: "ready",
            payer: "personal_provider_account",
          },
        }),
      },
    });

    expect(wrapper.text()).toContain("Primary: OpenAI · personal-deterministic-v1");
    expect(wrapper.text()).toContain("your key");
    expect(wrapper.text()).toContain("provider bills your account directly");
    expect(wrapper.attributes("data-preference-status")).toBe("ready");
  });

  it("keeps a broken preference visible with a repair explanation", async () => {
    const wrapper = mount(PreferenceCard, {
      props: {
        slotData: slot({
          preference: {
            id: 11,
            slot: "writing_assistant",
            integration_id: 42,
            provider: "openai",
            provider_name: "OpenAI",
            model: "retired-model",
            implementation_status: null,
            status: "model_deprecated",
            payer: "personal_provider_account",
          },
        }),
      },
    });

    expect(wrapper.text()).toContain("Model deprecated");
    expect(wrapper.text()).toContain("can no longer be selected");

    await wrapper
      .get('button[aria-label="Remove the Writing assistant configuration"]')
      .trigger("click");
    expect(wrapper.emitted("remove")).toEqual([["writing_assistant"]]);
  });

  it("keeps future roles visible when no executable model exists", () => {
    const wrapper = mount(PreferenceCard, {
      props: {
        slotData: slot({
          slot: "voice",
          required_capabilities: ["speech"],
          options: [],
        }),
      },
    });

    expect(wrapper.text()).toContain("Voice");
    expect(wrapper.text()).toContain("No connection with a supported model is enabled");
    expect(wrapper.get("#preference-provider-voice").attributes()).toHaveProperty("disabled");
  });

  it("renders the general assistant as a distinct configurable role", () => {
    const wrapper = mount(PreferenceCard, {
      props: {
        slotData: slot({
          slot: "general_assistant",
          required_capabilities: ["tasks"],
        }),
      },
    });

    expect(wrapper.text()).toContain("General assistant");
    expect(wrapper.text()).toContain("launched from the command palette");
    expect(wrapper.find("#preference-provider-general_assistant").exists()).toBe(true);
    expect(wrapper.find("#preference-model-general_assistant").exists()).toBe(true);
  });

  it.each([
    {
      role: "illustrator" as const,
      capability: "images",
      model: "gpt-image-2",
    },
    {
      role: "voice" as const,
      capability: "speech",
      model: "tts-1",
    },
  ])(
    "allows saving a configuration-only $role model with honest execution copy",
    async ({ role, capability, model }) => {
      const wrapper = mount(PreferenceCard, {
        props: {
          slotData: slot({
            slot: role,
            required_capabilities: [capability],
            options: [
              {
                integration_id: 42,
                assignment_id: 8,
                provider: "openai",
                provider_name: "OpenAI",
                model,
                capabilities: [capability],
                implementation_status: "configuration_only",
                payer: "personal_provider_account",
              },
            ],
          }),
        },
      });

      const comboboxes = wrapper.findAllComponents(PreferenceCombobox);
      await comboboxes[0]!.vm.$emit("update:modelValue", "42");
      await wrapper.vm.$nextTick();

      const availabilityNotice = wrapper.get(
        '[data-selected-implementation-status="configuration_only"]',
      );
      expect(availabilityNotice.text()).toContain("Storyarn cannot execute this role yet");
      expect(availabilityNotice.text()).toContain("no provider charge occurs");

      const saveButton = wrapper
        .findAll("button")
        .find((button) => button.text().includes("Set primary"));

      expect(saveButton?.attributes()).not.toHaveProperty("disabled");
      expect(saveButton?.attributes("aria-describedby")).toBe(`configuration-only-help-${role}`);
      await saveButton!.trigger("click");
      expect(wrapper.emitted("save")).toEqual([
        [
          {
            slot: role,
            integration_id: 42,
            model,
          },
        ],
      ]);
    },
  );

  it("describes a valid configuration-only preference as configured, not broken", () => {
    const wrapper = mount(PreferenceCard, {
      props: {
        slotData: slot({
          slot: "voice",
          required_capabilities: ["speech"],
          preference: {
            id: 12,
            slot: "voice",
            integration_id: 42,
            provider: "openai",
            provider_name: "OpenAI",
            model: "tts-1",
            implementation_status: "configuration_only",
            status: "configured",
            payer: "personal_provider_account",
          },
          options: [
            {
              integration_id: 42,
              assignment_id: 8,
              provider: "openai",
              provider_name: "OpenAI",
              model: "tts-1",
              capabilities: ["speech"],
              implementation_status: "configuration_only",
              payer: "personal_provider_account",
            },
          ],
        }),
      },
    });

    expect(wrapper.attributes("data-preference-status")).toBe("configured");
    expect(wrapper.get("[data-configuration-only-preference]").text()).toContain(
      "Configuration saved",
    );
    expect(wrapper.get("[data-configuration-only-preference]").text()).toContain(
      "no provider charge occurs",
    );
    expect(wrapper.text()).not.toContain("provider bills your account directly");
    expect(wrapper.text()).not.toContain("Choose an available model");
  });

  it("disables role editing when workspace policy blocks personal AI", () => {
    const wrapper = mount(PreferenceCard, {
      props: {
        slotData: slot(),
        disabled: true,
      },
    });

    expect(wrapper.attributes("data-policy-disabled")).toBe("true");
    expect(wrapper.get("#preference-provider-writing_assistant").attributes()).toHaveProperty(
      "disabled",
    );
    expect(wrapper.get("#preference-model-writing_assistant").attributes()).toHaveProperty(
      "disabled",
    );
  });
});
