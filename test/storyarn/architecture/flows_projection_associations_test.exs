defmodule Storyarn.Architecture.FlowsProjectionAssociationsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.Editor.Projections.AssetRecord, as: EditorAssetRecord
  alias Storyarn.Flows.Editor.Projections.BlockRecord, as: EditorBlockRecord
  alias Storyarn.Flows.Editor.Projections.GalleryImageRecord, as: EditorGalleryImageRecord
  alias Storyarn.Flows.Editor.Projections.SheetAvatarRecord, as: EditorAvatarRecord
  alias Storyarn.Flows.Editor.Projections.SheetRecord, as: EditorSheetRecord
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.References.Projections.AssetRecord, as: ReferencesAssetRecord
  alias Storyarn.Flows.References.Projections.BlockRecord, as: ReferencesBlockRecord
  alias Storyarn.Flows.References.Projections.SheetAvatarRecord, as: ReferencesAvatarRecord
  alias Storyarn.Flows.References.Projections.SheetRecord, as: ReferencesSheetRecord
  alias Storyarn.Flows.References.Projections.TableColumnRecord, as: ReferencesColumnRecord
  alias Storyarn.Flows.References.Projections.TableRowRecord, as: ReferencesRowRecord
  alias Storyarn.Flows.Runtime.Projections.AssetRecord, as: RuntimeAssetRecord
  alias Storyarn.Flows.Runtime.Projections.SheetAvatarRecord, as: RuntimeAvatarRecord
  alias Storyarn.Flows.Runtime.Projections.SheetRecord, as: RuntimeSheetRecord
  alias Storyarn.Flows.SequenceConfig
  alias Storyarn.Flows.SequenceTrack
  alias Storyarn.Flows.SequenceVisualLayer
  alias Storyarn.Flows.VariableReference
  alias Storyarn.Flows.Versioning.Entities.AssetRecord, as: VersioningAssetRecord
  alias Storyarn.Flows.Versioning.EntityVersionRecord
  alias Storyarn.Flows.Versioning.Projections.ProjectRecord, as: VersioningProjectRecord
  alias Storyarn.Flows.Versioning.Projections.SheetAvatarRecord, as: VersioningAvatarRecord
  alias Storyarn.Flows.Versioning.Projections.SheetRecord, as: VersioningSheetRecord
  alias Storyarn.Flows.Versioning.Projections.UserRecord, as: VersioningUserRecord

  @root "lib/storyarn/flows"
  @capabilities ~w(ai editor expressions health localization references runtime versioning)

  test "owned schemas associate to entities and projections selected by their capability" do
    assert association(Flow, :parent) == Flow
    assert association(Flow, :children) == Flow
    assert association(Flow, :nodes) == FlowNode
    assert association(Flow, :connections) == FlowConnection

    assert association(FlowNode, :flow) == Flow
    assert association(FlowNode, :parent) == FlowNode
    assert association(FlowNode, :children) == FlowNode
    assert association(FlowNode, :sequence_config) == SequenceConfig
    assert association(FlowNode, :sequence_tracks) == SequenceTrack
    assert association(FlowNode, :sequence_visual_layers) == SequenceVisualLayer
    assert association(FlowNode, :outgoing_connections) == FlowConnection
    assert association(FlowNode, :incoming_connections) == FlowConnection

    assert association(FlowConnection, :flow) == Flow
    assert association(FlowConnection, :source_node) == FlowNode
    assert association(FlowConnection, :target_node) == FlowNode
    assert association(SequenceConfig, :flow_node) == FlowNode
    assert association(SequenceTrack, :flow_node) == FlowNode
    assert association(SequenceTrack, :asset) == EditorAssetRecord
    assert association(SequenceVisualLayer, :flow_node) == FlowNode
    assert association(SequenceVisualLayer, :asset) == EditorAssetRecord

    assert association(EditorBlockRecord, :sheet) == EditorSheetRecord
    assert association(EditorGalleryImageRecord, :asset) == EditorAssetRecord
    assert association(EditorAvatarRecord, :asset) == EditorAssetRecord
    assert association(EditorSheetRecord, :banner_asset) == EditorAssetRecord
    assert association(EditorSheetRecord, :avatars) == EditorAvatarRecord
    assert association(EditorSheetRecord, :blocks) == EditorBlockRecord

    assert association(VariableReference, :flow_node) == FlowNode
    assert association(VariableReference, :block) == ReferencesBlockRecord
    assert association(ReferencesBlockRecord, :sheet) == ReferencesSheetRecord
    assert association(ReferencesBlockRecord, :table_columns) == ReferencesColumnRecord
    assert association(ReferencesBlockRecord, :table_rows) == ReferencesRowRecord
    assert association(ReferencesAvatarRecord, :asset) == ReferencesAssetRecord
    assert association(ReferencesSheetRecord, :banner_asset) == ReferencesAssetRecord
    assert association(ReferencesSheetRecord, :avatars) == ReferencesAvatarRecord
    assert association(ReferencesSheetRecord, :blocks) == ReferencesBlockRecord

    assert association(RuntimeAvatarRecord, :asset) == RuntimeAssetRecord
    assert association(RuntimeSheetRecord, :avatars) == RuntimeAvatarRecord

    assert association(EntityVersionRecord, :project) == VersioningProjectRecord
    assert association(EntityVersionRecord, :created_by) == VersioningUserRecord
    assert association(VersioningAvatarRecord, :asset) == VersioningAssetRecord
    assert association(VersioningSheetRecord, :banner_asset) == VersioningAssetRecord
    assert association(VersioningSheetRecord, :avatars) == VersioningAvatarRecord
  end

  test "schemas never associate to another Flow capability's Data projection" do
    violations =
      for capability <- @capabilities,
          path <- schema_paths(capability),
          module <- [module_in(path)],
          association <- associations(module),
          related <- [association(module, association)],
          related_capability = data_capability(related),
          related_capability != nil and related_capability != capability,
          do: "#{path}: #{inspect(module)}.#{association} -> #{inspect(related)}"

    assert violations == [],
           "Flow capabilities must own independent Data association graphs: #{inspect(violations)}"
  end

  defp schema_paths(capability) do
    Enum.flat_map(~w(data entities), fn role ->
      Path.wildcard("#{@root}/#{capability}/#{role}/**/*.ex")
    end)
  end

  defp module_in(path) do
    [module_name] = Regex.run(~r/^defmodule\s+([A-Za-z0-9_.]+)\s+do/m, File.read!(path), capture: :all_but_first)

    Module.concat([module_name])
  end

  defp associations(module) do
    if function_exported?(module, :__schema__, 1), do: module.__schema__(:associations), else: []
  end

  defp data_capability(module) do
    case Module.split(module) do
      ["Storyarn", "Flows", capability, "Data" | _rest] -> Macro.underscore(capability)
      _other -> nil
    end
  end

  defp association(schema, name), do: schema.__schema__(:association, name).related
end
