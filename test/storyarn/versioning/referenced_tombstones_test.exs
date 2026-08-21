defmodule Storyarn.Versioning.ReferencedTombstonesTest do
  use Storyarn.DataCase, async: true

  import Ecto.Changeset, only: [change: 2]
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Scenes
  alias Storyarn.Versioning.Builders.ProjectSnapshotBuilder
  alias Storyarn.Versioning.ReferencedTombstones
  alias Storyarn.Versioning.SnapshotObjectFormat

  test "captures only referenced tombstones, deduplicates them, and closes child ownership" do
    project = project_fixture(user_fixture())
    language_fixture(project, %{locale_code: "es"})

    active_sheet = sheet_fixture(project, %{name: "Active sheet"})
    active_block = block_fixture(active_sheet)
    deleted_sheet = sheet_fixture(project, %{name: "Referenced deleted sheet"})
    deleted_block = block_fixture(deleted_sheet)

    active_flow = flow_fixture(project, %{name: "Active flow"})
    active_node = node_fixture(active_flow)
    deleted_flow = flow_fixture(project, %{name: "Referenced deleted flow"})
    deleted_node = node_fixture(deleted_flow)

    deleted_scene = scene_fixture(project, %{name: "Referenced deleted scene"})
    _active_child = scene_fixture(project, %{name: "Active child", parent_id: deleted_scene.id})
    active_scene = scene_fixture(project, %{name: "Active scene"})

    Repo.update!(change(active_block, inherited_from_block_id: deleted_block.id, detached: true))
    Repo.update!(change(active_flow, scene_id: deleted_scene.id))

    Repo.insert!(%FlowConnection{
      flow_id: active_flow.id,
      source_node_id: active_node.id,
      target_node_id: deleted_node.id,
      source_pin: "output",
      target_pin: "input"
    })

    pin_fixture(active_scene, %{"sheet_id" => deleted_sheet.id, "flow_id" => deleted_flow.id})
    assert {:ok, _ambient} = Scenes.create_ambient_flow(active_scene.id, %{"flow_id" => deleted_flow.id})

    localized_text = localized_text_fixture(project.id, %{source_id: active_node.id})
    Repo.update!(change(localized_text, speaker_sheet_id: deleted_sheet.id))

    now = DateTime.truncate(DateTime.utc_now(), :second)

    for entity <- [deleted_block, deleted_node, deleted_sheet, deleted_flow, deleted_scene] do
      Repo.update!(change(entity, deleted_at: now))
    end

    assert {:ok, snapshot} =
             Repo.transaction(fn ->
               ProjectSnapshotBuilder.build_canonical_snapshot_in_transaction(project.id,
                 localization_scope: :active,
                 include_referenced_tombstones: true
               )
             end)

    entries = snapshot["referenced_tombstones"]["entries"]

    assert Enum.map(entries, &{&1["entity_type"], &1["id"]}) == [
             {"sheet", deleted_sheet.id},
             {"flow", deleted_flow.id},
             {"scene", deleted_scene.id},
             {"block", deleted_block.id},
             {"flow_node", deleted_node.id}
           ]

    by_type = Map.new(entries, &{&1["entity_type"], &1})
    assert by_type["block"]["owner"] == %{"entity_type" => "sheet", "id" => deleted_sheet.id}
    assert by_type["flow_node"]["owner"] == %{"entity_type" => "flow", "id" => deleted_flow.id}
    assert by_type["scene"]["owner"] == %{"entity_type" => "project"}
    refute Map.has_key?(by_type["block"]["snapshot"], "inherited_from_block_id")
    refute Map.has_key?(by_type["flow"]["snapshot"], "scene_id")
    refute Map.has_key?(by_type["scene"]["snapshot"], "parent_id")

    assert :ok = SnapshotObjectFormat.validate_project(snapshot)
    assert :ok = ReferencedTombstones.validate_complete(snapshot, 10_001)
  end

  test "foreign references never leak data or block capture, but are not standalone-complete" do
    user = user_fixture()
    project = project_fixture(user)
    foreign_project = project_fixture(user)
    flow = flow_fixture(project)
    foreign_scene = scene_fixture(foreign_project, %{name: "Secret foreign scene"})
    Repo.update!(change(flow, scene_id: foreign_scene.id))
    Repo.update!(change(foreign_scene, deleted_at: DateTime.truncate(DateTime.utc_now(), :second)))

    assert {:ok, snapshot} =
             Repo.transaction(fn ->
               ProjectSnapshotBuilder.build_canonical_snapshot_in_transaction(project.id,
                 localization_scope: :active,
                 include_referenced_tombstones: true
               )
             end)

    assert snapshot["referenced_tombstones"]["entries"] == []
    refute inspect(snapshot) =~ "Secret foreign scene"
    assert :ok = SnapshotObjectFormat.validate_project(snapshot)

    assert {:error, {:referenced_tombstone_catalog_mismatch, [{"scene", id}], []}} =
             ReferencedTombstones.validate_complete(snapshot, 10_001)

    assert id == foreign_scene.id
  end

  test "canonical in-situ and strict template captures retain their previous payload shape" do
    project = project_fixture(user_fixture())

    assert {:ok, canonical} =
             Repo.transaction(fn ->
               ProjectSnapshotBuilder.build_canonical_snapshot_in_transaction(project.id,
                 localization_scope: :active
               )
             end)

    strict = ProjectSnapshotBuilder.build_snapshot(project.id)

    refute Map.has_key?(canonical, "referenced_tombstones")
    refute Map.has_key?(strict, "referenced_tombstones")
    assert :ok = SnapshotObjectFormat.validate_project(canonical)
    assert :ok = SnapshotObjectFormat.validate_project(strict)
  end

  test "structural validation is optional while standalone validation is required and exact" do
    project = empty_project()
    assert :ok = SnapshotObjectFormat.validate_project(project)
    assert {:error, :missing_referenced_tombstones} = ReferencedTombstones.validate_complete(project, 10_001)

    scene_entry = tombstone_entry("scene", 42)

    complete =
      project
      |> put_in(["flows"], [
        %{"id" => 7, "snapshot" => %{"nodes" => [], "connections" => [], "scene_id" => 42}}
      ])
      |> Map.put("referenced_tombstones", %{"format_version" => 1, "entries" => [scene_entry]})

    assert :ok = ReferencedTombstones.validate_complete(complete, 10_001)

    assert :ok =
             project
             |> Map.put("referenced_tombstones", %{
               "format_version" => 1,
               "entries" => [tombstone_entry("sheet", 1), tombstone_entry("sheet", 2)]
             })
             |> ReferencedTombstones.validate(2)

    assert {:error, {:collection_limit_exceeded, :referenced_tombstones, 1}} =
             project
             |> Map.put("referenced_tombstones", %{
               "format_version" => 1,
               "entries" => [tombstone_entry("sheet", 1), tombstone_entry("sheet", 2)]
             })
             |> ReferencedTombstones.validate(1)

    active_over_catalog_limit =
      project
      |> Map.put("sheets", [%{"id" => 1, "snapshot" => %{"blocks" => []}}])
      |> Map.put("referenced_tombstones", %{"format_version" => 1, "entries" => []})

    assert :ok = ReferencedTombstones.validate(active_over_catalog_limit, 0)
  end

  defp empty_project do
    %{
      "format_version" => 2,
      "sheets" => [],
      "flows" => [],
      "scenes" => [],
      "tree" => %{"sheets" => [], "flows" => [], "scenes" => []},
      "localization" => %{"texts" => []}
    }
  end

  defp tombstone_entry("sheet", id) do
    %{
      "entity_type" => "sheet",
      "id" => id,
      "deleted_at" => "2026-08-20T12:00:00Z",
      "owner" => %{"entity_type" => "project"},
      "snapshot" => %{
        "name" => "Deleted sheet",
        "shortcut" => nil,
        "description" => nil,
        "color" => nil,
        "position" => 0,
        "hidden_inherited_block_ids" => []
      }
    }
  end

  defp tombstone_entry("scene", id) do
    %{
      "entity_type" => "scene",
      "id" => id,
      "deleted_at" => "2026-08-20T12:00:00Z",
      "owner" => %{"entity_type" => "project"},
      "snapshot" => %{
        "name" => "Deleted scene",
        "shortcut" => nil,
        "description" => nil,
        "width" => nil,
        "height" => nil,
        "default_zoom" => 1.0,
        "default_center_x" => 50.0,
        "default_center_y" => 50.0,
        "position" => 0,
        "scale_unit" => nil,
        "scale_value" => nil,
        "fog_color" => "#000000",
        "fog_opacity" => 0.85,
        "exploration_display_mode" => "fit"
      }
    }
  end
end
