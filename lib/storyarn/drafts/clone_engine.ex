defmodule Storyarn.Drafts.CloneEngine do
  @moduledoc """
  Materializes draft entities from canonical snapshots.

  `CloneEngine` remains the draft-facing adapter, but the copy semantics now
  come from `Versioning` builders instead of handwritten per-table cloning SQL.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Flows.{Flow, FlowNode}
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Versioning

  @doc """
  Builds a snapshot for the source entity if it exists and is eligible for drafts.
  """
  def build_source_snapshot(entity_type, project_id, source_id) do
    builder = Versioning.get_builder!(entity_type)

    case load_source_entity(entity_type, project_id, source_id) do
      nil -> {:error, :source_not_found}
      source -> {:ok, builder.build_snapshot(source)}
    end
  end

  @doc """
  Clones the source entity by materializing a fresh entity from its snapshot.
  Must be called within a transaction.
  """
  def clone(entity_type, project_id, source_id, draft_id) do
    builder = Versioning.get_builder!(entity_type)

    with {:ok, snapshot} <- build_source_snapshot(entity_type, project_id, source_id),
         {:ok, entity, _id_maps} <-
           builder.instantiate_snapshot(project_id, snapshot,
             draft_id: draft_id,
             reset_shortcut: true,
             preserve_external_refs: true
           ) do
      {:ok, entity}
    end
  end

  @doc """
  Returns the name of the source entity, or nil if not found.
  """
  def get_source_name("sheet", project_id, source_id) do
    from(s in Sheet,
      where:
        s.id == ^source_id and s.project_id == ^project_id and is_nil(s.deleted_at) and
          is_nil(s.draft_id),
      select: s.name
    )
    |> Repo.one()
  end

  def get_source_name("flow", project_id, source_id) do
    from(f in Flow,
      where:
        f.id == ^source_id and f.project_id == ^project_id and is_nil(f.deleted_at) and
          is_nil(f.draft_id),
      select: f.name
    )
    |> Repo.one()
  end

  def get_source_name("scene", project_id, source_id) do
    from(s in Scene,
      where:
        s.id == ^source_id and s.project_id == ^project_id and is_nil(s.deleted_at) and
          is_nil(s.draft_id),
      select: s.name
    )
    |> Repo.one()
  end

  @doc """
  Gets the cloned entity for a draft.
  """
  def get_draft_entity("sheet", draft_id) do
    from(s in Sheet,
      where: s.draft_id == ^draft_id,
      preload: [:blocks, :avatar_asset, :banner_asset]
    )
    |> Repo.one()
  end

  def get_draft_entity("flow", draft_id) do
    active_nodes =
      from(n in FlowNode, where: is_nil(n.deleted_at), order_by: [asc: n.inserted_at])

    from(f in Flow,
      where: f.draft_id == ^draft_id,
      preload: [:connections, nodes: ^active_nodes]
    )
    |> Repo.one()
  end

  def get_draft_entity("scene", draft_id) do
    from(s in Scene,
      where: s.draft_id == ^draft_id,
      preload: [
        :layers,
        :zones,
        [pins: [:icon_asset, sheet: :avatar_asset]],
        :annotations,
        :background_asset,
        connections: [:from_pin, :to_pin]
      ]
    )
    |> Repo.one()
  end

  @doc """
  Deletes the cloned entity for a draft (hard delete).
  """
  def delete_draft_entity("sheet", draft_id) do
    from(s in Sheet, where: s.draft_id == ^draft_id) |> Repo.delete_all()
  end

  def delete_draft_entity("flow", draft_id) do
    from(f in Flow, where: f.draft_id == ^draft_id) |> Repo.delete_all()
  end

  def delete_draft_entity("scene", draft_id) do
    from(s in Scene, where: s.draft_id == ^draft_id) |> Repo.delete_all()
  end

  defp load_source_entity(entity_type, project_id, source_id) do
    schema = entity_schema(entity_type)

    from(e in schema,
      where:
        e.id == ^source_id and e.project_id == ^project_id and is_nil(e.deleted_at) and
          is_nil(e.draft_id)
    )
    |> Repo.one()
  end

  defp entity_schema("sheet"), do: Sheet
  defp entity_schema("flow"), do: Flow
  defp entity_schema("scene"), do: Scene
end
