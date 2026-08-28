defmodule Storyarn.Flows.FlowTrash do
  @moduledoc """
  Flow-owned soft-delete queries and descendant cascade behavior.

  The localization cleanup is part of the Flow deletion invariant, so it lives
  here instead of being injected into a cross-tool recursive utility.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.Localization
  alias Storyarn.Flows.References
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  @spec list_deleted(pos_integer()) :: [Flow.t()]
  def list_deleted(project_id) do
    Repo.all(
      from(flow in Flow,
        where: flow.project_id == ^project_id and not is_nil(flow.deleted_at),
        order_by: [desc: flow.deleted_at]
      )
    )
  end

  @spec soft_delete_descendants(pos_integer(), pos_integer()) :: [pos_integer()]
  def soft_delete_descendants(project_id, parent_id) do
    children =
      Repo.all(
        from(flow in Flow,
          where:
            flow.project_id == ^project_id and flow.parent_id == ^parent_id and
              is_nil(flow.deleted_at),
          order_by: [asc: flow.id]
        )
      )

    Enum.flat_map(children, fn child ->
      Localization.delete_flow_node_texts_for_flows([child.id])

      Repo.update_all(
        from(flow in Flow, where: flow.id == ^child.id and is_nil(flow.deleted_at)),
        set: [deleted_at: TimeHelpers.now()]
      )

      case References.sweep_trash_jsonb_field(
             FlowNode,
             "flow_node",
             :data,
             "referenced_flow_id",
             :flow,
             child.id
           ) do
        {:ok, _swept_count} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end

      [child.id | soft_delete_descendants(project_id, child.id)]
    end)
  end
end
