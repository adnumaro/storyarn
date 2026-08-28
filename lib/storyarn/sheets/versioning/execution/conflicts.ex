defmodule Storyarn.Sheets.Versioning.Execution.Conflicts do
  @moduledoc """
  Sheet-owned, read-only preview of conflicts that would block a restore.

  The preview reads shared tables through Sheet-local records. The restore
  itself remains authoritative and repeats these checks under its locks.
  """

  use Gettext, backend: Storyarn.Gettext

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.References
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.SheetAvatar
  alias Storyarn.Sheets.Versioning.Commands.AssetHashResolver
  alias Storyarn.Sheets.Versioning.Entities.AssetRecord, as: Asset
  alias Storyarn.Sheets.Versioning.Projections.FlowRecord, as: Flow
  alias Storyarn.Sheets.Versioning.Projections.SceneRecord, as: Scene
  alias Storyarn.Sheets.Versioning.SheetSnapshot

  @type_to_schema %{
    asset: Asset,
    sheet: Sheet,
    flow: Flow,
    scene: Scene,
    block: Block
  }

  @doc """
  Detects conflicts in a snapshot before restoring.

  Returns a report with:
  - `has_conflicts` - whether any conflicts were found
  - `conflicts` - list of grouped conflicts by type
  - `shortcut_collision` - whether the snapshot's shortcut collides with another sheet
  - `resolved_shortcut` - the shortcut that will be used (with "-restored" suffix if collision)
  """
  @spec detect(map(), Sheet.t()) :: map()
  def detect(snapshot, %Sheet{} = sheet) when is_map(snapshot) do
    references = SheetSnapshot.scan_references(snapshot)

    missing = find_missing_references(references, sheet.project_id, snapshot)

    grouped = group_conflicts(missing)
    {shortcut_collision, resolved_shortcut} = check_shortcut_collision(sheet, snapshot)

    %{
      has_conflicts: grouped != [] or shortcut_collision,
      conflicts: grouped,
      shortcut_collision: shortcut_collision,
      resolved_shortcut: resolved_shortcut,
      summary: build_summary(grouped, shortcut_collision)
    }
  end

  defp find_missing_references([], _project_id, _snapshot), do: []

  defp find_missing_references(references, project_id, snapshot) do
    # Normalize IDs to integers — snapshot data may store FKs as strings
    references
    |> Enum.map(&normalize_reference_ids/1)
    |> Enum.group_by(& &1.type)
    |> Enum.flat_map(fn {type, refs} ->
      ids = refs |> Enum.flat_map(&queryable_reference_id/1) |> Enum.uniq()
      existing_ids = existing_reference_ids(type, ids, project_id)

      Enum.reject(refs, fn ref ->
        reference_materializable?(ref, existing_ids, project_id, snapshot)
      end)
    end)
  end

  defp reference_materializable?(%{type: :asset} = ref, existing_assets, project_id, snapshot) do
    restorable_from_snapshot_catalog?(ref, project_id, snapshot) and
      active_asset_matches_snapshot_catalog?(ref.id, existing_assets, snapshot)
  end

  defp reference_materializable?(ref, existing_ids, _project_id, _snapshot) do
    reference_exists?(ref, existing_ids)
  end

  defp reference_exists?(%{type: :avatar, id: avatar_id, speaker_sheet_id: speaker_sheet_id}, existing_avatar_sheets)
       when is_integer(avatar_id) and (is_integer(speaker_sheet_id) or is_nil(speaker_sheet_id)) do
    case Map.fetch(existing_avatar_sheets, avatar_id) do
      {:ok, avatar_sheet_id} ->
        References.validate_avatar_speaker(
          avatar_id,
          avatar_sheet_id,
          speaker_sheet_id
        ) == :ok

      :error ->
        false
    end
  end

  defp reference_exists?(%{type: :avatar}, _existing_pairs), do: false

  defp reference_exists?(ref, existing_ids) do
    is_integer(ref.id) and MapSet.member?(existing_ids, ref.id)
  end

  # Entity restores can recreate a deleted asset from its canonical project blob.
  # Preview deliberately performs no storage I/O, so this only accepts catalog
  # entries that satisfy every pure validation enforced by AssetHashResolver.
  # The restore remains authoritative for blob availability and persisted size.
  defp restorable_from_snapshot_catalog?(%{type: :asset, id: asset_id}, project_id, snapshot)
       when is_integer(asset_id) and asset_id > 0 and is_map(snapshot) do
    with {:ok, ^asset_id} <- References.normalize_optional_id(asset_id),
         %{} = blob_hashes <- snapshot["asset_blob_hashes"],
         %{} = asset_metadata <- snapshot["asset_metadata"],
         blob_hash when is_binary(blob_hash) <- blob_hashes[to_string(asset_id)],
         %{} = metadata <- asset_metadata[to_string(asset_id)],
         {:ok, ^project_id} <-
           AssetHashResolver.validate_portable_catalog_entry(
             blob_hash,
             metadata,
             project_id
           ),
         # Every asset slot in the Sheet builder is image-only.
         true <- String.starts_with?(metadata["content_type"], "image/") do
      true
    else
      _invalid_or_incomplete_catalog -> false
    end
  end

  defp restorable_from_snapshot_catalog?(_ref, _project_id, _snapshot), do: false

  defp active_asset_matches_snapshot_catalog?(asset_id, existing_assets, snapshot) do
    case Map.get(existing_assets, asset_id) do
      nil ->
        true

      %Asset{} = asset ->
        id = to_string(asset_id)
        metadata = get_in(snapshot, ["asset_metadata", id])

        asset.blob_hash == get_in(snapshot, ["asset_blob_hashes", id]) and
          asset.filename == metadata["filename"] and
          asset.content_type == metadata["content_type"] and
          asset.size == metadata["size"] and
          sanitized_svg?(asset.metadata) == (metadata["sanitized_svg"] == true)
    end
  end

  defp sanitized_svg?(%{"sanitized_svg" => true}), do: true
  defp sanitized_svg?(_metadata), do: false

  defp existing_reference_ids(:block, ids, project_id) do
    from(block in Block,
      join: sheet in Sheet,
      on: sheet.id == block.sheet_id,
      where:
        block.id in ^ids and sheet.project_id == ^project_id and is_nil(block.deleted_at) and
          is_nil(sheet.deleted_at),
      select: block.id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp existing_reference_ids(:reference, _ids, _project_id), do: MapSet.new()

  defp existing_reference_ids(:asset, ids, project_id) do
    from(asset in Asset,
      where:
        asset.id in ^ids and asset.project_id == ^project_id and
          is_nil(asset.deleted_at),
      select: asset
    )
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp existing_reference_ids(:avatar, ids, project_id) do
    from(avatar in SheetAvatar,
      join: sheet in Sheet,
      on: sheet.id == avatar.sheet_id,
      where:
        avatar.id in ^ids and sheet.project_id == ^project_id and
          is_nil(sheet.deleted_at),
      select: {avatar.id, avatar.sheet_id}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp existing_reference_ids(type, ids, project_id) do
    schema = Map.fetch!(@type_to_schema, type)

    from(entity in schema,
      where:
        entity.id in ^ids and field(entity, :project_id) == ^project_id and
          is_nil(field(entity, :deleted_at)),
      select: entity.id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp normalize_ref_id(%{id: id} = ref) do
    case References.normalize_optional_id(id) do
      {:ok, normalized_id} when is_integer(normalized_id) -> %{ref | id: normalized_id}
      _invalid_or_absent -> ref
    end
  end

  defp normalize_ref_id(%{} = ref), do: Map.put(ref, :id, nil)

  defp normalize_reference_ids(ref) do
    ref
    |> normalize_ref_id()
    |> normalize_avatar_speaker_id()
  end

  defp normalize_avatar_speaker_id(%{type: :avatar, speaker_sheet_id: speaker_sheet_id} = ref) do
    Map.put(ref, :speaker_sheet_id, normalize_optional_reference_id(speaker_sheet_id))
  end

  defp normalize_avatar_speaker_id(ref), do: ref

  defp normalize_optional_reference_id(value) do
    case References.normalize_optional_id(value) do
      {:ok, normalized_id} -> normalized_id
      :error -> value
    end
  end

  defp queryable_reference_id(%{id: id}) do
    case References.normalize_optional_id(id) do
      {:ok, normalized_id} when is_integer(normalized_id) -> [normalized_id]
      _invalid_or_absent -> []
    end
  end

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

  defp check_shortcut_collision(sheet, snapshot) do
    shortcut = snapshot["shortcut"]

    if shortcut && shortcut_taken?(sheet, shortcut) do
      {true, shortcut <> "-restored"}
    else
      {false, shortcut}
    end
  end

  defp shortcut_taken?(sheet, shortcut) do
    Repo.exists?(
      from(candidate in Sheet,
        where:
          candidate.shortcut == ^shortcut and candidate.project_id == ^sheet.project_id and
            candidate.id != ^sheet.id and is_nil(candidate.deleted_at)
      )
    )
  end

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

  defp type_label(:asset, count), do: dngettext("versioning", "asset", "assets", count)

  defp type_label(:sheet, count), do: dngettext("versioning", "sheet", "sheets", count)

  defp type_label(:flow, count), do: dngettext("versioning", "flow", "flows", count)

  defp type_label(:scene, count), do: dngettext("versioning", "scene", "scenes", count)

  defp type_label(:block, count), do: dngettext("versioning", "block", "blocks", count)

  defp type_label(:reference, count), do: dngettext("versioning", "reference", "references", count)

  defp type_label(:avatar, count), do: dngettext("versioning", "avatar", "avatars", count)

  defp type_label(:variable, count), do: dngettext("versioning", "variable", "variables", count)
end
