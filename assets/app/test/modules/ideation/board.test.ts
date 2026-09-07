import { afterEach, describe, expect, it, vi } from "vitest";
import { flushPromises, mount } from "@vue/test-utils";
import { pasteContent } from "@modules/ideation/lib/paste";
import IdeasCollection from "@modules/ideation/components/IdeasCollection.vue";
import IdeaComposer from "@modules/ideation/components/IdeaComposer.vue";
import IdeaEditor from "@modules/ideation/components/IdeaEditor.vue";
import RevealDialog from "@modules/ideation/components/RevealDialog.vue";
import type { Request } from "@modules/ideation/types";
import { board, idea } from "./fixtures";
import { setTestLocale } from "../../setup";

afterEach(() => {
  setTestLocale("en");
  document.body.innerHTML = "";
});
const dialogStubs = {
  Dialog: { template: "<div><slot /></div>" },
  DialogContent: { template: "<div><slot /></div>" },
  DialogTitle: { template: "<h2><slot /></h2>" },
  DialogDescription: { template: "<p><slot /></p>" },
};

it("keeps script text inert and strips every pasted attribute including adjacent attributes", async () => {
  const html = pasteContent(
    '<p class="x" style="color:red" onclick="alert(1)">Hi<script>alert(1)</script><a href="javascript:alert(1)">link</a></p>',
  );
  expect(html).toBe("<p>Hialert(1)link</p>");
  const wrapper = mount(IdeaEditor, { props: { value: html, readonly: true, label: "Text" } });
  await flushPromises();
  expect(wrapper.find("script").exists()).toBe(false);
  expect(wrapper.text()).toContain("alert(1)");
  wrapper.unmount();
});

it("offers the same cards and keyboard actions in list view, with localized page search", async () => {
  setTestLocale("es");
  const wrapper = mount(IdeasCollection, { props: { board: board(), selectedId: null } });
  expect(wrapper.text()).toContain("A motive");
  await wrapper.get('[aria-label="Lista"]').trigger("click");
  expect(wrapper.get("#idea-card-10").element.tagName).toBe("BUTTON");
  await wrapper.get("#idea-card-10").trigger("click");
  expect(wrapper.emitted("select")?.[0]).toEqual([idea()]);
  await wrapper.get('input[aria-label="Buscar en esta página…"]').setValue("missing");
  expect(wrapper.find("#idea-card-10").exists()).toBe(false);
  expect(wrapper.text()).toContain("No hay ideas que coincidan");
  wrapper.unmount();
});

describe("publication", () => {
  it("requires a count confirmation, freezes the request and defaults to excluding discarded ideas", async () => {
    const request = vi
      .fn()
      .mockResolvedValueOnce({ status: "ok", value: { id: 9, count: 2, status: "prepared" } })
      .mockResolvedValueOnce({ status: "error", code: "offline" })
      .mockResolvedValue({ status: "ok", value: { id: 9, count: 2, status: "completed" } });
    const wrapper = mount(RevealDialog, {
      props: { request: request as Request, context: { epoch: "one", session_id: 1 } },
      global: { stubs: dialogStubs },
    });
    const submit = () =>
      wrapper
        .findAll("button")
        .find((button) => /Review selection|Confirm publication/.test(button.text()))!
        .trigger("click");
    expect((wrapper.get('input[type="checkbox"]').element as HTMLInputElement).checked).toBe(false);
    await submit();
    await flushPromises();
    expect(request.mock.calls[0][1]).toMatchObject({ mode: "eligible", include_discarded: false });
    expect(wrapper.text()).toContain("2 revisions ready to publish");
    expect(request).toHaveBeenCalledTimes(1);
    await submit();
    await flushPromises();
    await submit();
    await flushPromises();
    expect(request.mock.calls[2]).toEqual(request.mock.calls[1]);
    expect(wrapper.emitted("published")).toHaveLength(1);
    wrapper.unmount();
  });
});

it("freezes the contribution configuration and reuses uncertain creation requests", async () => {
  const request = vi
    .fn()
    .mockResolvedValueOnce({ status: "error", code: "offline" })
    .mockResolvedValueOnce({ status: "ok", value: idea() });
  const initial = board().session!;
  const wrapper = mount(IdeaComposer, {
    props: {
      session: initial,
      context: { epoch: "one", session_id: 1 },
      request: request as Request,
    },
    global: { stubs: dialogStubs },
  });
  await wrapper.get("#new-idea-title").setValue("An idea");
  wrapper.getComponent(IdeaEditor).vm.$emit("change", "<p>Saved text</p>");
  await wrapper.setProps({ session: { ...initial, configuration_version: 2 } });
  await wrapper.get("form").trigger("submit");
  await flushPromises();
  expect(request.mock.calls[0][1]).toMatchObject({ configuration_version: 1, title: "An idea" });
  await wrapper.get("form").trigger("submit");
  await flushPromises();
  expect(request.mock.calls[1]).toEqual(request.mock.calls[0]);
  expect(wrapper.emitted("created")).toHaveLength(1);
  wrapper.unmount();
});
