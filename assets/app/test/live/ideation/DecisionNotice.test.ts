import { afterEach, describe, expect, it } from "vitest";
import { mount, type VueWrapper } from "@vue/test-utils";
import Notice from "@app/live/ideation/DecisionNotice.vue";
import type { NotificationItem } from "@components/notifications/types";
import type { DecisionNoticeData } from "@app/live/ideation/decisionTypes";
import { accepted, decision } from "./decisionFixtures";

let wrapper: VueWrapper;
afterEach(() => wrapper?.unmount());

function notice(kind: NotificationItem["kind"], data: Partial<DecisionNoticeData> = {}) {
  wrapper = mount(Notice, {
    props: {
      notification: {
        id: 7,
        kind,
        entityType: "decision",
        entityName: "Endings we could ship",
        status: null,
        createdAt: "2026-09-24T12:00:00Z",
        readAt: null,
        actorName: "Noor Haddad",
        projectName: "The Glass Harbor",
        href: null,
      },
      data: {
        decision: decision({ canAccept: true }),
        target: null,
        action: { kind: "open", href: "/brainstorming/3?decision=4" },
        sessionName: "Endings we could ship",
        ...data,
      },
      when: "12 min ago",
    },
  });
}

describe("a decision notification", () => {
  it("asks the responsible person to accept, and opening keeps the request unread", async () => {
    notice("decision_to_accept");
    expect(wrapper.text()).toContain("Noor Haddad proposed a decision for you to accept");
    expect(wrapper.find("[data-decision-card]").text()).toContain("Waiting for you");
    const open = wrapper.get("#notification-action-7");
    expect(open.text()).toBe("Open");
    expect(open.attributes("href")).toBe("/brainstorming/3?decision=4");
    expect(open.attributes("data-slot")).toBe("button");
    expect(open.classes().join(" ")).toContain("bg-primary");
    expect(wrapper.get("time").text()).toBe("12 min ago");
    expect(wrapper.text()).toContain("Endings we could ship");
    open.element.addEventListener("click", (event) => event.preventDefault(), { once: true });
    await open.trigger("click");
    expect(wrapper.emitted("open")).toEqual([[true]]);
  });

  it("sends the owner of a next action to the content still to apply", async () => {
    notice("decision_next_action", {
      decision: accepted(),
      target: "Mara",
      action: { kind: "apply", href: "/sheets/7?decision=4&session=3" },
    });
    expect(wrapper.text()).toContain("Noor Haddad asked you to apply · Mara");
    const apply = wrapper.get("#notification-action-7");
    expect(apply.text()).toBe("Go apply");
    expect(apply.attributes("href")).toBe("/sheets/7?decision=4&session=3");
    apply.element.addEventListener("click", (event) => event.preventDefault(), { once: true });
    await apply.trigger("click");
    expect(wrapper.emitted("open")).toEqual([[false]]);
  });

  it("names the content an application marked, and only offers to open it", () => {
    notice("decision_applied", { decision: accepted(), target: "Mara" });
    expect(wrapper.text()).toContain("Noor Haddad marked Mara as applied");
    expect(wrapper.get("#notification-action-7").classes().join(" ")).not.toContain("bg-primary");
    notice("decision_applied", { decision: accepted() });
    expect(wrapper.text()).toContain("Noor Haddad marked a decision as applied");
  });
});
