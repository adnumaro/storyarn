defmodule Storyarn.Shared.Trashable do
  @moduledoc """
  Generic soft-delete + restore lifecycle helper.

  Replaces ad-hoc sweep code in domain CRUDs. Each schema that can be
  soft-deleted is registered here with its target_type atom and the list
  of inbound refs (other schemas that hold a reference to it). When
  `soft_delete/1` is called:

    1. The entity is soft-deleted (`deleted_at = now()`).
    2. Every declared inbound ref is swept into the appropriate
       entity-trash-refs table via `Storyarn.Flows.EntityTrashRefs`.

  On `restore/1`, the inverse: `deleted_at` is cleared, then trash refs
  pointing at this entity are re-applied conservatively.

  Everything in one transaction. Callers write one-liners:

      def delete_sequence(seq), do: Storyarn.Shared.Trashable.soft_delete(seq)
      def restore_sequence(seq), do: Storyarn.Shared.Trashable.restore(seq)

  ## Registry (central map, Variant 2 from the 2026-04-21 design call)

  - `@targets`: `schema_module => target_type_atom`. The atom matches
    `Storyarn.Flows.EntityTrashRefs` target types.
  - `@inbound_refs`: `target_type => [{source_schema, source_path}, ...]`
    where `source_path` is `:column_atom` or `{:jsonb, :column_atom, "key"}`.

  ## Source-type dispatch

  Every source schema maps to a `source_type` string consumed by
  `EntityTrashRefs`. Hardcoded here until sheets/scenes have their own
  trash tables and need dispatch by source-domain.

  Relations registered:

    * `:flow` ← `flow_nodes.data["referenced_flow_id"]`

  The `:flow_sequence` entry was removed in Phase 1 of the flow relational
  refactor: sequences are now `flow_nodes` rows with `type='sequence'` and
  inbound refs via `flow_nodes.parent_id` are handled by a DB trigger,
  not this sweep machinery.

  NOT registered yet:

    * `flow_node` (hub) ← `flow_nodes.data["target_hub_id"]` — the value stored
      in `target_hub_id` is the user-defined `hub_id` STRING, not the hub node's
      integer PK. `EntityTrashRefs.sweep_jsonb_field/6` only supports integer-PK
      lookup. Needs a new sweep path that handles string-id lookups. Until then,
      `NodeDelete.clear_orphaned_jumps/2` keeps handling this (no restore path).
  """

  alias Storyarn.Flows.EntityTrashRefs
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  @targets %{
    Flow => :flow
  }

  @inbound_refs %{
    flow: [
      {FlowNode, {:jsonb, :data, "referenced_flow_id"}}
    ]
  }

  @source_type_for %{
    FlowNode => "flow_node"
  }

  @doc """
  Soft-delete an entity and sweep every inbound ref declared for its type.

  Returns `{:ok, deleted_entity}` or `{:error, changeset}`.
  """
  @spec soft_delete(struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  def soft_delete(%_{} = entity) do
    target_type = target_type!(entity)
    refs = Map.get(@inbound_refs, target_type, [])

    Repo.transaction(fn ->
      case soft_delete_entity(entity) do
        {:ok, deleted} ->
          Enum.each(refs, &perform_sweep(&1, target_type, deleted.id))
          deleted

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Restore a soft-deleted entity and re-apply trash refs pointing at it
  (conservative — only nil live fields are re-populated).

  Returns `{:ok, restored_entity}` or `{:error, changeset}`.
  """
  @spec restore(struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  def restore(%_{} = entity) do
    target_type = target_type!(entity)

    Repo.transaction(fn ->
      case restore_entity(entity) do
        {:ok, restored} ->
          {:ok, _} = EntityTrashRefs.restore(target_type, restored.id)
          restored

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Returns the registered target_type atom for an entity (or its schema module).
  Raises if the schema is not in the registry.
  """
  @spec target_type!(struct() | module()) :: atom()
  def target_type!(%_{} = entity), do: target_type!(entity.__struct__)

  def target_type!(schema) when is_atom(schema) do
    case Map.fetch(@targets, schema) do
      {:ok, type} -> type
      :error -> raise ArgumentError, "#{inspect(schema)} is not registered in Trashable"
    end
  end

  @doc "Returns the inbound refs registered for a target_type. Returns [] if none."
  @spec inbound_refs(atom()) :: [tuple()]
  def inbound_refs(target_type), do: Map.get(@inbound_refs, target_type, [])

  # ===========================================================================
  # Private
  # ===========================================================================

  defp soft_delete_entity(entity) do
    entity
    |> Ecto.Changeset.change(%{deleted_at: TimeHelpers.now()})
    |> Repo.update()
  end

  defp restore_entity(entity) do
    entity
    |> Ecto.Changeset.change(%{deleted_at: nil})
    |> Repo.update()
  end

  defp perform_sweep({source_schema, source_path}, target_type, target_id) do
    source_type = Map.fetch!(@source_type_for, source_schema)

    case source_path do
      column when is_atom(column) ->
        EntityTrashRefs.sweep_column(
          source_schema,
          source_type,
          column,
          target_type,
          target_id
        )

      {:jsonb, jsonb_column, jsonb_key} ->
        EntityTrashRefs.sweep_jsonb_field(
          source_schema,
          source_type,
          jsonb_column,
          jsonb_key,
          target_type,
          target_id
        )
    end
  end
end
