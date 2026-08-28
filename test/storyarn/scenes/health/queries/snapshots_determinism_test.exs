defmodule Storyarn.Scenes.Health.Queries.SnapshotsDeterminismTest do
  @moduledoc """
  The scenes health sweep must return the same rows in the same order on every
  run, as the equivalent Flow topology loader does.

  `position` is not a unique key — siblings created together share it, and every
  child table defaults it — so an `order_by` that stops there leaves the rest to
  `Repo.all`'s unspecified order. These tests force that order to differ from
  insertion order and pin the id tiebreak that makes it deterministic anyway.

  The lever is a Postgres fact rather than a mock: an UPDATE writes a NEW heap
  tuple at the end of the table, so a scan of a small table returns the rewritten
  row LAST even though it was inserted first.
  """

  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Scenes.Health.Queries.Snapshots, as: HealthSnapshots
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneZone

  setup do
    user = user_fixture()
    %{project: project_fixture(user)}
  end

  describe "the project sweep's scene order" do
    test "breaks ties by id when position and name collide", %{project: project} do
      ids = Enum.map(1..4, fn _ -> scene_fixture(project, %{name: "Twin"}).id end)

      collide_positions(Scene, ids)
      rewrite_first(Scene, ids)

      assert scene_ids(project) == Enum.sort(ids),
             "sibling scenes that share a position and a name reorder between runs, so the " <>
               "dashboard's row order depends on which row was touched last"
    end

    test "the sweep reports the same scenes in that order", %{project: project} do
      ids = Enum.map(1..4, fn _ -> scene_fixture(project, %{name: "Twin"}).id end)

      collide_positions(Scene, ids)
      rewrite_first(Scene, ids)

      swept =
        project.id
        |> Scenes.list_dashboard_health_findings()
        |> Enum.map(& &1.scene_id)
        |> Enum.uniq()

      assert swept == Enum.sort(ids)
    end
  end

  describe "the project sweep's element order" do
    test "breaks ties by id when zone positions collide", %{project: project} do
      scene = scene_fixture(project, %{name: "Collides"})
      ids = Enum.map(1..4, fn i -> zone_fixture(scene, %{"name" => "Twin #{i}"}).id end)

      collide_positions(SceneZone, ids)
      rewrite_first(SceneZone, ids)

      zone_ids =
        project.id
        |> HealthSnapshots.load_project()
        |> Enum.find(&(&1.scene.id == scene.id))
        |> then(& &1.collections.zones)
        |> Enum.map(& &1.id)

      assert zone_ids == Enum.sort(ids),
             "elements sharing a position reorder between runs, so findings for equally named " <>
               "elements swap their dashboard rows — and their deep links with them"
    end
  end

  # Every row gets the same position, which is what siblings created together
  # already look like.
  defp collide_positions(schema, ids) do
    Repo.update_all(from(e in schema, where: e.id in ^ids), set: [position: 0])
  end

  # Rewrites the row that was inserted FIRST, moving its heap tuple last.
  defp rewrite_first(schema, [first | _]) do
    Repo.update_all(from(e in schema, where: e.id == ^first), set: [position: 0])
  end

  defp scene_ids(project), do: project.id |> Scenes.list_scenes() |> Enum.map(& &1.id)
end
