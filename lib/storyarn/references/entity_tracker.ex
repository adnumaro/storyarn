defmodule Storyarn.References.EntityTracker do
  @moduledoc """
  Write-path adapter for entity references.

  During the PR2 transition this module delegates to the existing tracking logic
  while callers migrate to the `Storyarn.References` facade.

  Project rebuilds replace references only for active sources. Rows owned by
  sources under a soft-deleted Sheet, Flow, or Scene are recovery state: root
  restores make those sources visible again, and not every root restore path
  rebuilds its children. The transaction enclosing
  `rebuild_project_entity_references/1` makes each active source's
  delete-and-replace sequence atomic; direct updater callers must provide
  their own transaction when they need the same guarantee.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Projects.Persistence.ScenePinRecord, as: ScenePin
  alias Storyarn.Projects.Persistence.SceneRecord, as: Scene
  alias Storyarn.Projects.Persistence.SceneZoneRecord, as: SceneZone
  alias Storyarn.Projects.SceneEntityReferenceTracker
  alias Storyarn.References.Persistence.FlowNodeRecord
  alias Storyarn.References.Persistence.FlowRecord
  alias Storyarn.References.ProjectReferenceIntegrity
  alias Storyarn.Repo
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.ReferenceTracker
  alias Storyarn.Sheets.Sheet

  @rebuild_batch_size 100

  def update_block_references(block, opts \\ []), do: ReferenceTracker.update_block_references(block, opts)

  defdelegate delete_block_references(block_id), to: ReferenceTracker
  defdelegate delete_target_references(target_type, target_id), to: ReferenceTracker

  @spec update_flow_node_entity_references(map(), keyword()) :: :ok | {:error, term()}
  def update_flow_node_entity_references(node, opts \\ []), do: ReferenceTracker.update_flow_node_references(node, opts)

  defdelegate flow_node_entity_references_current?(node),
    to: ReferenceTracker,
    as: :flow_node_references_current?

  defdelegate flow_node_entity_references_current_ids(nodes),
    to: ReferenceTracker,
    as: :flow_node_references_current_ids

  def delete_flow_node_entity_references(node_id), do: ReferenceTracker.delete_flow_node_references(node_id)

  def update_scene_pin_entity_references(pin, opts \\ []),
    do: SceneEntityReferenceTracker.update_pin_references(pin, opts)

  def delete_scene_pin_entity_references(pin_id), do: SceneEntityReferenceTracker.delete_pin_references(pin_id)

  def update_scene_zone_entity_references(zone, opts \\ []),
    do: SceneEntityReferenceTracker.update_zone_references(zone, opts)

  def delete_scene_zone_entity_references(zone_id), do: SceneEntityReferenceTracker.delete_zone_references(zone_id)

  @spec rebuild_project_entity_references(integer()) :: :ok | {:error, term()}
  def rebuild_project_entity_references(project_id) when is_integer(project_id) and project_id > 0 do
    if Repo.in_transaction?() do
      do_rebuild_project_entity_references(project_id)
    else
      rebuild_project_entity_references_transaction(project_id)
    end
  end

  def rebuild_project_entity_references(project_id) do
    {:error, {:invalid_project_id, project_id}}
  end

  defp rebuild_project_entity_references_transaction(project_id) do
    case Repo.transaction(fn -> execute_project_rebuild!(project_id) end) do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_project_rebuild!(project_id) do
    case do_rebuild_project_entity_references(project_id) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
      unexpected -> Repo.rollback({:unexpected_entity_reference_rebuild_result, unexpected})
    end
  end

  defp do_rebuild_project_entity_references(project_id) do
    with {:ok, _project} <-
           ProjectReferenceIntegrity.lock_active_project(project_id, :update),
         :ok <-
           rebuild_sources(active_project_blocks_query(project_id), fn block ->
             ReferenceTracker.update_block_references(block, project_id: project_id)
           end),
         :ok <-
           rebuild_sources(active_project_flow_nodes_query(project_id), fn node ->
             ReferenceTracker.update_flow_node_references(node, project_id: project_id)
           end),
         :ok <-
           rebuild_sources(active_project_scene_rows_query(ScenePin, project_id), fn pin ->
             SceneEntityReferenceTracker.update_pin_references(pin, project_id: project_id)
           end) do
      rebuild_sources(active_project_scene_rows_query(SceneZone, project_id), fn zone ->
        SceneEntityReferenceTracker.update_zone_references(zone, project_id: project_id)
      end)
    end
  end

  defp active_project_blocks_query(project_id) do
    from block in Block,
      join: sheet in Sheet,
      on: sheet.id == block.sheet_id,
      where:
        sheet.project_id == ^project_id and
          is_nil(sheet.deleted_at) and is_nil(block.deleted_at),
      lock: "FOR UPDATE",
      select: block
  end

  defp active_project_flow_nodes_query(project_id) do
    from node in FlowNodeRecord,
      join: flow in FlowRecord,
      on: flow.id == node.flow_id,
      where:
        flow.project_id == ^project_id and
          is_nil(flow.deleted_at) and is_nil(node.deleted_at),
      lock: "FOR UPDATE",
      select: node
  end

  defp active_project_scene_rows_query(schema, project_id) do
    from row in schema,
      join: scene in Scene,
      on: scene.id == row.scene_id,
      where:
        scene.project_id == ^project_id and
          is_nil(scene.deleted_at),
      lock: "FOR UPDATE",
      select: row
  end

  defp rebuild_sources(query, update_fun, after_id \\ 0) do
    sources =
      Repo.all(
        from(source in query,
          where: source.id > ^after_id,
          order_by: [asc: source.id],
          limit: ^@rebuild_batch_size
        )
      )

    case apply_source_updates(sources, update_fun) do
      :ok when length(sources) == @rebuild_batch_size ->
        rebuild_sources(query, update_fun, List.last(sources).id)

      :ok ->
        :ok

      {:error, _reason} = error ->
        error
    end
  end

  defp apply_source_updates(sources, update_fun) do
    Enum.reduce_while(sources, :ok, fn source, :ok ->
      case update_fun.(source) do
        :ok ->
          {:cont, :ok}

        {:error, _reason} = error ->
          {:halt, error}

        unexpected ->
          {:halt, {:error, {:unexpected_entity_reference_update_result, source.id, unexpected}}}
      end
    end)
  end
end
