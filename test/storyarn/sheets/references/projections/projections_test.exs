defmodule Storyarn.Sheets.References.Projections.ProjectionsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Sheets.References.Entities.EntityReferenceRecord
  alias Storyarn.Sheets.References.Projections.AssetRecord
  alias Storyarn.Sheets.References.Projections.EntityTrashRefRecord
  alias Storyarn.Sheets.References.Projections.FlowNodeRecord
  alias Storyarn.Sheets.References.Projections.FlowRecord
  alias Storyarn.Sheets.References.Projections.ProjectRecord
  alias Storyarn.Sheets.References.Projections.SceneAmbientFlowRecord
  alias Storyarn.Sheets.References.Projections.ScenePinRecord
  alias Storyarn.Sheets.References.Projections.SceneRecord
  alias Storyarn.Sheets.References.Projections.SceneZoneRecord
  alias Storyarn.Sheets.References.Projections.VariableReferenceRecord

  test "references owns every foreign SQL shape used by its commands and queries" do
    assert EntityReferenceRecord.__schema__(:source) == "entity_references"
    assert VariableReferenceRecord.__schema__(:source) == "variable_references"
    assert EntityTrashRefRecord.__schema__(:source) == "flows_entity_trash_refs"
    assert ProjectRecord.__schema__(:source) == "projects"
    assert AssetRecord.__schema__(:source) == "assets"
    assert FlowRecord.__schema__(:source) == "flows"
    assert FlowNodeRecord.__schema__(:source) == "flow_nodes"
    assert SceneRecord.__schema__(:source) == "scenes"
    assert ScenePinRecord.__schema__(:source) == "scene_pins"
    assert SceneZoneRecord.__schema__(:source) == "scene_zones"
    assert SceneAmbientFlowRecord.__schema__(:source) == "scene_ambient_flows"
  end

  test "projections retain the facts that make reference ownership explicit" do
    assert Enum.all?([ProjectRecord, AssetRecord, FlowRecord, SceneRecord], fn record ->
             :deleted_at in record.__schema__(:fields)
           end)

    assert Enum.all?([AssetRecord, FlowRecord, SceneRecord], fn record ->
             :project_id in record.__schema__(:fields)
           end)

    assert :data in FlowNodeRecord.__schema__(:fields)
    assert :target_sheet_avatar_id in EntityTrashRefRecord.__schema__(:fields)
    assert :source_variable in VariableReferenceRecord.__schema__(:fields)
  end
end
