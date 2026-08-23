defmodule Storyarn.Scenes.Versioning.ConflictDetector do
  @moduledoc """
  Scene-owned, read-only preview of conflicts that would block a restore.

  The preview reads shared tables through Scene-local records. The restore
  itself remains authoritative and repeats these checks under its locks.
  """

  use Gettext, backend: Storyarn.Gettext

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Scenes.Persistence.AssetRecord
  alias Storyarn.Scenes.Persistence.FlowRecord
  alias Storyarn.Scenes.Persistence.SheetRecord
  alias Storyarn.Scenes.ProjectReferenceIntegrity
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.Versioning.AssetHashResolver
  alias Storyarn.Scenes.Versioning.SceneSnapshot

  @type_to_schema %{
    flow: FlowRecord,
    scene: Scene,
    sheet: SheetRecord
  }

  @doc "Returns the conflict report consumed by the Scene version-history UI."
  @spec detect(map(), Scene.t()) :: map()
  def detect(snapshot, %Scene{} = scene) when is_map(snapshot) do
    references = Enum.map(SceneSnapshot.scan_references(snapshot), &normalize_reference/1)

    missing =
      find_missing_references(references, scene.project_id, snapshot) ++
        variable_conflicts(snapshot, scene.project_id)

    conflicts = group_conflicts(missing)
    {shortcut_collision, resolved_shortcut} = shortcut_collision(scene, snapshot["shortcut"])

    %{
      has_conflicts: conflicts != [] or shortcut_collision,
      conflicts: conflicts,
      shortcut_collision: shortcut_collision,
      resolved_shortcut: resolved_shortcut,
      summary: summary(conflicts, shortcut_collision)
    }
  end

  defp find_missing_references([], _project_id, _snapshot), do: []

  defp find_missing_references(references, project_id, snapshot) do
    references
    |> Enum.group_by(& &1.type)
    |> Enum.flat_map(fn {type, entries} ->
      ids = entries |> Enum.flat_map(&queryable_reference_id/1) |> Enum.uniq()
      existing = existing_references(type, ids, project_id)

      Enum.reject(entries, &materializable?(&1, existing, snapshot, project_id))
    end)
  end

  defp materializable?(%{type: :asset, id: asset_id}, existing, snapshot, project_id) do
    portable_asset?(asset_id, snapshot, project_id) and
      active_asset_matches_snapshot?(asset_id, existing, snapshot)
  end

  defp materializable?(%{id: id}, existing, _snapshot, _project_id), do: is_integer(id) and MapSet.member?(existing, id)

  defp portable_asset?(asset_id, snapshot, project_id) when is_integer(asset_id) and asset_id > 0 do
    id = to_string(asset_id)

    with %{} = blob_hashes <- snapshot["asset_blob_hashes"],
         %{} = metadata_by_id <- snapshot["asset_metadata"],
         blob_hash when is_binary(blob_hash) <- blob_hashes[id],
         %{} = metadata <- metadata_by_id[id],
         {:ok, ^project_id} <-
           AssetHashResolver.validate_portable_catalog_entry(
             blob_hash,
             metadata,
             project_id
           ),
         true <- String.starts_with?(metadata["content_type"], "image/") do
      true
    else
      _invalid_or_incomplete_catalog -> false
    end
  end

  defp portable_asset?(_asset_id, _snapshot, _project_id), do: false

  defp active_asset_matches_snapshot?(asset_id, existing, snapshot) do
    case Map.get(existing, asset_id) do
      nil ->
        true

      %AssetRecord{} = asset ->
        id = to_string(asset_id)
        metadata = get_in(snapshot, ["asset_metadata", id])

        is_map(metadata) and
          asset.blob_hash == get_in(snapshot, ["asset_blob_hashes", id]) and
          asset.filename == metadata["filename"] and
          asset.content_type == metadata["content_type"] and
          asset.size == metadata["size"] and
          sanitized_svg?(asset.metadata) == (metadata["sanitized_svg"] == true)
    end
  end

  defp existing_references(:asset, [], _project_id), do: %{}

  defp existing_references(:asset, ids, project_id) do
    from(asset in AssetRecord,
      where:
        asset.id in ^ids and asset.project_id == ^project_id and
          is_nil(asset.deleted_at)
    )
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp existing_references(_type, [], _project_id), do: MapSet.new()

  defp existing_references(type, ids, project_id) do
    schema = Map.fetch!(@type_to_schema, type)

    from(record in schema,
      where:
        record.id in ^ids and field(record, :project_id) == ^project_id and
          is_nil(field(record, :deleted_at)),
      select: record.id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp variable_conflicts(snapshot, project_id) do
    case SceneSnapshot.validate_variable_references(snapshot, project_id) do
      :ok -> []
      {:error, reason} -> [variable_conflict(reason)]
    end
  end

  defp variable_conflict({:unresolved_variable_reference, source_type, source_id, kind, source_sheet, source_variable}) do
    %{
      type: :variable,
      id: "#{source_sheet}.#{source_variable}",
      context:
        dgettext(
          "versioning",
          "%{source} #%{id} — unresolved %{kind} variable",
          source: variable_source_label(source_type),
          id: source_id,
          kind: variable_kind_label(kind)
        )
    }
  end

  defp variable_conflict({:malformed_variable_reference, source_type, source_id, _context, _value}) do
    %{
      type: :variable,
      id: nil,
      context:
        dgettext(
          "versioning",
          "%{source} #%{id} — malformed variable reference",
          source: variable_source_label(source_type),
          id: source_id
        )
    }
  end

  defp variable_conflict(_reason) do
    %{
      type: :variable,
      id: nil,
      context: dgettext("versioning", "Snapshot variable references could not be validated")
    }
  end

  defp variable_source_label("scene_pin"), do: dgettext("versioning", "Scene pin")
  defp variable_source_label("scene_zone"), do: dgettext("versioning", "Scene zone")

  defp variable_source_label("scene_ambient_flow"), do: dgettext("versioning", "Scene ambient flow")

  defp variable_source_label(_source_type), do: dgettext("versioning", "Snapshot source")

  defp variable_kind_label("read"), do: dgettext("versioning", "read")
  defp variable_kind_label("write"), do: dgettext("versioning", "write")
  defp variable_kind_label(_kind), do: dgettext("versioning", "referenced")

  defp normalize_reference(%{id: id} = reference) do
    case ProjectReferenceIntegrity.normalize_optional_id(id) do
      {:ok, normalized_id} -> %{reference | id: normalized_id}
      :error -> reference
    end
  end

  defp queryable_reference_id(%{id: id}) do
    case ProjectReferenceIntegrity.normalize_optional_id(id) do
      {:ok, normalized_id} when is_integer(normalized_id) -> [normalized_id]
      _invalid_or_absent -> []
    end
  end

  defp group_conflicts(conflicts) do
    conflicts
    |> Enum.group_by(&{&1.type, &1.id})
    |> Enum.map(fn {{type, id}, entries} ->
      %{type: type, id: id, contexts: entries |> Enum.map(& &1.context) |> Enum.uniq()}
    end)
    |> Enum.sort_by(&{&1.type, &1.id})
  end

  defp shortcut_collision(_scene, nil), do: {false, nil}

  defp shortcut_collision(scene, shortcut) when is_binary(shortcut) do
    collision? =
      Repo.exists?(
        from(candidate in Scene,
          where:
            candidate.project_id == ^scene.project_id and candidate.id != ^scene.id and
              candidate.shortcut == ^shortcut and is_nil(candidate.deleted_at)
        )
      )

    if collision?, do: {true, shortcut <> "-restored"}, else: {false, shortcut}
  end

  defp shortcut_collision(_scene, shortcut), do: {false, shortcut}

  defp summary([], false), do: nil

  defp summary(conflicts, shortcut_collision) do
    parts =
      conflicts
      |> Enum.group_by(& &1.type)
      |> Enum.map(fn {type, entries} ->
        count = length(entries)

        dngettext("versioning", "%{count} missing %{type}", "%{count} missing %{type}", count,
          count: count,
          type: type_label(type, count)
        )
      end)

    parts =
      if shortcut_collision,
        do: parts ++ [dgettext("versioning", "shortcut collision")],
        else: parts

    Enum.join(parts, ", ")
  end

  defp type_label(:asset, count), do: dngettext("versioning", "asset", "assets", count)
  defp type_label(:sheet, count), do: dngettext("versioning", "sheet", "sheets", count)
  defp type_label(:flow, count), do: dngettext("versioning", "flow", "flows", count)
  defp type_label(:scene, count), do: dngettext("versioning", "scene", "scenes", count)
  defp type_label(:variable, count), do: dngettext("versioning", "variable", "variables", count)

  defp sanitized_svg?(%{"sanitized_svg" => true}), do: true
  defp sanitized_svg?(_metadata), do: false
end
