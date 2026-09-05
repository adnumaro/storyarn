import { flushPromises, mount } from "@vue/test-utils";
import { nextTick } from "vue";
import { afterEach, describe, expect, it, vi } from "vitest";
import LocalizationTextsIndex from "../../../live/localization/texts/LocalizationTextsIndex.vue";
import type { SelectedText, TextRow } from "../../../modules/localization/domain/types";
import { createMockLive, createPromiseMockLive } from "../../setup";

const selectedText: SelectedText = {
  id: 1,
  sourceType: "flow_node",
  sourceTypeLabel: "Node",
  sourceField: "text",
  contentRole: "dialogue",
  contentRoleLabel: "Dialogue",
  speakerName: "Louise",
  sourceRef: { parent: "Harbor", label: "Opening", url: "/flows/1?node=9" },
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
  translatedBy: null,
  stale: false,
  placeholders: ["{name}"],
  glossaryHits: [],
  lockVersion: 1,
};

function row(id: number, sourceText: string): TextRow {
  return {
    id,
    sourceText,
    translatedText: null,
    status: "pending",
    statusLabel: "Pending",
    sourceType: "flow_node",
    sourceTypeLabel: "Node",
    sourceTypeIcon: "message-square",
    sourceField: "text",
    contentRole: "dialogue",
    contentRoleLabel: "Dialogue",
    speakerName: "Louise",
    voEligible: true,
    voStatus: "none",
    wordCount: 2,
    machineTranslated: false,
    stale: false,
    editUrl: `/texts/${id}`,
  };
}

const texts = [row(1, "Hello {name}"), row(2, "Goodbye")];

const languages = {
  current: {
    code: "es",
    name: "Spanish",
    flagCode: "es",
    shortLabel: "ES",
    wordCount: 3,
    sourceName: "English",
  },
  targets: [],
};

const progress = {
  total: 2,
  pending: 2,
  draft: 0,
  in_progress: 0,
  review: 0,
  final: 0,
  stale: 0,
};

function mountWorkbench(overrides: Record<string, unknown> = {}, live = createMockLive()) {
  const wrapper = mount(LocalizationTextsIndex, {
    props: {
      texts,
      totalCount: texts.length,
      progress,
      selectedText,
      languages,
      capabilities: { canEdit: true, hasProvider: true, hasTargetLanguages: true },
      ...overrides,
    },
    global: {
      config: { globalProperties: { $live: live } as never },
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
    expect(wrapper.get('[data-testid="localization-placeholder-status"]').text()).toContain(
      "{name} missing",
    );
  });

  it.each(["reply", "transport error"])(
    "clears DeepL loading when a prerequisite save is superseded by a newer save (%s)",
    async (outcome) => {
      vi.useFakeTimers();
      const saves: Array<{
        resolve: (response: Record<string, unknown>) => void;
        reject: (reason?: unknown) => void;
      }> = [];
      const pushEvent = vi.fn((event: unknown) => {
        if (event !== "save_translation") return Promise.resolve({});
        return new Promise<Record<string, unknown>>((resolve, reject) => {
          saves.push({ resolve, reject });
        });
      });
      const live = createPromiseMockLive({}, pushEvent);
      const { wrapper } = mountWorkbench({}, live);

      const consoleWarning = vi.spyOn(console, "warn").mockImplementation(() => undefined);

      await nextTick();
      const editor = wrapper.get("#localization-translation-editor");
      await editor.setValue("Hola {name}");
      await wrapper.get('[data-testid="localization-translate-2"]').trigger("click");
      expect(saves).toHaveLength(1);

      await wrapper.setProps({
        selectedText: {
          ...selectedText,
          id: 2,
          sourceText: "Goodbye",
          translatedText: "",
          placeholders: [],
        },
      });
      await nextTick();
      await editor.setValue("Adiós");
      await vi.advanceTimersByTimeAsync(900);
      expect(saves).toHaveLength(2);

      if (outcome === "reply") {
        saves[0].resolve({
          ok: true,
          text: { ...selectedText, translatedText: "Hola {name}", lockVersion: 2 },
        });
      } else {
        saves[0].reject(new Error("disconnected"));
      }
      await flushPromises();

      expect(wrapper.get('[data-testid="localization-translate-2"]').attributes("disabled")).toBe(
        undefined,
      );
      expect(wrapper.get('[data-testid="localization-save-state"]').text()).toBe("Saving…");
      expect(pushEvent).toHaveBeenCalledTimes(2);
      consoleWarning.mockRestore();
    },
  );

  it("loads the next page when Save & next runs past the loaded rows", async () => {
    const callbacks: Array<(response: Record<string, unknown>) => void> = [];
    const { live, wrapper } = mountWorkbench({
      selectedText: { ...selectedText, id: 2, sourceText: "Goodbye", placeholders: [] },
      pagination: { page: 1, pageSize: 2, hasMore: true },
    });

    vi.mocked(live.pushEvent).mockImplementation((event, _payload, callback) => {
      if (event === "save_translation" && callback) callbacks.push(callback);
    });

    await nextTick();
    await wrapper.get('[data-testid="localization-save-next"]').trigger("click");

    expect(callbacks).toHaveLength(1);
    callbacks[0]({ ok: true, text: { ...selectedText, id: 2, lockVersion: 2 } });
    await nextTick();

    expect(live.pushEvent).toHaveBeenLastCalledWith("load_more", {}, expect.any(Function));

    await wrapper.setProps({ texts: [...texts, row(3, "Third")] });
    await nextTick();

    expect(live.pushEvent).toHaveBeenLastCalledWith("select_text", { id: 3 }, undefined);
  });

  it("offers the next piece of work when nothing is selected", async () => {
    const { live, wrapper } = mountWorkbench({ selectedText: null });

    await wrapper.get('[data-testid="localization-next-pending"]').trigger("click");

    expect(live.pushEvent).toHaveBeenCalledWith("select_next", { kind: "pending" }, undefined);
  });

  it("toggles the summary tiles as list filters", async () => {
    const { live, wrapper } = mountWorkbench({
      selectedText: null,
      filters: {
        status: "",
        sourceType: "",
        voStatus: "",
        speaker: null,
        stale: false,
        search: "",
      },
    });

    const tiles = wrapper.findAll("button[aria-pressed]");
    await tiles[0].trigger("click");

    expect(live.pushEvent).toHaveBeenCalledWith(
      "change_filter",
      { status: "pending", stale: "false" },
      undefined,
    );
  });

  it("clears an active status when the Outdated tile is enabled", async () => {
    const { live, wrapper } = mountWorkbench({
      selectedText: null,
      filters: {
        status: "pending",
        sourceType: "",
        voStatus: "",
        speaker: null,
        stale: false,
        search: "",
      },
    });

    const tiles = wrapper.findAll("button[aria-pressed]");
    await tiles[2].trigger("click");

    expect(live.pushEvent).toHaveBeenCalledWith(
      "change_filter",
      { status: "", stale: "true" },
      undefined,
    );
  });

  it("ignores a save reply that arrives after another string was opened", async () => {
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

    await wrapper.setProps({
      selectedText: { ...selectedText, id: 2, sourceText: "Goodbye", translatedText: "Adiós" },
    });
    await nextTick();
    expect((editor.element as HTMLTextAreaElement).value).toBe("Adiós");

    callbacks[0]({
      ok: true,
      text: { ...selectedText, translatedText: "Hola {name}", status: "draft", lockVersion: 2 },
    });
    await nextTick();

    expect((editor.element as HTMLTextAreaElement).value).toBe("Adiós");
    expect(wrapper.get('[data-testid="localization-save-state"]').text()).toBe("All changes saved");
    expect(live.pushEvent).toHaveBeenCalledTimes(1);
  });

  it("opens the row clicked while a save is in flight once the save lands", async () => {
    vi.useFakeTimers();
    const callbacks: Array<(response: Record<string, unknown>) => void> = [];
    const { live, wrapper } = mountWorkbench();

    vi.mocked(live.pushEvent).mockImplementation((event, _payload, callback) => {
      if (event === "save_translation" && callback) callbacks.push(callback);
    });

    await nextTick();
    await wrapper.get("#localization-translation-editor").setValue("Hola {name}");
    await vi.advanceTimersByTimeAsync(900);
    expect(callbacks).toHaveLength(1);

    await wrapper.get('[data-row-id="2"]').trigger("click");
    expect(live.pushEvent).toHaveBeenCalledTimes(1);

    callbacks[0]({
      ok: true,
      text: { ...selectedText, translatedText: "Hola {name}", status: "draft", lockVersion: 2 },
    });
    await nextTick();

    expect(live.pushEvent).toHaveBeenLastCalledWith("select_text", { id: 2 }, undefined);
  });

  it("moves between rows with the arrow keys from the DeepL button too", async () => {
    const live = createMockLive();
    const wrapper = mount(LocalizationTextsIndex, {
      attachTo: document.body,
      props: {
        texts,
        totalCount: texts.length,
        progress,
        selectedText: null,
        languages,
        capabilities: { canEdit: true, hasProvider: true, hasTargetLanguages: true },
      },
      global: { config: { globalProperties: { $live: live } as never } },
    });

    (wrapper.get('[data-testid="localization-translate-1"]').element as HTMLElement).focus();
    await wrapper
      .get('[data-testid="localization-string-list"]')
      .trigger("keydown", { key: "ArrowDown" });

    expect(document.activeElement?.getAttribute("data-row-id")).toBe("2");
    wrapper.unmount();
  });

  it("disables the Outdated confirmation while placeholders are missing", async () => {
    const { wrapper } = mountWorkbench({ selectedText: { ...selectedText, stale: true } });
    await nextTick();

    const confirm = wrapper.get('[data-testid="localization-outdated-confirm"]');
    expect(confirm.attributes("disabled")).toBeUndefined();

    await wrapper.get("#localization-translation-editor").setValue("Hola");
    await nextTick();

    expect(confirm.attributes("disabled")).toBeDefined();
    expect(wrapper.get('[data-testid="localization-outdated-banner"]').text()).toContain(
      "Fix the placeholders first",
    );
  });

  it("ignores a machine-translation reply for a row that is no longer open", async () => {
    const callbacks: Array<(response: Record<string, unknown>) => void> = [];
    const { live, wrapper } = mountWorkbench();

    vi.mocked(live.pushEvent).mockImplementation((event, _payload, callback) => {
      if (event === "translate_single" && callback) callbacks.push(callback);
    });

    await nextTick();
    await wrapper.get('[data-testid="localization-translate-2"]').trigger("click");
    expect(callbacks).toHaveLength(1);

    await wrapper.setProps({
      selectedText: { ...selectedText, id: 3, sourceText: "Third", translatedText: "Tercero" },
    });
    await nextTick();

    callbacks[0]({
      ok: true,
      text: { ...selectedText, id: 2, translatedText: "Adiós (machine)", status: "draft" },
    });
    await nextTick();

    const editor = wrapper.get("#localization-translation-editor");
    expect((editor.element as HTMLTextAreaElement).value).toBe("Tercero");
    expect(wrapper.get('[data-testid="localization-save-state"]').text()).toBe("All changes saved");
  });

  it("ignores a machine-translation reply from an earlier opening of the same row", async () => {
    const callbacks: Array<(response: Record<string, unknown>) => void> = [];
    const { live, wrapper } = mountWorkbench();

    vi.mocked(live.pushEvent).mockImplementation((event, _payload, callback) => {
      if (event === "translate_single" && callback) callbacks.push(callback);
    });

    await nextTick();
    await wrapper.get('[data-testid="localization-translate-1"]').trigger("click");
    expect(callbacks).toHaveLength(1);

    await wrapper.setProps({
      selectedText: {
        ...selectedText,
        id: 2,
        sourceText: "Goodbye",
        translatedText: "Adiós",
        placeholders: [],
      },
    });
    await nextTick();
    await wrapper.setProps({ selectedText: { ...selectedText, translatedText: "Hola anterior" } });
    await nextTick();

    const editor = wrapper.get("#localization-translation-editor");
    await editor.setValue("Edición nueva {name}");

    const staleTranslation = {
      ...selectedText,
      translatedText: "Traducción automática {name}",
      status: "draft",
    };
    await wrapper.setProps({ selectedText: staleTranslation });
    await nextTick();
    callbacks[0]({ ok: true, text: staleTranslation });
    await nextTick();

    expect((editor.element as HTMLTextAreaElement).value).toBe("Edición nueva {name}");
    expect(wrapper.get('[data-testid="localization-translate-1"]').attributes("disabled")).toBe(
      undefined,
    );
  });

  it("lets a newer save own the state when an older reply arrives late", async () => {
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

    // The server moves the selection while the first save is in flight and
    // the translator keeps typing on the new row.
    await wrapper.setProps({
      selectedText: { ...selectedText, id: 2, sourceText: "Goodbye", placeholders: [] },
    });
    await nextTick();
    await editor.setValue("Adiós");
    await vi.advanceTimersByTimeAsync(900);
    expect(callbacks).toHaveLength(2);

    await wrapper.get('[data-row-id="1"]').trigger("click");

    callbacks[0]({
      ok: true,
      text: { ...selectedText, translatedText: "Hola {name}", lockVersion: 2 },
    });
    await nextTick();
    expect(wrapper.get('[data-testid="localization-save-state"]').text()).toBe("Saving…");
    expect(live.pushEvent).toHaveBeenCalledTimes(2);

    callbacks[1]({
      ok: true,
      text: { ...selectedText, id: 2, translatedText: "Adiós", placeholders: [], lockVersion: 2 },
    });
    await nextTick();

    expect(live.pushEvent).toHaveBeenLastCalledWith("select_text", { id: 1 }, undefined);
  });
});
