import { mount } from "@vue/test-utils";
import { nextTick } from "vue";
import { afterEach, describe, expect, it, vi } from "vitest";
import LocalizationTextsIndex from "../../../live/localization/texts/LocalizationTextsIndex.vue";
import { createMockLive } from "../../setup";

const selectedText = {
  id: 1,
  sourceType: "flow_node",
  sourceTypeLabel: "Flow node",
  sourceField: "text",
  sourceReference: "Opening",
  sourceHtml: "Hello {name}",
  sourceText: "Hello {name}",
  wordCount: 2,
  localeCode: "es",
  localeName: "Spanish",
  translatedText: "",
  status: "pending",
  translatorNotes: "",
  voStatus: "none",
  voEligible: true,
  machineTranslated: false,
  lastTranslatedAt: null,
  stale: false,
  placeholders: ["{name}"],
  lockVersion: 1,
};

const texts = [
  {
    id: 1,
    sourceText: "Hello {name}",
    translatedText: null,
    status: "pending",
    statusLabel: "Pending",
    sourceType: "flow_node",
    sourceTypeLabel: "Flow node",
    sourceTypeIcon: "message-square",
    sourceField: "text",
    wordCount: 2,
    machineTranslated: false,
    stale: false,
    editUrl: "/texts/1",
  },
  {
    id: 2,
    sourceText: "Goodbye",
    translatedText: null,
    status: "pending",
    statusLabel: "Pending",
    sourceType: "flow_node",
    sourceTypeLabel: "Flow node",
    sourceTypeIcon: "message-square",
    sourceField: "text",
    wordCount: 1,
    machineTranslated: false,
    stale: false,
    editUrl: "/texts/2",
  },
];

function mountWorkbench() {
  const live = createMockLive();
  const wrapper = mount(LocalizationTextsIndex, {
    props: {
      texts,
      totalCount: texts.length,
      selectedText,
      selectedLocaleName: "Spanish",
      capabilities: { canEdit: true, hasProvider: true, hasTargetLanguages: true },
    },
    global: {
      config: { globalProperties: { $live: live } as never },
      stubs: {
        DashboardContent: { template: "<div><slot /></div>" },
      },
    },
  });

  return { live, wrapper };
}

afterEach(() => {
  vi.useRealTimers();
});

describe("LocalizationTextsIndex", () => {
  it("preserves edits made while an autosave reply is in flight", async () => {
    vi.useFakeTimers();
    const callbacks: Array<(response: Record<string, unknown>) => void> = [];
    const { live, wrapper } = mountWorkbench();

    vi.mocked(live.pushEvent).mockImplementation((event, _payload, callback) => {
      if (event === "save_translation" && callback) callbacks.push(callback);
    });

    await nextTick();
    const editor = wrapper.get("#localization-translation-editor");
    await editor.setValue("Hola {name}");
    await vi.advanceTimersByTimeAsync(900);

    expect(callbacks).toHaveLength(1);
    await editor.setValue("Buenos días {name}");

    callbacks[0]({
      ok: true,
      text: { ...selectedText, translatedText: "Hola {name}", status: "draft", lockVersion: 2 },
    });
    await nextTick();

    expect((editor.element as HTMLTextAreaElement).value).toBe("Buenos días {name}");
    expect(live.pushEvent).toHaveBeenNthCalledWith(
      2,
      "save_translation",
      expect.objectContaining({
        lock_version: 2,
        localized_text: expect.objectContaining({ translated_text: "Buenos días {name}" }),
      }),
      expect.any(Function),
    );
  });

  it("saves the open editor before translating a different row", async () => {
    const callbacks: Array<(response: Record<string, unknown>) => void> = [];
    const { live, wrapper } = mountWorkbench();

    vi.mocked(live.pushEvent).mockImplementation((event, _payload, callback) => {
      if (event === "save_translation" && callback) callbacks.push(callback);
    });

    await nextTick();
    await wrapper.get("#localization-translation-editor").setValue("Hola {name}");

    await wrapper.get('[data-testid="localization-translate-2"]').trigger("click");

    expect(live.pushEvent).toHaveBeenCalledTimes(1);
    expect(live.pushEvent).toHaveBeenCalledWith(
      "save_translation",
      expect.objectContaining({ id: 1 }),
      expect.any(Function),
    );

    callbacks[0]({
      ok: true,
      text: { ...selectedText, translatedText: "Hola {name}", status: "draft", lockVersion: 2 },
    });
    await nextTick();

    expect(live.pushEvent).toHaveBeenLastCalledWith(
      "translate_single",
      { id: 2 },
      expect.any(Function),
    );
  });

  it("clears DeepL loading when placeholder validation blocks the prerequisite save", async () => {
    const { live, wrapper } = mountWorkbench();
    await nextTick();
    await wrapper.get("#localization-translation-editor").setValue("Hola");

    const translateButton = wrapper.get('[data-testid="localization-translate-2"]');
    await translateButton.trigger("click");
    await nextTick();

    expect(live.pushEvent).not.toHaveBeenCalled();
    expect(translateButton.attributes("disabled")).toBeUndefined();
  });
});
