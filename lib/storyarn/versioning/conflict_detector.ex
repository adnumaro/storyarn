defmodule Storyarn.Versioning.ConflictDetector do
  @moduledoc """
  Detects conflicts that would occur when restoring an entity from a snapshot.

  Scans the snapshot for external references (foreign keys to sheets, flows,
  scenes, assets) and checks which ones no longer exist. Also detects shortcut
  collisions with other entities.
  """

  import Ecto.Query, warn: false
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Repo
  alias Storyarn.Versioning.VersionCrud

  @type_to_schema %{
    asset: Storyarn.Assets.Asset,
    sheet: Storyarn.Sheets.Sheet,
    flow: Storyarn.Flows.Flow,
    scene: Storyarn.Scenes.Scene,
    block: Storyarn.Sheets.Block
  }

  @entity_type_to_schema %{
    "sheet" => Storyarn.Sheets.Sheet,
    "flow" => Storyarn.Flows.Flow,
    "scene" => Storyarn.Scenes.Scene
  }

  @doc """
  Detects conflicts in a snapshot before restoring.

  Returns a report with:
  - `has_conflicts` - whether any conflicts were found
  - `conflicts` - list of grouped conflicts by type
  - `shortcut_collision` - whether the snapshot's shortcut collides with another entity
  - `resolved_shortcut` - the shortcut that will be used (with "-restored" suffix if collision)
  - `auto_resolved` - list of auto-resolved issues (e.g., detached block inheritance)
  """
  @spec detect_conflicts(String.t(), map(), struct()) :: map()
  def detect_conflicts(entity_type, snapshot, entity) do
    builder = VersionCrud.get_builder!(entity_type)
    references = extract_references(builder, snapshot)
    missing = find_missing_references(references)
    grouped = group_conflicts(missing)

    {shortcut_collision, resolved_shortcut} =
      check_shortcut_collision(entity_type, entity, snapshot)

    auto_resolved = detect_auto_resolved(entity_type, snapshot)

    %{
      has_conflicts: grouped != [] or shortcut_collision,
      conflicts: grouped,
      shortcut_collision: shortcut_collision,
      resolved_shortcut: resolved_shortcut,
      auto_resolved: auto_resolved,
      summary: build_summary(grouped, shortcut_collision)
    }
  end

  defp extract_references(builder, snapshot) do
    Code.ensure_loaded(builder)

    if function_exported?(builder, :scan_references, 1) do
      builder.scan_references(snapshot)
    else
      []
    end
  end

  defp find_missing_references([]), do: []

  defp find_missing_references(references) do
    # Normalize IDs to integers — snapshot data may store FKs as strings
    references
    |> Enum.map(&normalize_ref_id/1)
    |> Enum.reject(&is_nil(&1.id))
    |> Enum.group_by(& &1.type)
    |> Enum.flat_map(fn {type, refs} ->
      schema = Map.fetch!(@type_to_schema, type)
      ids = refs |> Enum.map(& &1.id) |> Enum.uniq()

      existing_ids =
        from(e in schema, where: e.id in ^ids, select: e.id)
        |> Repo.all()
        |> MapSet.new()

      Enum.reject(refs, &MapSet.member?(existing_ids, &1.id))
    end)
  end

  defp normalize_ref_id(%{id: id} = ref) when is_integer(id), do: ref

  defp normalize_ref_id(%{id: id} = ref) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} -> %{ref | id: int_id}
      _ -> %{ref | id: nil}
    end
  end

  defp normalize_ref_id(%{} = ref), do: %{ref | id: nil}

  defp group_conflicts([]), do: []

  defp group_conflicts(missing) do
    missing
    |> Enum.group_by(&{&1.type, &1.id})
    |> Enum.map(fn {{type, id}, refs} ->
      %{
        type: type,
        id: id,
        contexts: Enum.map(refs, & &1.context)
      }
    end)
    |> Enum.sort_by(&{&1.type, &1.id})
  end

  defp check_shortcut_collision(entity_type, entity, snapshot) do
    shortcut = snapshot["shortcut"]

    if shortcut && shortcut_taken?(entity_type, entity, shortcut) do
      {true, shortcut <> "-restored"}
    else
      {false, shortcut}
    end
  end

  defp shortcut_taken?(entity_type, entity, shortcut) do
    schema = Map.fetch!(@entity_type_to_schema, entity_type)

    from(e in schema,
      where:
        e.shortcut == ^shortcut and
          e.project_id == ^entity.project_id and
          e.id != ^entity.id and
          is_nil(e.deleted_at)
    )
    |> Repo.exists?()
  end

  defp detect_auto_resolved("sheet", snapshot) do
    blocks = snapshot["blocks"] || []

    inherited_count =
      Enum.count(blocks, fn b ->
        b["inherited_from_block_id"] != nil
      end)

    if inherited_count > 0 do
      [
        dgettext(
          "versioning",
          "%{count} inherited blocks will be auto-detached if source blocks are missing",
          count: inherited_count
        )
      ]
    else
      []
    end
  end

  defp detect_auto_resolved(_entity_type, _snapshot), do: []

  defp build_summary([], false), do: nil

  defp build_summary(grouped, shortcut_collision) do
    parts =
      grouped
      |> Enum.group_by(& &1.type)
      |> Enum.map(fn {type, conflicts} ->
        count = length(conflicts)
        type_label = type_label(type, count)

        dngettext("versioning", "%{count} missing %{type}", "%{count} missing %{type}", count,
          count: count,
          type: type_label
        )
      end)

    parts =
      if shortcut_collision do
        parts ++ [dgettext("versioning", "shortcut collision")]
      else
        parts
      end

    Enum.join(parts, ", ")
  end

  defp type_label(:asset, count),
    do: dngettext("versioning", "asset", "assets", count)

  defp type_label(:sheet, count),
    do: dngettext("versioning", "sheet", "sheets", count)

  defp type_label(:flow, count),
    do: dngettext("versioning", "flow", "flows", count)

  defp type_label(:scene, count),
    do: dngettext("versioning", "scene", "scenes", count)

  defp type_label(:block, count),
    do: dngettext("versioning", "block", "blocks", count)
end
