defmodule Storyarn.Versioning.ConflictDetector do
  @moduledoc """
  Detects conflicts that would occur when restoring an entity from a snapshot.

  Scans the snapshot for external references (foreign keys to sheets, flows,
  scenes, assets) and checks which ones no longer exist. Also detects shortcut
  collisions with other entities.
  """

  use Gettext, backend: Storyarn.Gettext

  import Ecto.Query, warn: false

  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.Storage
  alias Storyarn.Flows.Flow
  alias Storyarn.References.ProjectReferenceIntegrity
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.SheetAvatar
  alias Storyarn.Versioning.VersionCrud

  @sha256_regex ~r/\A[0-9a-f]{64}\z/
  @max_asset_size 52_428_800

  @type_to_schema %{
    asset: Asset,
    sheet: Sheet,
    flow: Flow,
    scene: Scene,
    block: Block
  }

  @entity_type_to_schema %{
    "sheet" => Sheet,
    "flow" => Flow,
    "scene" => Scene
  }

  @doc """
  Detects conflicts in a snapshot before restoring.

  Returns a report with:
  - `has_conflicts` - whether any conflicts were found
  - `conflicts` - list of grouped conflicts by type
  - `shortcut_collision` - whether the snapshot's shortcut collides with another entity
  - `resolved_shortcut` - the shortcut that will be used (with "-restored" suffix if collision)
  - `auto_resolved` - list of issues the restore can resolve without data loss
  """
  @spec detect_conflicts(String.t(), map(), struct()) :: map()
  def detect_conflicts(entity_type, snapshot, entity) do
    builder = VersionCrud.get_builder!(entity_type)
    references = extract_references(builder, snapshot)
    missing = find_missing_references(references, entity.project_id, entity_type, snapshot)
    grouped = group_conflicts(missing)

    {shortcut_collision, resolved_shortcut} =
      check_shortcut_collision(entity_type, entity, snapshot)

    %{
      has_conflicts: grouped != [] or shortcut_collision,
      conflicts: grouped,
      shortcut_collision: shortcut_collision,
      resolved_shortcut: resolved_shortcut,
      auto_resolved: [],
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

  defp find_missing_references([], _project_id, _entity_type, _snapshot), do: []

  defp find_missing_references(references, project_id, entity_type, snapshot) do
    # Normalize IDs to integers — snapshot data may store FKs as strings
    references
    |> Enum.map(&normalize_reference_ids/1)
    |> Enum.group_by(& &1.type)
    |> Enum.flat_map(fn {type, refs} ->
      ids = refs |> Enum.flat_map(&queryable_reference_id/1) |> Enum.uniq()
      existing_ids = existing_reference_ids(type, ids, project_id)

      Enum.reject(refs, fn ref ->
        reference_materializable?(ref, existing_ids, project_id, entity_type, snapshot)
      end)
    end)
  end

  defp reference_materializable?(%{type: :asset} = ref, existing_assets, project_id, entity_type, snapshot) do
    restorable_from_snapshot_catalog?(ref, project_id, entity_type, snapshot) and
      active_asset_matches_snapshot_catalog?(ref.id, existing_assets, snapshot)
  end

  defp reference_materializable?(ref, existing_ids, _project_id, _entity_type, _snapshot) do
    reference_exists?(ref, existing_ids)
  end

  defp reference_exists?(%{type: :avatar, id: avatar_id, speaker_sheet_id: speaker_sheet_id}, existing_pairs) do
    is_integer(avatar_id) and is_integer(speaker_sheet_id) and
      MapSet.member?(existing_pairs, {avatar_id, speaker_sheet_id})
  end

  defp reference_exists?(%{type: :avatar}, _existing_pairs), do: false

  defp reference_exists?(ref, existing_ids) do
    is_integer(ref.id) and MapSet.member?(existing_ids, ref.id)
  end

  # Entity restores can recreate a deleted asset from its canonical project blob.
  # Preview deliberately performs no storage I/O, so this only accepts catalog
  # entries that satisfy every pure validation enforced by AssetHashResolver.
  # The restore remains authoritative for blob availability and persisted size.
  defp restorable_from_snapshot_catalog?(%{type: :asset, id: asset_id} = ref, project_id, entity_type, snapshot)
       when is_integer(asset_id) and asset_id > 0 and is_map(snapshot) do
    with {:ok, ^asset_id} <- ProjectReferenceIntegrity.normalize_optional_id(asset_id),
         expected_prefix when expected_prefix in ["audio/", "image/"] <-
           expected_asset_content_type_prefix(ref, entity_type),
         %{} = blob_hashes <- snapshot["asset_blob_hashes"],
         %{} = asset_metadata <- snapshot["asset_metadata"],
         blob_hash when is_binary(blob_hash) <- blob_hashes[to_string(asset_id)],
         true <- Regex.match?(@sha256_regex, blob_hash),
         %{} = metadata <- asset_metadata[to_string(asset_id)],
         true <- valid_portable_asset_metadata?(metadata, project_id, expected_prefix) do
      true
    else
      _invalid_or_incomplete_catalog -> false
    end
  end

  defp restorable_from_snapshot_catalog?(_ref, _project_id, _entity_type, _snapshot), do: false

  defp expected_asset_content_type_prefix(%{expected_content_type_prefix: prefix}, _entity_type), do: prefix

  # Every asset slot in Sheet and Scene builders is image-only. Flow asset refs
  # carry their slot-specific prefix because a flow contains both image and audio
  # references.
  defp expected_asset_content_type_prefix(_ref, entity_type) when entity_type in ["sheet", "scene"], do: "image/"

  defp expected_asset_content_type_prefix(_ref, _entity_type), do: nil

  defp valid_portable_asset_metadata?(metadata, project_id, expected_prefix) do
    filename = metadata["filename"]
    content_type = metadata["content_type"]
    size = metadata["size"]

    valid_asset_filename?(filename) and
      valid_asset_content_type?(metadata) and
      String.starts_with?(content_type, expected_prefix) and
      is_integer(size) and size > 0 and size <= @max_asset_size and
      metadata["project_id"] == project_id
  end

  defp valid_asset_filename?(filename) when is_binary(filename) do
    if String.valid?(filename) and String.trim(filename) != "" do
      sanitized = Assets.sanitize_filename(filename)

      sanitized not in ["", ".", ".."] and
        not String.contains?(sanitized, "/") and
        Storage.canonical_key?(sanitized)
    else
      false
    end
  end

  defp valid_asset_filename?(_filename), do: false

  defp valid_asset_content_type?(%{"content_type" => "image/svg+xml", "sanitized_svg" => true}), do: true

  defp valid_asset_content_type?(%{"content_type" => content_type}), do: Asset.allowed_content_type?(content_type)

  defp valid_asset_content_type?(_metadata), do: false

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
    |> MapSet.new()
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
    case ProjectReferenceIntegrity.normalize_optional_id(id) do
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
    case ProjectReferenceIntegrity.normalize_optional_id(value) do
      {:ok, normalized_id} when is_integer(normalized_id) -> normalized_id
      _invalid_or_absent -> value
    end
  end

  defp queryable_reference_id(%{id: id}) do
    case ProjectReferenceIntegrity.normalize_optional_id(id) do
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

    Repo.exists?(
      from(e in schema,
        where:
          e.shortcut == ^shortcut and e.project_id == ^entity.project_id and e.id != ^entity.id and is_nil(e.deleted_at)
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
end
