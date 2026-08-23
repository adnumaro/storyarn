defmodule StoryarnWeb.SceneLive.CompareTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Storyarn.Repo
  alias Storyarn.Scenes

  setup :register_and_log_in_user

  test "loads Scene comparison and exposes adjacent version navigation", %{
    conn: conn,
    user: user
  } do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    scene = scene_fixture(project, %{name: "World map"})

    {:ok, first} = Scenes.create_version(scene, user.id, title: "First draft")
    {:ok, middle} = Scenes.create_version(scene, user.id, title: "Review point")
    {:ok, latest} = Scenes.create_version(scene, user.id, title: "Published map")

    path = compare_path(project, scene, middle.version_number)
    {:ok, view, _html} = live(conn, path)

    compare = LiveVue.Test.get_vue(view, name: "live/versioning/compare/VersioningCompare")

    assert compare.props["version-label"] == "v2 — Review point"
    assert compare.props["back-url"] == scene_path(project, scene)
    assert compare.props["prev-version-url"] == compare_path(project, scene, first.version_number)
    assert compare.props["next-version-url"] == compare_path(project, scene, latest.version_number)

    assert compare.props["current-url"] ==
             scene_path(project, scene) <> "?layout=compact"

    assert compare.props["version-url"] == viewer_path(project, scene, middle.version_number)
  end

  defp scene_path(project, scene) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
  end

  defp compare_path(project, scene, version_number) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}/compare/#{version_number}"
  end

  defp viewer_path(project, scene, version_number) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}/versions/#{version_number}/viewer"
  end
end
