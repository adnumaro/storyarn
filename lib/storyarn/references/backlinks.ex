defmodule Storyarn.References.Backlinks do
  @moduledoc """
  Read paths for entity backlinks.

  Legacy editor reads remain delegated to `Sheets.ReferenceTracker`; bounded,
  normalized lookup reads live here under the canonical References context.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.References.EntityReference
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneZone
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.ReferenceTracker
  alias Storyarn.Sheets.Sheet

  @default_limit 25
  @max_limit 50

  defdelegate get_backlinks(target_type, target_id), to: ReferenceTracker
  defdelegate get_backlinks_with_sources(target_type, target_id, project_id), to: ReferenceTracker
  defdelegate count_backlinks(target_type, target_id), to: ReferenceTracker

  @doc """
  Returns a bounded, normalized page of active sources that reference a target.

  This read model intentionally excludes block values, node data, scene action
  data and every other authored JSON field.
  """
  @spec list_entity_usages(String.t(), integer(), integer(), keyword()) ::
          %{items: [map()], truncated: boolean()}
  def list_entity_usages(target_type, target_id, project_id, opts \\ [])

  def list_entity_usages(target_type, target_id, project_id, opts) when target_type in ~w(sheet flow scene) do
    limit = bounded_limit(opts)
    fetch_limit = limit + 1

    items =
      block_usages(target_type, target_id, project_id, fetch_limit) ++
        flow_usages(target_type, target_id, project_id, fetch_limit) ++
        pin_usages(target_type, target_id, project_id, fetch_limit) ++
        zone_usages(target_type, target_id, project_id, fetch_limit)

    items =
      Enum.sort(items, fn left, right ->
        case NaiveDateTime.compare(left.inserted_at, right.inserted_at) do
          :gt -> true
          :lt -> false
          :eq -> left.reference_id > right.reference_id
        end
      end)

    %{items: Enum.take(items, limit), truncated: length(items) > limit}
  end

  def list_entity_usages(_target_type, _target_id, _project_id, _opts), do: %{items: [], truncated: false}

  defp block_usages(target_type, target_id, project_id, limit) do
    Repo.all(
      from(reference in EntityReference,
        join: block in Block,
        on: reference.source_type == "block" and reference.source_id == block.id,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where:
          reference.target_type == ^target_type and reference.target_id == ^target_id and
            sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and
            is_nil(block.deleted_at),
        order_by: [desc: reference.inserted_at, desc: reference.id],
        limit: ^limit,
        select: %{
          reference_id: reference.id,
          source_type: :block,
          source_id: block.id,
          source_kind: block.type,
          source_label: fragment("NULLIF(?->>'label', '')", block.config),
          container_type: :sheet,
          container_id: sheet.id,
          container_name: sheet.name,
          inserted_at: reference.inserted_at,
          reference_context: reference.context
        }
      )
    )
  end

  defp flow_usages(target_type, target_id, project_id, limit) do
    Repo.all(
      from(reference in EntityReference,
        join: node in FlowNode,
        on: reference.source_type == "flow_node" and reference.source_id == node.id,
        join: flow in Flow,
        on: flow.id == node.flow_id,
        where:
          reference.target_type == ^target_type and reference.target_id == ^target_id and
            flow.project_id == ^project_id and is_nil(flow.deleted_at) and
            is_nil(node.deleted_at),
        order_by: [desc: reference.inserted_at, desc: reference.id],
        limit: ^limit,
        select: %{
          reference_id: reference.id,
          source_type: :flow_node,
          source_id: node.id,
          source_kind: node.type,
          source_label: nil,
          container_type: :flow,
          container_id: flow.id,
          container_name: flow.name,
          inserted_at: reference.inserted_at,
          reference_context: reference.context
        }
      )
    )
  end

  defp pin_usages(target_type, target_id, project_id, limit) do
    Repo.all(
      from(reference in EntityReference,
        join: pin in ScenePin,
        on: reference.source_type == "scene_pin" and reference.source_id == pin.id,
        join: scene in Scene,
        on: scene.id == pin.scene_id,
        where:
          reference.target_type == ^target_type and reference.target_id == ^target_id and
            scene.project_id == ^project_id and is_nil(scene.deleted_at),
        order_by: [desc: reference.inserted_at, desc: reference.id],
        limit: ^limit,
        select: %{
          reference_id: reference.id,
          source_type: :scene_pin,
          source_id: pin.id,
          source_kind: "pin",
          source_label: pin.label,
          container_type: :scene,
          container_id: scene.id,
          container_name: scene.name,
          inserted_at: reference.inserted_at,
          reference_context: reference.context
        }
      )
    )
  end

  defp zone_usages(target_type, target_id, project_id, limit) do
    Repo.all(
      from(reference in EntityReference,
        join: zone in SceneZone,
        on: reference.source_type == "scene_zone" and reference.source_id == zone.id,
        join: scene in Scene,
        on: scene.id == zone.scene_id,
        where:
          reference.target_type == ^target_type and reference.target_id == ^target_id and
            scene.project_id == ^project_id and is_nil(scene.deleted_at),
        order_by: [desc: reference.inserted_at, desc: reference.id],
        limit: ^limit,
        select: %{
          reference_id: reference.id,
          source_type: :scene_zone,
          source_id: zone.id,
          source_kind: "zone",
          source_label: zone.name,
          container_type: :scene,
          container_id: scene.id,
          container_name: scene.name,
          inserted_at: reference.inserted_at,
          reference_context: reference.context
        }
      )
    )
  end

  defp bounded_limit(opts) do
    opts
    |> Keyword.get(:limit, @default_limit)
    |> max(1)
    |> min(@max_limit)
  end
end
