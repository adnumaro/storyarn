defmodule StoryarnWeb.SceneLive.VersionViewerTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Scenes.Versioning.EntityVersionRecord

  setup :register_and_log_in_user

  setup %{user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    scene = scene_fixture(project, %{name: "Historical map"})
    _pin = pin_fixture(scene, %{"label" => "Old gate"})

    _zone =
      zone_fixture(scene, %{
        "name" => "Old courtyard",
        "action_type" => "walkable",
        "is_walkable" => true,
        "label_mode" => "both",
        "label_font_size" => 18,
        "label_font_family" => "serif",
        "label_font_weight" => "700",
        "label_font_style" => "italic"
      })

    _annotation = annotation_fixture(scene, %{"text" => "Archived note"})
    {:ok, version} = Scenes.create_version(scene, user.id, title: "Review point")

    %{project: project, scene: scene, version: version}
  end

  describe "a readable version" do
    test "renders an immutable Scene surface", %{conn: conn, project: project, scene: scene} do
      {:ok, view, _html} = live(conn, viewer_path(project, scene, 1))

      vue = LiveVue.Test.get_vue(view, name: "live/scene/show/SceneCompactSurface")
      surface = vue.props["surface"]

      assert vue.component == "live/scene/show/SceneCompactSurface"
      assert surface["canvas"]["sceneData"]["name"] == "Historical map"
      assert [%{"label" => "Old gate"}] = surface["canvas"]["pins"]
      assert [zone] = surface["canvas"]["zones"]
      assert zone["name"] == "Old courtyard"
      assert zone["isWalkable"] == true
      assert zone["labelMode"] == "both"
      assert zone["labelFontSize"] == 18
      assert zone["labelFontFamily"] == "serif"
      assert zone["labelFontWeight"] == "700"
      assert zone["labelFontStyle"] == "italic"
      assert [%{"text" => "Archived note"}] = surface["canvas"]["annotations"]
      assert surface["canvas"]["editMode"] == false
      assert surface["canvas"]["canEdit"] == false
      assert surface["dock"]["editMode"] == false
      assert surface["dock"]["compact"] == true
    end
  end

  describe "a version that cannot be shown" do
    test "reports a version number that does not exist inside the viewer pane", %{
      conn: conn,
      project: project,
      scene: scene
    } do
      assert {:ok, view, _html} = live(conn, viewer_path(project, scene, 99))

      assert error_reason(view) == "not_found"
      refute render(view) =~ "SceneCompactSurface"
    end

    test "keeps a checksum failure inside the viewer pane", %{
      conn: conn,
      project: project,
      scene: scene,
      version: version
    } do
      {1, nil} =
        Repo.update_all(from_version(version), set: [checksum: String.duplicate("a", 64)])

      assert {:ok, view, _html} = live(conn, viewer_path(project, scene, 1))

      assert error_reason(view) == "integrity"
      refute render(view) =~ "SceneCompactSurface"
    end

    test "keeps a compressed-size failure inside the viewer pane", %{
      conn: conn,
      project: project,
      scene: scene,
      version: version
    } do
      {1, nil} =
        Repo.update_all(
          from_version(version),
          set: [snapshot_size_bytes: version.snapshot_size_bytes + 1]
        )

      assert {:ok, view, _html} = live(conn, viewer_path(project, scene, 1))

      assert error_reason(view) == "integrity"
      refute render(view) =~ "SceneCompactSurface"
    end
  end

  describe "identity and ownership boundaries" do
    test "treats malformed Scene and version identifiers as not found", %{
      conn: conn,
      project: project,
      scene: scene
    } do
      assert {:ok, scene_error_view, _html} =
               live(conn, viewer_path(project, "not-a-scene", 1))

      assert error_reason(scene_error_view) == "not_found"
      refute render(scene_error_view) =~ "SceneCompactSurface"

      assert {:ok, version_error_view, _html} =
               live(conn, viewer_path(project, scene, "not-a-version"))

      assert error_reason(version_error_view) == "not_found"
      refute render(version_error_view) =~ "SceneCompactSurface"
    end

    test "treats zero and negative Scene or version identifiers as not found", %{
      conn: conn,
      project: project,
      scene: scene
    } do
      invalid_identifiers = [
        {0, 1},
        {-1, 1},
        {scene.id, 0},
        {scene.id, -1}
      ]

      for {scene_id, version_number} <- invalid_identifiers do
        assert {:ok, view, _html} = live(conn, viewer_path(project, scene_id, version_number))
        assert error_reason(view) == "not_found"
        refute render(view) =~ "SceneCompactSurface"
      end
    end

    test "does not resolve a Scene owned by another project", %{
      conn: conn,
      user: user,
      project: project
    } do
      other_project = user |> project_fixture() |> Repo.preload(:workspace)
      other_scene = scene_fixture(other_project)
      {:ok, _version} = Scenes.create_version(other_scene, user.id, title: "Other project")

      assert {:ok, view, _html} = live(conn, viewer_path(project, other_scene, 1))

      assert error_reason(view) == "not_found"
      refute render(view) =~ "SceneCompactSurface"
    end

    test "does not resolve a version belonging to another Scene", %{
      conn: conn,
      user: user,
      project: project,
      scene: scene
    } do
      other_scene = scene_fixture(project)
      {:ok, _first_version} = Scenes.create_version(other_scene, user.id, title: "First")
      {:ok, other_version} = Scenes.create_version(other_scene, user.id, title: "Second")

      assert other_version.version_number == 2

      assert {:ok, view, _html} =
               live(conn, viewer_path(project, scene, other_version.version_number))

      assert error_reason(view) == "not_found"
      refute render(view) =~ "SceneCompactSurface"
    end

    test "redirects a user without project access before loading the Scene version", %{
      conn: conn,
      project: project,
      scene: scene
    } do
      conn = log_in_user(conn, user_fixture())

      assert {:error, {:redirect, %{to: "/workspaces", flash: %{"error" => error_message}}}} =
               live(conn, viewer_path(project, scene, 1))

      assert error_message =~ "access"
    end
  end

  defp viewer_path(project, scene, version_number) do
    scene_id = if is_struct(scene), do: scene.id, else: scene

    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene_id}/versions/#{version_number}/viewer"
  end

  defp error_reason(view) do
    LiveVue.Test.get_vue(view, name: "live/versioning/viewer/VersionViewerError").props["reason"]
  end

  defp from_version(%EntityVersionRecord{id: id}) do
    import Ecto.Query, only: [from: 2]

    from(version in EntityVersionRecord, where: version.id == ^id)
  end
end
