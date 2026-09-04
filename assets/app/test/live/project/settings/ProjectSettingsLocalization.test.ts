import { mount } from "@vue/test-utils";
import { nextTick } from "vue";
import { describe, expect, it, vi } from "vitest";
import ProjectSettingsLocalization from "../../../../live/project/settings/ProjectSettingsLocalization.vue";
import { createMockLive } from "../../../setup";

function mountLocalization(props = {}, live = createMockLive()) {
  const wrapper = mount(ProjectSettingsLocalization, {
    props: {
      providerApiEndpoint: "https://api-free.deepl.com",
      hasApiKey: false,
      providerUsage: null,
      ...props,
    },
    global: { provide: { _live_vue: live } },
  });

  return { live, wrapper };
}

describe("ProjectSettingsLocalization", () => {
  it("saves the provider key and endpoint through the form", async () => {
    const { live, wrapper } = mountLocalization();

    expect(wrapper.text()).toContain("Setup required");
    expect(wrapper.find('[data-testid="localization-test-connection"]').exists()).toBe(false);

    await wrapper.get("#api-key").setValue("deepl-secret");
    await wrapper.get("form").trigger("submit");

    const [event, payload, complete] = vi.mocked(live.pushEvent).mock.calls[0];
    expect(event).toBe("save_provider_config");
    expect(payload).toEqual({
      provider: { api_key_encrypted: "deepl-secret", api_endpoint: "https://api-free.deepl.com" },
    });
    expect(
      wrapper.get('[data-testid="localization-save-provider"]').attributes("disabled"),
    ).toBeDefined();

    complete?.({ ok: true });
    await nextTick();

    expect(wrapper.get<HTMLInputElement>("#api-key").element.value).toBe("");
    expect(
      wrapper.get('[data-testid="localization-save-provider"]').attributes("disabled"),
    ).toBeUndefined();
  });

  it("tests the connection and renders the reported usage as a meter", async () => {
    const { live, wrapper } = mountLocalization({ hasApiKey: true });

    expect(wrapper.text()).toContain("Configured");
    await wrapper.get('[data-testid="localization-test-connection"]').trigger("click");

    const [event, , complete] = vi.mocked(live.pushEvent).mock.calls[0];
    expect(event).toBe("test_provider_connection");

    complete?.({ ok: true, usage: { characterCount: 450000, characterLimit: 500000 } });
    await nextTick();

    expect(wrapper.get('[data-testid="localization-connection-status"]').text()).toContain(
      "Connection successful",
    );
    const meter = wrapper.get('[data-testid="localization-usage-meter"]');
    expect(meter.text()).toContain("450,000");
    expect(meter.text()).toContain("500,000");
    expect(meter.attributes("data-meter-status")).toBe("warning");
    meter.get('[role="progressbar"]');
  });

  it("explains a failed connection test", async () => {
    const { live, wrapper } = mountLocalization({ hasApiKey: true });

    await wrapper.get('[data-testid="localization-test-connection"]').trigger("click");
    const [, , complete] = vi.mocked(live.pushEvent).mock.calls[0];
    complete?.({ ok: false, error: "Forbidden" });
    await nextTick();

    expect(wrapper.get('[data-testid="localization-connection-status"]').text()).toContain(
      "DeepL connection failed: Forbidden",
    );
    expect(wrapper.find('[data-testid="localization-usage-meter"]').exists()).toBe(false);
  });
});
