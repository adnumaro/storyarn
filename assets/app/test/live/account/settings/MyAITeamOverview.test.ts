import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it } from "vitest";
import MyAITeamOverview, {
  type AITeamWorkspaceOverview,
} from "../../../../live/account/settings/MyAITeamOverview.vue";
import { setTestLocale } from "../../../setup";

function workspaces(): AITeamWorkspaceOverview[] {
  return [
    {
      id: 7,
      name: "Narrative games",
      slug: "narrative-games",
      role: "owner",
      policy_allowed: true,
      can_configure: true,
      edit_path: "/users/settings/ai-team/narrative-games?sudo_grant=valid",
      slots: [
        {
          slot: "general_assistant",
          kind: "role",
          required_capabilities: ["tasks"],
          available: true,
          preference: {
            provider_name: "OpenAI",
            model: "gpt-5-mini",
            implementation_status: "executable",
            status: "ready",
          },
        },
        {
          slot: "writing_assistant",
          kind: "role",
          required_capabilities: ["suggestions"],
          available: true,
          preference: {
            provider_name: "OpenAI",
            model: "gpt-5-mini",
            implementation_status: "executable",
            status: "ready",
          },
        },
        {
          slot: "illustrator",
          kind: "role",
          required_capabilities: ["images"],
          available: true,
          preference: {
            provider_name: "OpenAI",
            model: "gpt-image-1",
            implementation_status: null,
            status: "model_unavailable",
          },
        },
        {
          slot: "voice",
          kind: "role",
          required_capabilities: ["speech"],
          available: true,
          preference: {
            provider_name: "OpenAI",
            model: "tts-1",
            implementation_status: "configuration_only",
            status: "configured",
          },
        },
      ],
    },
    {
      id: 8,
      name: "Film room",
      slug: "film-room",
      role: null,
      policy_allowed: false,
      can_configure: false,
      edit_path: null,
      slots: [
        {
          slot: "general_assistant",
          kind: "role",
          required_capabilities: ["tasks"],
          available: true,
          preference: null,
        },
        {
          slot: "writing_assistant",
          kind: "role",
          required_capabilities: ["suggestions"],
          available: true,
          preference: null,
        },
        {
          slot: "illustrator",
          kind: "role",
          required_capabilities: ["images"],
          available: false,
          preference: null,
        },
        {
          slot: "voice",
          kind: "role",
          required_capabilities: ["speech"],
          available: false,
          preference: null,
        },
      ],
    },
  ];
}

describe("MyAITeamOverview", () => {
  beforeEach(() => {
    setTestLocale("en");
  });

  it("summarizes every accessible workspace and personal role choice", () => {
    const wrapper = mount(MyAITeamOverview, {
      props: { workspaces: workspaces() },
    });

    expect(wrapper.findAll("[data-workspace-slug]")).toHaveLength(2);
    expect(
      wrapper.get('[data-workspace-slug="narrative-games"]').findAll("[data-role]"),
    ).toHaveLength(4);
    expect(
      wrapper
        .get('[data-workspace-slug="narrative-games"] [data-role="general_assistant"]')
        .attributes("data-state"),
    ).toBe("ready");
    expect(wrapper.get('[data-workspace-slug="narrative-games"]').text()).toContain(
      "Narrative games",
    );
    expect(
      wrapper
        .get('[data-workspace-slug="narrative-games"] [data-role="writing_assistant"]')
        .attributes("data-state"),
    ).toBe("ready");
    expect(wrapper.text()).toContain("OpenAI");
    expect(wrapper.text()).toContain("gpt-5-mini");
    expect(wrapper.get("#ai-team-personal-scope-note").text()).toContain(
      "Other members keep their provider keys and configurations private",
    );
  });

  it("distinguishes configured, broken, unconfigured and coming-soon roles", () => {
    const wrapper = mount(MyAITeamOverview, {
      props: { workspaces: workspaces() },
    });

    expect(
      wrapper
        .get('[data-workspace-slug="narrative-games"] [data-role="illustrator"]')
        .attributes("data-state"),
    ).toBe("broken");
    expect(
      wrapper
        .get('[data-workspace-slug="film-room"] [data-role="writing_assistant"]')
        .attributes("data-state"),
    ).toBe("unconfigured");
    expect(
      wrapper
        .get('[data-workspace-slug="narrative-games"] [data-role="voice"]')
        .attributes("data-state"),
    ).toBe("configured");
    expect(
      wrapper.get('[data-workspace-slug="narrative-games"] [data-role="voice"]').text(),
    ).toContain("execution support is still being built");
    expect(
      wrapper.get('[data-workspace-slug="film-room"] [data-role="voice"]').attributes("data-state"),
    ).toBe("coming-soon");
  });

  it("offers configuration only for workspaces the actor may configure", () => {
    const wrapper = mount(MyAITeamOverview, {
      props: { workspaces: workspaces() },
    });

    expect(wrapper.get("#configure-ai-team-narrative-games").attributes("href")).toBe(
      "/users/settings/ai-team/narrative-games?sudo_grant=valid",
    );
    expect(wrapper.get("#configure-ai-team-narrative-games").attributes("aria-label")).toBe(
      "Configure the AI team for Narrative games",
    );
    expect(
      wrapper.get('[data-workspace-slug="narrative-games"]').attributes("aria-labelledby"),
    ).toBe("ai-team-workspace-title-narrative-games");
    expect(wrapper.find("#configure-ai-team-film-room").exists()).toBe(false);
    expect(wrapper.get('[data-workspace-slug="film-room"]').text()).toContain("Project access");
    expect(wrapper.get('[data-workspace-slug="film-room"]').text()).toContain(
      "Workspace membership is required to configure this AI team",
    );
    expect(wrapper.get('[data-workspace-slug="film-room"]').text()).not.toContain(
      "Personal AI is blocked here",
    );
  });

  it("links every configurable workspace to its own editor", () => {
    const workspaceData = workspaces();
    const source = workspaceData[0]!;
    const novelWorkspace: AITeamWorkspaceOverview = {
      ...source,
      id: 9,
      name: "Novel lab",
      slug: "novel-lab",
      edit_path: "/users/settings/ai-team/novel-lab?sudo_grant=valid",
    };
    const wrapper = mount(MyAITeamOverview, {
      props: { workspaces: [...workspaceData, novelWorkspace] },
    });

    expect(wrapper.get("#configure-ai-team-narrative-games").attributes("href")).toBe(
      "/users/settings/ai-team/narrative-games?sudo_grant=valid",
    );
    expect(wrapper.get("#configure-ai-team-novel-lab").attributes("href")).toBe(
      "/users/settings/ai-team/novel-lab?sudo_grant=valid",
    );
    expect(wrapper.get("#configure-ai-team-novel-lab").attributes("aria-label")).toBe(
      "Configure the AI team for Novel lab",
    );
  });

  it("waits for a wide settings content area before rendering the role matrix", () => {
    const wrapper = mount(MyAITeamOverview, {
      props: { workspaces: workspaces() },
    });

    expect(wrapper.get("#ai-team-overview-columns").classes()).toContain("xl:grid");
    expect(wrapper.get("#ai-team-overview-columns").classes()).not.toContain("md:grid");
    expect(wrapper.get('[data-workspace-slug="narrative-games"]').classes()).toContain(
      "xl:grid-cols-[minmax(10rem,1.2fr)_repeat(4,minmax(8rem,1fr))_auto]",
    );
  });

  it("centers role headers and values without changing the outer columns", () => {
    const wrapper = mount(MyAITeamOverview, {
      props: { workspaces: workspaces() },
    });

    const headers = wrapper.get("#ai-team-overview-columns").findAll("span");
    expect(headers[0]?.classes()).not.toContain("text-center");
    expect(headers.slice(1, 5).every((header) => header.classes().includes("text-center"))).toBe(
      true,
    );
    expect(
      wrapper
        .get('[data-workspace-slug="narrative-games"] [data-role="general_assistant"]')
        .classes(),
    ).toContain("text-center");
    expect(
      wrapper.get('[data-workspace-slug="narrative-games"] > div:first-child').classes(),
    ).not.toContain("text-center");
    expect(wrapper.get("#configure-ai-team-narrative-games").classes()).not.toContain(
      "text-center",
    );
  });

  it("renders an informative empty state without workspaces", () => {
    const wrapper = mount(MyAITeamOverview, {
      props: { workspaces: [] },
    });

    expect(wrapper.find("#ai-team-overview-empty").exists()).toBe(true);
    expect(wrapper.find("#ai-team-workspace-overviews").exists()).toBe(false);
  });
});
