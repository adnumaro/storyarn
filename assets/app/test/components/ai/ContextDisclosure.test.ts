import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it } from "vitest";
import ContextDisclosure, {
  type ContextDisclosureData,
} from "../../../components/ai/ContextDisclosure.vue";
import { setTestLocale } from "../../setup";

function disclosure(overrides: Partial<ContextDisclosureData> = {}): ContextDisclosureData {
  return {
    version: "storyarn-context-v1",
    context_version: "sheet-context-v1",
    scope: "sheet",
    serialized_bytes: 2_560,
    token_count: 640,
    included_count: 4,
    excluded_count: 0,
    truncated: false,
    warnings: [],
    ...overrides,
  };
}

describe("ContextDisclosure", () => {
  beforeEach(() => {
    setTestLocale("en");
  });

  it("shows a compact complete-context summary and deterministic details", async () => {
    const wrapper = mount(ContextDisclosure, {
      props: { disclosure: disclosure() },
    });

    expect(wrapper.text()).toContain("Context sent to AI");
    expect(wrapper.text()).toContain("Complete");
    expect(wrapper.text()).toContain("4 items · 2.5 KB");

    await wrapper.get('[data-testid="ai-context-disclosure-trigger"]').trigger("click");

    expect(wrapper.text()).toContain("Sheet");
    expect(wrapper.text()).toContain("640");
    expect(wrapper.find('[data-testid="ai-context-disclosure-warnings"]').exists()).toBe(false);
  });

  it("makes truncation and stale-reference warnings explicit", async () => {
    const wrapper = mount(ContextDisclosure, {
      props: {
        disclosure: disclosure({
          excluded_count: 3,
          truncated: true,
          warnings: ["optional_context_truncated", "stale_reference"],
        }),
      },
    });

    expect(wrapper.text()).toContain("Limited");
    await wrapper.get('[data-testid="ai-context-disclosure-trigger"]').trigger("click");

    const warnings = wrapper.get('[data-testid="ai-context-disclosure-warnings"]').text();
    expect(warnings).toContain("Some optional context was omitted");
    expect(warnings).toContain("Some referenced content no longer exists");
  });
});
