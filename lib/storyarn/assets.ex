defmodule Storyarn.Assets do
  @moduledoc """
  The Assets context.

  Handles file uploads and asset management for projects.
  Supports both local storage (development) and Cloudflare R2 (production).
  """

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.User
  alias Storyarn.Analytics
  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.AssetTrash
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Assets.ImageProcessor
  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Assets.StorageKeyLock
  alias Storyarn.Assets.UploadPolicy
  alias Storyarn.Billing
  alias Storyarn.Collaboration
  alias Storyarn.Flows.EntityTrashRef
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.SequenceConfig
  alias Storyarn.Flows.SequenceTrack
  alias Storyarn.Flows.SequenceVisualLayer
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Projects.Project
  alias Storyarn.References.ProjectReferenceIntegrity
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneZone
  alias Storyarn.Shared.HtmlSanitizer
  alias Storyarn.Shared.SearchHelpers
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.BlockGalleryImage
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.SheetAvatar

  require Logger

  @svg_content_type "image/svg+xml"
  @upload_tracker_process_key {__MODULE__, :upload_storage_tracker}
  @post_commit_variant_jobs_process_key {__MODULE__, :post_commit_variant_jobs}
  @import_capacity_process_key {__MODULE__, :import_capacity}
  @parent_cleanup_asset_batch_size 250
  @snapshot_asset_batch_size 500
  @sha256_regex ~r/\A[0-9a-f]{64}\z/

  # =============================================================================
  # Type Definitions
  # =============================================================================

  @type asset :: Asset.t()
  @type project :: Project.t()
  @type user :: User.t()
  @type changeset :: Ecto.Changeset.t()
  @type attrs :: map()
  @type upload_error :: {:error, term()} | {:error, :limit_reached, map()}
  @type upload_result :: {:ok, asset()} | upload_error()
  @type list_opts :: [
          content_type: String.t(),
          images_only: boolean(),
          search: String.t(),
          limit: non_neg_integer(),
          offset: non_neg_integer()
        ]

  @doc """
  Lists all assets for a project.

  ## Options

    * `:content_type` - Filter by content type prefix (e.g., "image/", "audio/")
    * `:images_only` - Filter to only image assets
    * `:search` - Search by filename
    * `:limit` - Maximum number of assets to return
    * `:offset` - Number of assets to skip

  """
  @spec list_assets(integer(), list_opts()) :: [asset()]
  def list_assets(project_id, opts \\ []) do
    project_id
    |> list_query(opts)
    |> Repo.all()
  end

  # The single filter/order pipeline both listers run. Extracted so a future
  # filter cannot be added to one and forgotten in the other: that would make
  # `list_asset_ids/2` return an id set that is not the row set's ids, silently
  # breaking the reference-existence checks that trust exactly that.
  defp list_query(project_id, opts) do
    from(a in Asset, where: a.project_id == ^project_id and is_nil(a.deleted_at))
    |> apply_content_type_filter(opts)
    |> apply_images_only_filter(opts)
    |> apply_search_filter(opts)
    |> apply_pagination(opts)
    |> order_by([a], desc: a.inserted_at, desc: a.id)
  end

  @doc """
  Lists the IDs of a project's assets, taking the same options as
  `list_assets/2` through the same filters.

  For callers that only need reference-existence checks (scene health, editor
  reference sets) this avoids loading every asset row to throw all but the id
  away — and going through the same filter pipeline is what keeps the id set
  identical to the row set.
  """
  @spec list_asset_ids(integer(), list_opts()) :: [integer()]
  def list_asset_ids(project_id, opts \\ []) do
    project_id
    |> list_query(opts)
    |> select([a], a.id)
    |> Repo.all()
  end

  defp apply_content_type_filter(query, opts) do
    case Keyword.get(opts, :content_type) do
      nil ->
        query

      prefix ->
        sanitized = SearchHelpers.sanitize_like_query(prefix)
        where(query, [a], ilike(a.content_type, ^"#{sanitized}%"))
    end
  end

  defp apply_images_only_filter(query, opts) do
    if Keyword.get(opts, :images_only) do
      where(query, [a], ilike(a.content_type, ^"image/%"))
    else
      query
    end
  end

  defp apply_search_filter(query, opts) do
    case Keyword.get(opts, :search) do
      nil ->
        query

      "" ->
        query

      term ->
        escaped = SearchHelpers.sanitize_like_query(term)
        where(query, [a], ilike(a.filename, ^"%#{escaped}%"))
    end
  end

  defp apply_pagination(query, opts) do
    query
    |> maybe_limit(Keyword.get(opts, :limit))
    |> maybe_offset(Keyword.get(opts, :offset))
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: limit(query, ^limit)

  defp maybe_offset(query, nil), do: query
  defp maybe_offset(query, offset), do: offset(query, ^offset)

  @doc """
  Gets a single asset by ID.

  This lookup does not perform authorization. Callers must authorize access to
  the asset's project before exposing the asset or its storage key.
  """
  @spec get_asset(integer()) :: asset() | nil
  def get_asset(asset_id) do
    Repo.one(from(asset in Asset, where: asset.id == ^asset_id and is_nil(asset.deleted_at)))
  end

  @doc """
  Gets a single asset by ID within a project.

  Returns `nil` if the asset doesn't exist or doesn't belong to the project.
  """
  @spec get_asset(integer(), integer()) :: asset() | nil
  def get_asset(project_id, asset_id) do
    Asset
    |> where([asset], asset.project_id == ^project_id and asset.id == ^asset_id and is_nil(asset.deleted_at))
    |> Repo.one()
  end

  @doc """
  Gets a single asset by ID within a project.

  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_asset!(integer(), integer()) :: asset()
  def get_asset!(project_id, asset_id) do
    Asset
    |> where([asset], asset.project_id == ^project_id and asset.id == ^asset_id and is_nil(asset.deleted_at))
    |> Repo.one!()
  end

  @doc """
  Gets an asset by its storage key.
  """
  @spec get_asset_by_key(integer(), String.t()) :: asset() | nil
  def get_asset_by_key(project_id, key) do
    Asset
    |> where([asset], asset.project_id == ^project_id and asset.key == ^key and is_nil(asset.deleted_at))
    |> Repo.one()
  end

  @doc "Gets a trashed asset by ID within one project."
  @spec get_trashed_asset(integer(), integer()) :: asset() | nil
  def get_trashed_asset(project_id, asset_id) do
    Repo.one(
      from(asset in Asset,
        where:
          asset.project_id == ^project_id and asset.id == ^asset_id and
            not is_nil(asset.deleted_at)
      )
    )
  end

  @doc """
  Creates an asset record.

  This only creates the database record and is intended for records whose
  storage lifecycle is managed elsewhere. Callers must use a fresh,
  globally-unique key and must not split a compensatable storage upload from
  this insert; use `upload_binary_and_create_asset/4` for that atomic lifecycle.
  """
  @spec create_asset(project(), user(), attrs()) ::
          {:ok, asset()} | {:error, changeset() | term()} | {:error, :limit_reached, map()}
  def create_asset(%Project{} = project, %User{} = user, attrs) do
    project
    |> create_asset_record(user.id, attrs, :generic)
    |> track_asset_created(user, attrs)
  end

  @doc """
  Creates an asset record without a user (for system uploads).
  """
  @spec create_asset(project(), attrs()) ::
          {:ok, asset()} | {:error, changeset() | term()} | {:error, :limit_reached, map()}
  def create_asset(%Project{} = project, attrs) do
    project
    |> create_asset_record(nil, attrs, :generic)
    |> track_asset_created(nil, attrs)
  end

  @doc """
  Updates an asset's metadata.
  """
  @spec update_asset(asset(), attrs()) :: {:ok, asset()} | {:error, changeset() | term()}
  def update_asset(%Asset{} = asset, attrs) do
    Repo.transaction(fn -> update_asset_in_transaction(asset, attrs) end)
  end

  @doc "Moves an asset and its intrinsic original/web/variant family to recoverable trash."
  @spec delete_asset(asset()) :: {:ok, asset()} | {:error, changeset() | term()}
  def delete_asset(%Asset{id: asset_id, project_id: project_id}) do
    move_asset_to_trash(project_id, asset_id, nil)
  end

  @doc "Moves one asset family to recoverable trash under the workspace storage lock."
  @spec move_asset_to_trash(pos_integer(), pos_integer(), pos_integer() | nil) ::
          {:ok, asset()} | {:error, changeset() | term()}
  def move_asset_to_trash(project_id, asset_id, actor_id)
      when is_integer(project_id) and project_id > 0 and is_integer(asset_id) and asset_id > 0 and
             (is_nil(actor_id) or (is_integer(actor_id) and actor_id > 0)) do
    reason = if is_integer(actor_id), do: "user", else: "system"

    with_result =
      with {:ok, workspace_id} <- project_workspace_id(project_id) do
        Billing.transact_with_workspace_lock(workspace_id, fn workspace ->
          AssetTrash.move_locked(
            project_id,
            workspace.id,
            [asset_id],
            actor_id,
            reason,
            asset_reference_check(project_id),
            expand_family: true
          )
        end)
      end

    with_result
    |> report_asset_trash_result(:move)
    |> Collaboration.broadcast_dashboard_result(project_id, :all)
  end

  def move_asset_to_trash(_project_id, _asset_id, _actor_id), do: {:error, :invalid_asset_trash_request}

  @doc """
  Moves an exact set of active assets to trash inside an existing restore transaction.

  This is the ENG-76 integration seam. It requires the canonical workspace lock,
  never expands the supplied set, and rejects active references or incomplete
  original/web/variant families.
  """
  @spec move_assets_to_trash_locked(pos_integer(), pos_integer() | nil, [pos_integer()], keyword()) ::
          {:ok, asset()} | {:error, term()}
  def move_assets_to_trash_locked(project_id, actor_id, asset_ids, opts \\ [])
      when is_integer(project_id) and project_id > 0 and is_list(asset_ids) and is_list(opts) do
    with :ok <- validate_asset_trash_actor(actor_id),
         {:ok, workspace_id} <- project_workspace_id(project_id) do
      AssetTrash.move_locked(
        project_id,
        workspace_id,
        asset_ids,
        actor_id,
        "snapshot_restore",
        asset_reference_check(project_id),
        expand_family: false
      )
    end
  end

  @doc "Restores a generation-fenced asset family from recoverable trash."
  @spec restore_trashed_asset(pos_integer(), pos_integer(), non_neg_integer(), pos_integer() | nil) ::
          {:ok, asset()} | {:error, term()}
  def restore_trashed_asset(project_id, asset_id, expected_generation, actor_id) do
    with_result =
      with :ok <- validate_asset_trash_identity(project_id, asset_id, expected_generation),
           :ok <- validate_asset_trash_actor(actor_id),
           {:ok, workspace_id} <- project_workspace_id(project_id) do
        Billing.transact_with_workspace_lock(workspace_id, fn workspace ->
          AssetTrash.restore_locked(
            project_id,
            workspace.id,
            asset_id,
            expected_generation
          )
        end)
      end

    with_result
    |> report_asset_trash_result(:restore)
    |> Collaboration.broadcast_dashboard_result(project_id, :all)
  end

  @doc "Permanently removes a generation-fenced trashed asset family and hands off live-key cleanup."
  @spec purge_trashed_asset(pos_integer(), pos_integer(), non_neg_integer(), pos_integer() | nil) ::
          {:ok, asset()} | {:error, term()}
  def purge_trashed_asset(project_id, asset_id, expected_generation, actor_id) do
    purge_trashed_asset(project_id, asset_id, expected_generation, actor_id, [])
  end

  @doc false
  @spec purge_trashed_asset(pos_integer(), pos_integer(), non_neg_integer(), pos_integer() | nil, keyword()) ::
          {:ok, asset()} | {:error, term()}
  def purge_trashed_asset(project_id, asset_id, expected_generation, actor_id, opts) when is_list(opts) do
    with_result =
      with :ok <- validate_asset_trash_identity(project_id, asset_id, expected_generation),
           :ok <- validate_asset_trash_actor(actor_id),
           {:ok, workspace_id} <- project_workspace_id(project_id) do
        Billing.transact_with_workspace_lock(workspace_id, fn workspace ->
          AssetTrash.purge_locked(
            project_id,
            workspace.id,
            asset_id,
            expected_generation,
            asset_reference_check(project_id),
            &asset_cleanup_targets/1,
            opts
          )
        end)
      end

    with_result
    |> report_asset_trash_result(:purge)
    |> Collaboration.broadcast_dashboard_result(project_id, :all)
  end

  @doc "Permanently removes one exact batch of trashed asset families under a single workspace lock."
  @spec purge_trashed_assets(
          pos_integer(),
          [{pos_integer(), non_neg_integer()}],
          pos_integer() | nil
        ) :: {:ok, [asset()]} | {:error, term()}
  def purge_trashed_assets(project_id, candidates, actor_id)
      when is_integer(project_id) and project_id > 0 and is_list(candidates) and candidates != [] and
             (is_nil(actor_id) or (is_integer(actor_id) and actor_id > 0)) do
    with_result =
      with {:ok, workspace_id} <- project_workspace_id(project_id) do
        Billing.transact_with_workspace_lock(workspace_id, fn workspace ->
          AssetTrash.purge_many_locked(
            project_id,
            workspace.id,
            candidates,
            asset_reference_check(project_id),
            &asset_cleanup_targets/1
          )
        end)
      end

    with_result
    |> report_asset_trash_result(:purge)
    |> Collaboration.broadcast_dashboard_result(project_id, :all)
  end

  def purge_trashed_assets(_project_id, _candidates, _actor_id), do: {:error, :invalid_asset_trash_request}

  @doc false
  @spec prepare_parent_hard_delete_locked(pos_integer(), :all | [pos_integer()]) ::
          :ok | {:error, term()}
  # This hands off only keys derivable from Asset rows locked in this
  # transaction. ENG-85 owns durable retirement of rowless project blobs.
  def prepare_parent_hard_delete_locked(workspace_id, project_scope)
      when is_integer(workspace_id) and workspace_id > 0 and (project_scope == :all or is_list(project_scope)) do
    with true <- Billing.workspace_lock_held?(workspace_id) || {:error, :storage_accounting_lock_required},
         {:ok, project_ids} <- lock_parent_cleanup_projects(workspace_id, project_scope) do
      assets = lock_parent_cleanup_assets(project_ids)
      persist_parent_asset_cleanup(assets)
    end
  end

  def prepare_parent_hard_delete_locked(_workspace_id, _project_scope), do: {:error, :invalid_parent_asset_cleanup_scope}

  @doc false
  @spec lock_active_asset_references_for_restore(pos_integer(), keyword()) ::
          :ok | {:error, term()}
  def lock_active_asset_references_for_restore(project_id, owner_ids)
      when is_integer(project_id) and project_id > 0 and is_list(owner_ids) do
    with {:ok, normalized_owner_ids} <- normalize_asset_restore_owner_ids(owner_ids),
         specs = asset_restore_reference_specs(normalized_owner_ids),
         {:ok, _asset_ids} <- ProjectReferenceIntegrity.lock_active_references(project_id, specs) do
      :ok
    end
  end

  def lock_active_asset_references_for_restore(_project_id, _owner_ids), do: {:error, :invalid_asset_restore_owners}

  defp normalize_asset_restore_owner_ids(owner_ids) do
    allowed_keys = [:sheet_ids, :block_ids, :scene_ids, :flow_node_ids]

    with :ok <- validate_asset_restore_owner_keys(owner_ids, allowed_keys),
         normalized = normalize_asset_restore_owner_values(owner_ids, allowed_keys),
         true <- valid_asset_restore_owner_values?(normalized) do
      {:ok, normalized}
    else
      _invalid -> {:error, :invalid_asset_restore_owners}
    end
  end

  defp validate_asset_restore_owner_keys(owner_ids, allowed_keys) do
    if Keyword.keyword?(owner_ids) and Enum.all?(Keyword.keys(owner_ids), &(&1 in allowed_keys)),
      do: :ok,
      else: :error
  end

  defp normalize_asset_restore_owner_values(owner_ids, allowed_keys) do
    Map.new(allowed_keys, fn key ->
      ids = owner_ids |> Keyword.get(key, []) |> List.wrap()
      {key, Enum.uniq(ids)}
    end)
  end

  defp valid_asset_restore_owner_values?(owner_ids) do
    Enum.all?(owner_ids, fn {_key, ids} ->
      Enum.all?(ids, &(is_integer(&1) and &1 > 0))
    end)
  end

  defp asset_restore_reference_specs(owner_ids) do
    sheet_restore_reference_specs(owner_ids.sheet_ids) ++
      block_restore_reference_specs(owner_ids.block_ids) ++
      scene_restore_reference_specs(owner_ids.scene_ids) ++
      flow_node_restore_reference_specs(owner_ids.flow_node_ids)
  end

  defp sheet_restore_reference_specs([]), do: []

  defp sheet_restore_reference_specs(sheet_ids) do
    banners =
      Repo.all(
        from(sheet in Sheet,
          where: sheet.id in ^sheet_ids,
          select: {sheet.id, sheet.banner_asset_id}
        )
      )

    avatars =
      Repo.all(
        from(avatar in SheetAvatar,
          where: avatar.sheet_id in ^sheet_ids,
          select: {avatar.id, avatar.asset_id}
        )
      )

    galleries =
      Repo.all(
        from(image in BlockGalleryImage,
          join: block in Block,
          on: block.id == image.block_id,
          where: block.sheet_id in ^sheet_ids and is_nil(block.deleted_at),
          select: {image.id, image.asset_id}
        )
      )

    Enum.map(banners, fn {sheet_id, asset_id} ->
      {:asset, {:sheet, sheet_id, :banner_asset_id}, asset_id}
    end) ++
      Enum.map(avatars, fn {avatar_id, asset_id} ->
        {:asset, {:sheet_avatar, avatar_id, :asset_id}, asset_id}
      end) ++
      Enum.map(galleries, fn {image_id, asset_id} ->
        {:asset, {:block_gallery_image, image_id, :asset_id}, asset_id}
      end)
  end

  defp block_restore_reference_specs([]), do: []

  defp block_restore_reference_specs(block_ids) do
    from(image in BlockGalleryImage,
      where: image.block_id in ^block_ids,
      select: {image.id, image.asset_id}
    )
    |> Repo.all()
    |> Enum.map(fn {image_id, asset_id} ->
      {:asset, {:block_gallery_image, image_id, :asset_id}, asset_id}
    end)
  end

  defp scene_restore_reference_specs([]), do: []

  defp scene_restore_reference_specs(scene_ids) do
    backgrounds =
      Repo.all(
        from(scene in Scene,
          where: scene.id in ^scene_ids,
          select: {scene.id, scene.background_asset_id}
        )
      )

    pins =
      Repo.all(
        from(pin in ScenePin,
          where: pin.scene_id in ^scene_ids,
          select: {pin.id, pin.icon_asset_id}
        )
      )

    zones =
      Repo.all(
        from(zone in SceneZone,
          where: zone.scene_id in ^scene_ids,
          select: {zone.id, zone.label_icon_asset_id}
        )
      )

    Enum.map(backgrounds, fn {scene_id, asset_id} ->
      {:asset, {:scene, scene_id, :background_asset_id}, asset_id}
    end) ++
      Enum.map(pins, fn {pin_id, asset_id} ->
        {:asset, {:scene_pin, pin_id, :icon_asset_id}, asset_id}
      end) ++
      Enum.map(zones, fn {zone_id, asset_id} ->
        {:asset, {:scene_zone, zone_id, :label_icon_asset_id}, asset_id}
      end)
  end

  defp flow_node_restore_reference_specs([]), do: []

  defp flow_node_restore_reference_specs(flow_node_ids) do
    audio =
      Repo.all(
        from(node in FlowNode,
          where: node.id in ^flow_node_ids,
          select: {node.id, fragment("?->>'audio_asset_id'", node.data)}
        )
      )

    tracks =
      Repo.all(
        from(track in SequenceTrack,
          where: track.flow_node_id in ^flow_node_ids,
          select: {track.id, track.asset_id}
        )
      )

    layers =
      Repo.all(
        from(layer in SequenceVisualLayer,
          where: layer.flow_node_id in ^flow_node_ids,
          select: {layer.id, layer.asset_id}
        )
      )

    Enum.map(audio, fn {node_id, asset_id} ->
      {:asset, {:flow_node, node_id, :audio_asset_id}, asset_id}
    end) ++
      Enum.map(tracks, fn {track_id, asset_id} ->
        {:asset, {:sequence_track, track_id, :asset_id}, asset_id}
      end) ++
      Enum.map(layers, fn {layer_id, asset_id} ->
        {:asset, {:sequence_visual_layer, layer_id, :asset_id}, asset_id}
      end)
  end

  defp validate_asset_trash_identity(project_id, asset_id, generation) do
    if positive_id?(project_id) and positive_id?(asset_id) and non_negative_integer?(generation),
      do: :ok,
      else: {:error, :invalid_asset_trash_request}
  end

  defp positive_id?(value), do: is_integer(value) and value > 0
  defp non_negative_integer?(value), do: is_integer(value) and value >= 0

  defp validate_asset_trash_actor(nil), do: :ok
  defp validate_asset_trash_actor(actor_id) when is_integer(actor_id) and actor_id > 0, do: :ok
  defp validate_asset_trash_actor(_actor_id), do: {:error, :invalid_asset_trash_request}

  defp report_asset_trash_result(result, action) do
    outcome =
      case result do
        {:ok, _result} -> :ok
        _result -> :error
      end

    :telemetry.execute(
      [:storyarn, :assets, :trash, :stop],
      %{count: 1},
      %{action: action, outcome: outcome}
    )

    result
  end

  defp asset_reference_check(project_id) do
    fn asset_ids, scope -> ensure_asset_references_clear(project_id, asset_ids, scope) end
  end

  defp ensure_asset_references_clear(project_id, asset_ids, scope) do
    if asset_references_exist?(project_id, asset_ids, scope),
      do: {:error, :asset_still_referenced},
      else: :ok
  end

  defp asset_references_exist?(project_id, asset_ids, scope) do
    flow_node_asset_reference?(project_id, asset_ids, scope) or
      sequence_layer_asset_reference?(project_id, asset_ids, scope) or
      sequence_track_asset_reference?(project_id, asset_ids, scope) or
      sheet_avatar_asset_reference?(project_id, asset_ids, scope) or
      sheet_banner_asset_reference?(project_id, asset_ids, scope) or
      secondary_asset_references_exist?(project_id, asset_ids, scope)
  end

  defp secondary_asset_references_exist?(project_id, asset_ids, scope) do
    scene_background_asset_reference?(project_id, asset_ids, scope) or
      scene_pin_asset_reference?(project_id, asset_ids, scope) or
      scene_zone_asset_reference?(project_id, asset_ids, scope) or
      localized_voiceover_asset_reference?(project_id, asset_ids, scope) or
      gallery_asset_reference?(project_id, asset_ids, scope) or
      entity_trash_asset_reference?(project_id, asset_ids, scope)
  end

  defp flow_node_asset_reference?(_project_id, asset_ids, scope) do
    asset_ids = Enum.map(asset_ids, &Integer.to_string/1)

    query =
      from(node in FlowNode,
        join: flow in Flow,
        on: flow.id == node.flow_id,
        where: fragment("?->>'audio_asset_id' = ANY(?)", node.data, ^asset_ids)
      )

    query |> maybe_active_flow_reference(scope, :flow_node) |> Repo.exists?()
  end

  defp sequence_layer_asset_reference?(_project_id, asset_ids, scope) do
    query =
      from(layer in SequenceVisualLayer,
        join: node in FlowNode,
        on: node.id == layer.flow_node_id,
        join: flow in Flow,
        on: flow.id == node.flow_id,
        where: layer.asset_id in ^asset_ids
      )

    query |> maybe_active_flow_reference(scope, :sequence) |> Repo.exists?()
  end

  defp sequence_track_asset_reference?(_project_id, asset_ids, scope) do
    query =
      from(track in SequenceTrack,
        join: node in FlowNode,
        on: node.id == track.flow_node_id,
        join: flow in Flow,
        on: flow.id == node.flow_id,
        where: track.asset_id in ^asset_ids
      )

    query |> maybe_active_flow_reference(scope, :sequence) |> Repo.exists?()
  end

  defp maybe_active_flow_reference(query, :active, :flow_node) do
    where(query, [node, flow], is_nil(node.deleted_at) and is_nil(flow.deleted_at))
  end

  defp maybe_active_flow_reference(query, :active, :sequence) do
    where(query, [_subject, node, flow], is_nil(node.deleted_at) and is_nil(flow.deleted_at))
  end

  defp maybe_active_flow_reference(query, _scope, _kind), do: query

  defp sheet_avatar_asset_reference?(_project_id, asset_ids, scope) do
    query =
      from(avatar in SheetAvatar,
        join: sheet in Sheet,
        on: sheet.id == avatar.sheet_id,
        where: avatar.asset_id in ^asset_ids
      )

    query |> maybe_active_parent_reference(scope, :sheet) |> Repo.exists?()
  end

  defp sheet_banner_asset_reference?(_project_id, asset_ids, scope) do
    query = from(sheet in Sheet, where: sheet.banner_asset_id in ^asset_ids)
    query |> maybe_active_direct_reference(scope) |> Repo.exists?()
  end

  defp scene_background_asset_reference?(_project_id, asset_ids, scope) do
    query = from(scene in Scene, where: scene.background_asset_id in ^asset_ids)
    query |> maybe_active_direct_reference(scope) |> Repo.exists?()
  end

  defp scene_pin_asset_reference?(_project_id, asset_ids, scope) do
    query =
      from(pin in ScenePin,
        join: scene in Scene,
        on: scene.id == pin.scene_id,
        where: pin.icon_asset_id in ^asset_ids
      )

    query |> maybe_active_parent_reference(scope, :scene) |> Repo.exists?()
  end

  defp scene_zone_asset_reference?(_project_id, asset_ids, scope) do
    query =
      from(zone in SceneZone,
        join: scene in Scene,
        on: scene.id == zone.scene_id,
        where: zone.label_icon_asset_id in ^asset_ids
      )

    query |> maybe_active_parent_reference(scope, :scene) |> Repo.exists?()
  end

  defp localized_voiceover_asset_reference?(_project_id, asset_ids, scope) do
    query =
      from(text in LocalizedText,
        where: text.vo_asset_id in ^asset_ids
      )

    query =
      if scope == :active,
        do: where(query, [text], is_nil(text.archived_at)),
        else: query

    Repo.exists?(query)
  end

  defp gallery_asset_reference?(_project_id, asset_ids, scope) do
    query =
      from(image in BlockGalleryImage,
        join: block in Block,
        on: block.id == image.block_id,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where: image.asset_id in ^asset_ids
      )

    query =
      if scope == :active,
        do: where(query, [_image, block, sheet], is_nil(block.deleted_at) and is_nil(sheet.deleted_at)),
        else: query

    Repo.exists?(query)
  end

  defp entity_trash_asset_reference?(_project_id, _asset_ids, :active), do: false

  defp entity_trash_asset_reference?(_project_id, asset_ids, :any) do
    Repo.exists?(
      from(reference in EntityTrashRef,
        where: reference.target_asset_id in ^asset_ids
      )
    )
  end

  defp maybe_active_parent_reference(query, :active, :sheet),
    do: where(query, [_subject, sheet], is_nil(sheet.deleted_at))

  defp maybe_active_parent_reference(query, :active, :scene),
    do: where(query, [_subject, scene], is_nil(scene.deleted_at))

  defp maybe_active_parent_reference(query, _scope, _parent), do: query

  defp maybe_active_direct_reference(query, :active), do: where(query, [subject], is_nil(subject.deleted_at))

  defp maybe_active_direct_reference(query, _scope), do: query

  defp asset_cleanup_targets(%Asset{} = asset) do
    if project_asset_key?(asset.key, asset.project_id) do
      thumbnail_key =
        if is_binary((asset.metadata || %{})["thumbnail_key"]),
          do: thumbnail_key(asset.key)

      [asset.key, thumbnail_key]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
    else
      []
    end
  end

  defp parent_asset_cleanup_targets(%Asset{} = asset) do
    case asset_cleanup_targets(asset) do
      [] -> []
      logical_targets -> logical_targets ++ parent_blob_cleanup_targets(asset)
    end
  end

  defp parent_blob_cleanup_targets(%Asset{blob_hash: blob_hash} = asset) when is_binary(blob_hash) do
    [BlobStore.blob_key(asset.project_id, blob_hash, BlobStore.ext_from_content_type(asset.content_type))]
  end

  defp parent_blob_cleanup_targets(%Asset{blob_hash: nil}), do: []

  defp lock_parent_cleanup_projects(workspace_id, :all) do
    {:ok,
     Repo.all(
       from(project in Project,
         where: project.workspace_id == ^workspace_id,
         order_by: [asc: project.id],
         lock: "FOR UPDATE",
         select: project.id
       )
     )}
  end

  defp lock_parent_cleanup_projects(workspace_id, project_ids) when is_list(project_ids) do
    valid_ids? = Enum.all?(project_ids, &(is_integer(&1) and &1 > 0))
    expected_ids = project_ids |> Enum.uniq() |> Enum.sort()

    locked_ids =
      if valid_ids? and expected_ids != [] do
        Repo.all(
          from(project in Project,
            where: project.workspace_id == ^workspace_id and project.id in ^expected_ids,
            order_by: [asc: project.id],
            lock: "FOR UPDATE",
            select: project.id
          )
        )
      else
        []
      end

    if locked_ids == expected_ids and expected_ids != [],
      do: {:ok, locked_ids},
      else: {:error, :invalid_parent_asset_cleanup_scope}
  end

  defp lock_parent_cleanup_assets([]), do: []

  defp lock_parent_cleanup_assets(project_ids) do
    Repo.all(
      from(asset in Asset,
        where: asset.project_id in ^project_ids,
        order_by: [asc: asset.project_id, asc: asset.id],
        lock: "FOR UPDATE"
      )
    )
  end

  defp persist_parent_asset_cleanup(assets) do
    assets
    |> Enum.chunk_every(@parent_cleanup_asset_batch_size)
    |> Enum.reduce_while(:ok, fn batch, :ok ->
      case AssetTrash.prepare_cleanup_locked(batch, &parent_asset_cleanup_targets/1) do
        {:ok, _request} -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp project_asset_key?(storage_key, project_id) when is_binary(storage_key) and is_integer(project_id) do
    case String.split(storage_key, "/") do
      ["projects", encoded_project_id, "assets", _asset_uuid, _filename] ->
        encoded_project_id == Integer.to_string(project_id)

      _parts ->
        false
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking asset changes.
  """
  @spec change_asset(asset(), attrs()) :: changeset()
  def change_asset(%Asset{} = asset, attrs \\ %{}) do
    Asset.update_changeset(asset, attrs)
  end

  @doc """
  Counts assets by content type prefix for a project.

  Returns a map like:
      %{"image" => 10, "audio" => 5}
  """
  @spec count_assets_by_type(integer()) :: %{String.t() => non_neg_integer()}
  def count_assets_by_type(project_id) do
    from(a in Asset,
      where: a.project_id == ^project_id and is_nil(a.deleted_at),
      group_by: fragment("split_part(?, '/', 1)", a.content_type),
      select: {fragment("split_part(?, '/', 1)", a.content_type), count(a.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Returns the total size of all assets for a project in bytes.
  """
  @spec total_storage_size(integer()) :: non_neg_integer()
  def total_storage_size(project_id) do
    Repo.one(
      from(a in Asset,
        where: a.project_id == ^project_id and is_nil(a.deleted_at),
        select: sum(a.size)
      )
    ) || 0
  end

  @doc """
  Generates a unique storage key for an asset.

  Format: projects/{project_id}/assets/{uuid}/{filename}
  """
  @spec generate_key(project(), String.t()) :: String.t()
  def generate_key(%Project{} = project, filename) do
    uuid = Ecto.UUID.generate()
    sanitized = sanitize_filename(filename)
    "projects/#{project.id}/assets/#{uuid}/#{sanitized}"
  end

  @doc """
  Generates a thumbnail key from an asset key.

  Format: projects/{project_id}/thumbnails/{uuid}/{filename}
  """
  @spec thumbnail_key(String.t()) :: String.t()
  def thumbnail_key(asset_key) do
    String.replace(asset_key, "/assets/", "/thumbnails/")
  end

  @doc """
  Returns a map of usage references for an asset within its project.

  Checks:
  - Flow nodes with `data->>'audio_asset_id'` matching the asset
  - Sequence visual layers and audio tracks
  - Sheets with avatars or banners referencing the asset
  - Scenes with backgrounds, pin icons, or zone label icons referencing the asset
  - Localized voice-over rows that reference the asset
  - Gallery images that reference the asset

  Content in trash is deliberately included because hard-deleting the asset
  also clears or cascades those references. Usage maps expose `:trashed` (or
  the source deletion timestamps for gallery rows) so callers can distinguish
  inactive content without hiding its data-loss impact.

  Returns:
      %{
        asset_metadata_links: [map()],
        flow_nodes: [map()],
        sequence_visual_layers: [map()],
        sequence_tracks: [map()],
        sheet_avatars: [map()],
        sheet_banners: [map()],
        scene_backgrounds: [map()],
        scene_pin_icons: [map()],
        scene_zone_icons: [map()],
        localized_voiceovers: [map()],
        gallery_images: [map()]
      }
  """
  @spec get_asset_usages(integer(), integer()) :: %{
          asset_metadata_links: [map()],
          flow_nodes: [map()],
          sequence_visual_layers: [map()],
          sequence_tracks: [map()],
          sheet_avatars: [map()],
          sheet_banners: [map()],
          scene_backgrounds: [map()],
          scene_pin_icons: [map()],
          scene_zone_icons: [map()],
          localized_voiceovers: [map()],
          gallery_images: [map()]
        }
  def get_asset_usages(project_id, asset_id) do
    get_asset_usages_for_ids(project_id, [asset_id])
  end

  defp get_asset_usages_for_ids(_project_id, []), do: empty_asset_usages()

  defp get_asset_usages_for_ids(project_id, asset_ids) do
    asset_ids = Enum.uniq(asset_ids)

    %{
      asset_metadata_links: list_asset_metadata_links(project_id, asset_ids),
      flow_nodes: list_flow_nodes_using_assets(project_id, asset_ids),
      sequence_visual_layers: list_sequence_visual_layers_using_assets(project_id, asset_ids),
      sequence_tracks: list_sequence_tracks_using_assets(project_id, asset_ids),
      sheet_avatars: list_sheet_avatars_using_assets(project_id, asset_ids),
      sheet_banners: list_sheet_banners_using_assets(project_id, asset_ids),
      scene_backgrounds: list_scenes_using_assets_as_background(project_id, asset_ids),
      scene_pin_icons: list_scene_pins_using_assets_as_icon(project_id, asset_ids),
      scene_zone_icons: list_scene_zones_using_assets_as_icon(project_id, asset_ids),
      localized_voiceovers: list_localized_voiceovers_using_assets(project_id, asset_ids),
      gallery_images: list_gallery_images_using_assets(project_id, asset_ids)
    }
  end

  @doc """
  Returns usage references aggregated across an asset's active family.

  Family membership uses the same undirected metadata graph as recoverable
  trash. Lists are deduplicated so callers can use this map as a complete
  preview of the references checked before moving the family to trash.
  """
  @spec get_asset_family_usages(integer(), integer()) :: %{
          asset_metadata_links: [map()],
          flow_nodes: [map()],
          sequence_visual_layers: [map()],
          sequence_tracks: [map()],
          sheet_avatars: [map()],
          sheet_banners: [map()],
          scene_backgrounds: [map()],
          scene_pin_icons: [map()],
          scene_zone_icons: [map()],
          localized_voiceovers: [map()],
          gallery_images: [map()]
        }
  def get_asset_family_usages(project_id, asset_id) do
    usages =
      project_id
      |> AssetTrash.active_family_ids(asset_id)
      |> then(&get_asset_usages_for_ids(project_id, &1))

    Map.update!(usages, :asset_metadata_links, fn links ->
      Enum.reject(links, &(&1.id == asset_id))
    end)
  end

  defp empty_asset_usages do
    %{
      asset_metadata_links: [],
      flow_nodes: [],
      sequence_visual_layers: [],
      sequence_tracks: [],
      sheet_avatars: [],
      sheet_banners: [],
      scene_backgrounds: [],
      scene_pin_icons: [],
      scene_zone_icons: [],
      localized_voiceovers: [],
      gallery_images: []
    }
  end

  defp lock_active_project_for_asset_write(project_id) do
    case Repo.one(
           from(project in Project,
             where: project.id == ^project_id,
             lock: "FOR UPDATE"
           )
         ) do
      %Project{deleted_at: nil} = project -> {:ok, project}
      %Project{} -> {:error, :project_not_active}
      nil -> {:error, :project_not_found}
    end
  end

  defp lock_active_project_for_asset_write(project_id, workspace_id) do
    case Repo.one(
           from(project in Project,
             where: project.id == ^project_id and project.workspace_id == ^workspace_id,
             lock: "FOR UPDATE"
           )
         ) do
      %Project{deleted_at: nil} = project -> {:ok, project}
      %Project{} -> {:error, :project_not_active}
      nil -> project_workspace_mismatch_error(project_id)
    end
  end

  defp project_workspace_mismatch_error(project_id) do
    if Repo.exists?(from(project in Project, where: project.id == ^project_id)),
      do: {:error, :project_workspace_mismatch},
      else: {:error, :project_not_found}
  end

  defp project_workspace_id(project_id) do
    case Repo.one(from(project in Project, where: project.id == ^project_id, select: project.workspace_id)) do
      workspace_id when is_integer(workspace_id) -> {:ok, workspace_id}
      nil -> {:error, :project_not_found}
    end
  end

  defp lock_asset_for_write(asset_id, project_id) do
    case Repo.one(
           from(asset in Asset,
             where: asset.id == ^asset_id and asset.project_id == ^project_id,
             lock: "FOR UPDATE"
           )
         ) do
      %Asset{deleted_at: nil} = asset -> {:ok, asset}
      %Asset{} -> {:error, :asset_not_active}
      nil -> {:error, :asset_not_found}
    end
  end

  defp create_asset_record(%Project{} = project, uploaded_by_id, attrs, upload_kind) do
    project.workspace_id
    |> Billing.transact_with_workspace_lock(fn workspace ->
      create_asset_record_with_lock(workspace, project, uploaded_by_id, attrs, upload_kind)
    end)
    |> normalize_asset_record_result()
  end

  defp create_asset_record_with_lock(workspace, project, uploaded_by_id, attrs, upload_kind) do
    with {:ok, locked_project} <-
           lock_active_project_for_asset_write(project.id, workspace.id),
         changeset =
           asset_create_changeset(
             %Asset{project_id: locked_project.id, uploaded_by_id: uploaded_by_id},
             attrs,
             upload_kind
           ),
         :ok <- lock_asset_family_references(%Asset{project_id: locked_project.id}, attrs),
         :ok <- check_asset_record_capacity(locked_project, changeset),
         {:ok, asset} <- with_asset_storage_key_lock(attrs, fn -> Repo.insert(changeset) end) do
      {:ok, asset}
    else
      {:error, :limit_reached, details} -> {:error, {:limit_reached, details}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_asset_record_capacity(%Project{} = project, %{valid?: true} = changeset) do
    Billing.can_upload_asset_for_project?(project, Ecto.Changeset.get_field(changeset, :size))
  end

  defp check_asset_record_capacity(_project, _changeset), do: :ok

  defp normalize_asset_record_result({:error, {:limit_reached, details}}), do: {:error, :limit_reached, details}

  defp normalize_asset_record_result(result), do: result

  defp update_asset_in_transaction(asset, attrs) do
    with {:ok, _project} <- lock_active_project_for_asset_write(asset.project_id),
         {:ok, locked_asset} <- lock_asset_for_write(asset.id, asset.project_id),
         :ok <- lock_asset_family_references(locked_asset, attrs),
         {:ok, updated_asset} <-
           locked_asset
           |> Asset.update_changeset(attrs)
           |> Repo.update() do
      updated_asset
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_asset_family_references(asset, attrs) do
    case asset_metadata_attr(attrs) do
      :absent ->
        :ok

      {:present, metadata} ->
        with {:ok, asset_ids} <- Asset.family_reference_ids(metadata),
             {:ok, _locked_ids} <-
               ProjectReferenceIntegrity.lock_active_references(
                 asset.project_id,
                 Enum.map(asset_ids, &{:asset, {:asset_family, asset.id}, &1})
               ) do
          :ok
        else
          :error -> {:error, :asset_family_identity_invalid}
          {:error, _reason} -> {:error, :asset_family_identity_invalid}
        end
    end
  end

  defp asset_metadata_attr(attrs) when is_map(attrs) do
    cond do
      Map.has_key?(attrs, :metadata) -> {:present, Map.get(attrs, :metadata)}
      Map.has_key?(attrs, "metadata") -> {:present, Map.get(attrs, "metadata")}
      true -> :absent
    end
  end

  defp asset_metadata_attr(_attrs), do: :absent

  defp asset_create_changeset(asset, attrs, :generic), do: Asset.create_changeset(asset, attrs)

  defp asset_create_changeset(asset, attrs, :sanitized_svg), do: Asset.create_sanitized_svg_changeset(asset, attrs)

  defp list_asset_metadata_links(project_id, asset_ids) do
    asset_id_strings = Enum.map(asset_ids, &to_string/1)

    project_id
    |> list_assets_with_metadata_links(asset_id_strings)
    |> Enum.map(fn asset ->
      %{
        id: asset.id,
        filename: asset.filename,
        relations: asset_metadata_link_relations(asset.metadata || %{}, asset_id_strings)
      }
    end)
  end

  defp list_assets_with_metadata_links(project_id, asset_id_strings) do
    Repo.all(
      from(asset in Asset,
        where: asset.project_id == ^project_id,
        where:
          fragment("?->>'web_asset_id' = ANY(?)", asset.metadata, ^asset_id_strings) or
            fragment("?->>'original_asset_id' = ANY(?)", asset.metadata, ^asset_id_strings) or
            fragment(
              """
              EXISTS (
                SELECT 1
                FROM jsonb_each_text(
                  CASE
                    WHEN jsonb_typeof(?->'variant_asset_ids') = 'object'
                    THEN ?->'variant_asset_ids'
                    ELSE '{}'::jsonb
                  END
                ) AS variant_link
                WHERE variant_link.value = ANY(?)
              )
              """,
              asset.metadata,
              asset.metadata,
              ^asset_id_strings
            ),
        order_by: [asc: asset.filename, asc: asset.id]
      )
    )
  end

  defp asset_metadata_link_relations(metadata, asset_id_strings) do
    []
    |> maybe_add_metadata_relation(
      metadata_id_matches_any?(metadata["web_asset_id"], asset_id_strings),
      "web_variant"
    )
    |> maybe_add_metadata_relation(
      metadata_id_matches_any?(metadata["original_asset_id"], asset_id_strings),
      "original"
    )
    |> maybe_add_metadata_relation(profile_variant_link?(metadata, asset_id_strings), "profile_variant")
    |> Enum.reverse()
  end

  defp profile_variant_link?(%{"variant_asset_ids" => profiles}, asset_id_strings) when is_map(profiles) do
    Enum.any?(profiles, fn {_profile, asset_id} ->
      metadata_id_matches_any?(asset_id, asset_id_strings)
    end)
  end

  defp profile_variant_link?(_metadata, _asset_id_strings), do: false

  defp maybe_add_metadata_relation(relations, true, relation), do: [relation | relations]
  defp maybe_add_metadata_relation(relations, false, _relation), do: relations

  defp metadata_id_matches?(value, asset_id_string) when is_integer(value),
    do: Integer.to_string(value) == asset_id_string

  defp metadata_id_matches?(value, asset_id_string) when is_binary(value), do: value == asset_id_string

  defp metadata_id_matches?(_value, _asset_id_string), do: false

  defp metadata_id_matches_any?(value, asset_id_strings) do
    Enum.any?(asset_id_strings, &metadata_id_matches?(value, &1))
  end

  @doc """
  Returns the total number of usage references for an asset.
  """
  @spec count_asset_usages(integer(), integer()) :: non_neg_integer()
  def count_asset_usages(project_id, asset_id) do
    usages = get_asset_usages(project_id, asset_id)

    usages
    |> Map.values()
    |> Enum.map(&length/1)
    |> Enum.sum()
  end

  defp list_flow_nodes_using_assets(project_id, asset_ids) do
    asset_ids = Enum.map(asset_ids, &to_string/1)

    Repo.all(
      from(node in FlowNode,
        join: flow in Flow,
        on: node.flow_id == flow.id,
        where:
          flow.project_id == ^project_id and
            fragment("?->>'audio_asset_id' = ANY(?)", node.data, ^asset_ids),
        order_by: [asc: flow.name, asc: node.id],
        select: %{
          node_id: node.id,
          node_type: node.type,
          flow_id: flow.id,
          flow_name: flow.name,
          trashed: not is_nil(node.deleted_at) or not is_nil(flow.deleted_at)
        }
      )
    )
  end

  defp list_sequence_visual_layers_using_assets(project_id, asset_ids) do
    Repo.all(
      from(layer in SequenceVisualLayer,
        join: node in FlowNode,
        on: layer.flow_node_id == node.id,
        join: flow in Flow,
        on: node.flow_id == flow.id,
        left_join: config in SequenceConfig,
        on: config.flow_node_id == node.id,
        where: flow.project_id == ^project_id and layer.asset_id in ^asset_ids,
        order_by: [asc: flow.name, asc: config.name, asc: layer.z_index, asc: layer.id],
        select: %{
          id: layer.id,
          node_id: node.id,
          flow_id: flow.id,
          flow_name: flow.name,
          sequence_name: config.name,
          label: layer.label,
          kind: layer.kind,
          trashed: not is_nil(node.deleted_at) or not is_nil(flow.deleted_at)
        }
      )
    )
  end

  defp list_sequence_tracks_using_assets(project_id, asset_ids) do
    Repo.all(
      from(track in SequenceTrack,
        join: node in FlowNode,
        on: track.flow_node_id == node.id,
        join: flow in Flow,
        on: node.flow_id == flow.id,
        left_join: config in SequenceConfig,
        on: config.flow_node_id == node.id,
        where: flow.project_id == ^project_id and track.asset_id in ^asset_ids,
        order_by: [asc: flow.name, asc: config.name, asc: track.kind, asc: track.id],
        select: %{
          id: track.id,
          node_id: node.id,
          flow_id: flow.id,
          flow_name: flow.name,
          sequence_name: config.name,
          kind: track.kind,
          trashed: not is_nil(node.deleted_at) or not is_nil(flow.deleted_at)
        }
      )
    )
  end

  defp list_sheet_avatars_using_assets(project_id, asset_ids) do
    Repo.all(
      from(sheet in Sheet,
        join: avatar in SheetAvatar,
        on: avatar.sheet_id == sheet.id,
        where: sheet.project_id == ^project_id and avatar.asset_id in ^asset_ids,
        distinct: true,
        order_by: [asc: sheet.name, asc: sheet.id],
        select: %{
          id: sheet.id,
          name: sheet.name,
          trashed: not is_nil(sheet.deleted_at)
        }
      )
    )
  end

  defp list_sheet_banners_using_assets(project_id, asset_ids) do
    Repo.all(
      from(sheet in Sheet,
        where: sheet.project_id == ^project_id and sheet.banner_asset_id in ^asset_ids,
        order_by: [asc: sheet.name, asc: sheet.id],
        select: %{
          id: sheet.id,
          name: sheet.name,
          trashed: not is_nil(sheet.deleted_at)
        }
      )
    )
  end

  defp list_localized_voiceovers_using_assets(project_id, asset_ids) do
    Repo.all(
      from(text in LocalizedText,
        where:
          text.project_id == ^project_id and
            text.vo_asset_id in ^asset_ids,
        order_by: [asc: text.locale_code, asc: text.id],
        select: %{
          id: text.id,
          locale_code: text.locale_code,
          source_type: text.source_type,
          source_id: text.source_id,
          source_text: text.source_text,
          archived_at: text.archived_at
        }
      )
    )
  end

  defp list_gallery_images_using_assets(project_id, asset_ids) do
    Repo.all(
      from(gallery_image in BlockGalleryImage,
        join: block in Block,
        on: block.id == gallery_image.block_id,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where:
          sheet.project_id == ^project_id and
            gallery_image.asset_id in ^asset_ids,
        order_by: [asc: sheet.name, asc: block.position, asc: gallery_image.position],
        select: %{
          id: gallery_image.id,
          block_id: block.id,
          sheet_id: sheet.id,
          sheet_name: sheet.name,
          label: gallery_image.label,
          block_deleted_at: block.deleted_at,
          sheet_deleted_at: sheet.deleted_at
        }
      )
    )
  end

  defp list_scenes_using_assets_as_background(project_id, asset_ids) do
    Repo.all(
      from(scene in Scene,
        where: scene.project_id == ^project_id and scene.background_asset_id in ^asset_ids,
        order_by: [asc: scene.name, asc: scene.id],
        select: %{
          id: scene.id,
          name: scene.name,
          trashed: not is_nil(scene.deleted_at)
        }
      )
    )
  end

  defp list_scene_pins_using_assets_as_icon(project_id, asset_ids) do
    Repo.all(
      from(pin in ScenePin,
        join: scene in Scene,
        on: pin.scene_id == scene.id,
        where: scene.project_id == ^project_id and pin.icon_asset_id in ^asset_ids,
        order_by: [asc: scene.name, asc: pin.label, asc: pin.id],
        select: %{
          pin_id: pin.id,
          pin_label: pin.label,
          scene_id: scene.id,
          scene_name: scene.name,
          trashed: not is_nil(scene.deleted_at)
        }
      )
    )
  end

  defp list_scene_zones_using_assets_as_icon(project_id, asset_ids) do
    Repo.all(
      from(zone in SceneZone,
        join: scene in Scene,
        on: zone.scene_id == scene.id,
        where: scene.project_id == ^project_id and zone.label_icon_asset_id in ^asset_ids,
        order_by: [asc: scene.name, asc: zone.name, asc: zone.id],
        select: %{
          zone_id: zone.id,
          zone_name: zone.name,
          scene_id: scene.id,
          scene_name: scene.name,
          trashed: not is_nil(scene.deleted_at)
        }
      )
    )
  end

  @doc """
  Uploads a file from a temporary path and creates the corresponding asset record.

  Used by LiveView's `consume_uploaded_entries/3` to process file uploads directly
  from the parent LiveView.

  Returns `{:ok, asset}` on success, `{:error, :limit_reached, details}` when
  the atomic workspace check rejects the write, or `{:error, reason}` for other
  failures.
  """
  @spec upload_and_create_asset(
          String.t(),
          Phoenix.LiveView.UploadEntry.t(),
          project(),
          user(),
          keyword()
        ) ::
          upload_result()
  def upload_and_create_asset(path, entry, %Project{} = project, %User{} = user, opts \\ []) do
    do_upload_and_create_asset(path, entry, project, user, opts)
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp do_upload_and_create_asset(path, entry, project, user, opts) do
    content = File.read!(path)
    metadata = extract_image_metadata(path, entry.client_type)

    attrs = %{filename: entry.client_name, content_type: entry.client_type, metadata: metadata}

    attrs =
      if purpose = Keyword.get(opts, :purpose), do: Map.put(attrs, :purpose, purpose), else: attrs

    upload_binary_and_create_asset(content, attrs, project, user)
  end

  @doc """
  Inspects a future image upload and returns the action needed for its purpose.

  The caller provides client-side metadata plus a SHA-256 source hash. The
  server uses that hash only for lookup; actual uploads still recompute the
  hash from the received binary.
  """
  @spec inspect_upload(project(), map()) :: {:ok, map()} | {:error, term()}
  def inspect_upload(%Project{} = project, attrs) do
    purpose = attrs |> Map.get("purpose", Map.get(attrs, :purpose)) |> UploadPolicy.parse_purpose()

    with {:ok, profile} <- UploadPolicy.profile_for(purpose),
         {:ok, metadata} <- UploadPolicy.normalize_metadata(attrs),
         :ok <- UploadPolicy.validate(profile, metadata) do
      existing_original = get_asset_by_blob_hash(project.id, metadata.source_hash)
      requires_variant? = requires_variant?(purpose, metadata.content_type, image_metadata(metadata))

      existing_variant =
        if requires_variant? do
          get_asset_by_source_profile(project.id, metadata.source_hash, profile.profile)
        end

      {:ok,
       %{
         action: upload_decision_action(existing_original, existing_variant, requires_variant?),
         source_exists: not is_nil(existing_original),
         variant_exists: not is_nil(existing_variant),
         requires_variant: requires_variant?,
         variant_profile: profile.profile,
         target: profile.target,
         asset_id: decision_asset_id(existing_original, existing_variant, requires_variant?)
       }}
    end
  end

  @doc """
  Materializes a purpose-specific asset from an existing source image.

  This is used after `inspect_upload/2` determines that the source hash already
  exists in the project, so the browser does not need to upload the same binary
  again.
  """
  @spec materialize_upload_variant(project(), user() | nil, map()) ::
          {:ok, asset(), map()} | upload_error()
  def materialize_upload_variant(%Project{} = project, user, attrs) do
    with_workspace_upload_lock(project, fn _workspace ->
      do_materialize_upload_variant(project, user, attrs)
    end)
  end

  defp do_materialize_upload_variant(project, user, attrs) do
    purpose = attrs |> Map.get("purpose", Map.get(attrs, :purpose)) |> UploadPolicy.parse_purpose()
    source_hash = Map.get(attrs, "hash") || Map.get(attrs, :hash)

    with {:ok, profile} <- UploadPolicy.profile_for(purpose),
         true <- is_binary(source_hash),
         %Asset{} = original <- get_asset_by_blob_hash(project.id, source_hash),
         {:ok, binary_data} <- Storage.download(original.key) do
      materialize_asset_for_purpose(binary_data, original, project, user, purpose, profile)
    else
      false -> {:error, :invalid_hash}
      nil -> {:error, :source_not_found}
      error -> error
    end
  end

  @doc """
  Uploads a source binary and returns the asset that should be attached for
  the requested purpose.

  For avatar, banner, and scene background uploads this keeps the original
  source once and returns a generated/reused placement-specific variant when
  one is required.
  """
  @spec upload_binary_for_purpose(binary(), map(), project(), user() | nil) ::
          {:ok, asset(), map()} | upload_error()
  def upload_binary_for_purpose(binary_data, attrs, %Project{} = project, user \\ nil) do
    purpose = attrs |> Map.get(:purpose, Map.get(attrs, "purpose")) |> UploadPolicy.parse_purpose()

    with {:ok, profile} <- UploadPolicy.profile_for(purpose),
         :ok <- validate_binary_upload(binary_data, attrs, profile) do
      with_workspace_upload_lock(project, fn _workspace ->
        ensure_and_materialize_asset(binary_data, attrs, project, user, purpose, profile)
      end)
    end
  end

  defp ensure_and_materialize_asset(binary_data, attrs, project, user, purpose, profile) do
    with {:ok, original} <- ensure_original_asset(binary_data, attrs, project, user) do
      materialize_asset_for_purpose(binary_data, original, project, user, purpose, profile)
    end
  end

  @doc """
  Uploads binary data to storage, persists a content-addressed blob for
  snapshot restoration, and creates the asset record.

  This is the single entry point for all asset creation from raw binary data.
  LiveView file uploads should use `upload_and_create_asset/4` instead.

  ## Attrs

    * `:filename` — original filename (will be sanitized)
    * `:content_type` — MIME type
    * `:metadata` — optional extra metadata map (default `%{}`)

  Returns `{:ok, asset}`, `{:error, :limit_reached, details}`, or another
  `{:error, reason}`.
  """
  @spec upload_binary_and_create_asset(binary(), map(), project(), user() | nil) ::
          upload_result()
  def upload_binary_and_create_asset(
        binary_data,
        %{filename: filename, content_type: content_type} = attrs,
        %Project{} = project,
        user \\ nil
      ) do
    with_upload_capacity(project, byte_size(binary_data), fn ->
      do_upload_binary_and_create_asset(
        binary_data,
        %{attrs | filename: filename, content_type: content_type},
        project,
        user,
        :generic
      )
    end)
  end

  @doc """
  Sanitizes and uploads an SVG asset from a server-controlled SVG upload flow.

  Generic asset uploads must use `upload_binary_and_create_asset/4`, which
  rejects SVG. This function exists for scene icon uploads, where SVG support is
  intentional and the content must be sanitized before public storage.
  """
  @spec upload_sanitized_svg_and_create_asset(binary(), map(), project(), user() | nil) ::
          upload_result()
  def upload_sanitized_svg_and_create_asset(binary_data, attrs, %Project{} = project, user \\ nil) when is_map(attrs) do
    with content_type when content_type == @svg_content_type <-
           Map.get(attrs, :content_type, Map.get(attrs, "content_type")),
         {:ok, sanitized_svg} <- sanitize_svg_upload(binary_data) do
      attrs =
        attrs
        |> normalize_asset_attrs()
        |> Map.put(:metadata, attrs |> upload_metadata() |> Map.put("sanitized_svg", true))

      with_upload_capacity(project, byte_size(sanitized_svg), fn ->
        do_upload_binary_and_create_asset(sanitized_svg, attrs, project, user, :sanitized_svg)
      end)
    else
      _ -> {:error, :invalid_svg}
    end
  end

  defp do_upload_binary_and_create_asset(
         binary_data,
         %{filename: filename, content_type: content_type} = attrs,
         %Project{} = project,
         user,
         upload_kind
       ) do
    safe_filename = sanitize_filename(filename)
    key = generate_key(project, safe_filename)

    blob_hash = BlobStore.compute_hash(binary_data)

    asset_attrs = %{
      filename: safe_filename,
      content_type: content_type,
      size: byte_size(binary_data),
      key: key,
      url: Storage.get_url(key),
      metadata: Map.get(attrs, :metadata, %{}),
      blob_hash: blob_hash
    }

    with :ok <- validate_asset_upload_attrs(asset_attrs, upload_kind) do
      ext = BlobStore.ext_from_content_type(content_type)
      blob_key = BlobStore.blob_key(project.id, blob_hash, ext)

      upload_context = %{
        binary_data: binary_data,
        content_type: content_type,
        key: key,
        asset_attrs: asset_attrs,
        attrs: attrs,
        project: project,
        user: user,
        upload_kind: upload_kind
      }

      StorageKeyLock.with_project_blob_lock(blob_key, fn ->
        ensure_upload_blob(blob_key, blob_hash, ext, upload_context)
      end)
    end
  end

  defp ensure_upload_blob(blob_key, blob_hash, ext, context) do
    case BlobStore.ensure_blob_with_status(
           context.project.id,
           blob_hash,
           ext,
           context.binary_data,
           context.content_type
         ) do
      {:ok, blob_key, blob_created?} ->
        track_new_upload_blob(blob_key, blob_created?)

        persist_uploaded_asset(
          %{
            binary_data: context.binary_data,
            content_type: context.content_type,
            key: context.key,
            blob_key: blob_key,
            blob_created?: blob_created?
          },
          context.asset_attrs,
          context.attrs,
          context.project,
          context.user,
          context.upload_kind
        )

      {:error, {:invalid_existing_blob, invalid_blob_key, reason}} ->
        track_force_upload_storage_key(invalid_blob_key)
        {:error, reason}

      {:error, reason} ->
        # Storage errors may have an ambiguous remote outcome (for example,
        # a lost R2 response after the object was accepted). Conservatively
        # retain cleanup ownership even when creation status is unknown.
        track_upload_storage_key(blob_key)
        {:error, reason}
    end
  end

  defp persist_uploaded_asset(upload, asset_attrs, attrs, project, user, upload_kind) do
    StorageKeyLock.with_storage_key_lock(upload.key, fn ->
      track_upload_storage_key(upload.key)

      case Storage.upload(upload.key, upload.binary_data, upload.content_type) do
        {:ok, url} ->
          persist_uploaded_asset_record(upload, asset_attrs, attrs, project, user, upload_kind, url)

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  defp persist_uploaded_asset_record(upload, asset_attrs, attrs, project, user, upload_kind, url) do
    case do_create_asset(project, user, %{asset_attrs | url: url}, upload_kind) do
      {:ok, asset} ->
        retain_successful_upload(upload)
        maybe_schedule_variant(upload.binary_data, asset, project, user, attrs)
        {:ok, asset}

      error ->
        error
    end
  end

  defp with_upload_capacity(%Project{} = project, file_size, fun) when is_function(fun, 0) do
    with_workspace_upload_lock(project, fn workspace ->
      capacity_checked_upload(workspace, file_size, fun)
    end)
  end

  defp capacity_checked_upload(workspace, file_size, fun) do
    case Billing.can_upload_asset?(workspace, file_size) do
      :ok -> fun.()
      {:error, _reason, _details} = error -> error
    end
  end

  defp with_workspace_upload_lock(%Project{} = project, fun) when is_function(fun, 1) do
    case Process.get(@upload_tracker_process_key) do
      tracker when is_reference(tracker) ->
        project
        |> workspace_upload_transaction(fun)
        |> unwrap_workspace_upload_transaction()

      _tracker ->
        if Repo.in_transaction?(),
          do: {:error, :asset_upload_transaction_owner_required},
          else: with_owned_upload_tracker(project, fun)
    end
  end

  defp with_owned_upload_tracker(project, fun) do
    tracker = StorageCompensation.new()
    Process.put(@upload_tracker_process_key, tracker)
    Process.put(@post_commit_variant_jobs_process_key, [])

    try do
      case workspace_upload_transaction(project, fun) do
        {:ok, result} ->
          finalized_result = finalize_committed_upload_transaction(tracker, result)
          schedule_post_commit_variant_jobs()
          finalized_result

        {:error, {:asset_upload_failed, error}} ->
          finalize_failed_upload_transaction(tracker, error)

        {:error, reason} ->
          finalize_failed_upload_transaction(tracker, {:error, reason})
      end
    rescue
      error ->
        StorageCompensation.cleanup_after_rollback!(tracker)
        reraise error, __STACKTRACE__
    catch
      kind, reason ->
        StorageCompensation.cleanup_after_rollback!(tracker)
        :erlang.raise(kind, reason, __STACKTRACE__)
    after
      Process.delete(@upload_tracker_process_key)
      Process.delete(@post_commit_variant_jobs_process_key)
    end
  end

  defp workspace_upload_transaction(project, fun) do
    Billing.with_storage_accounting_lock(project.workspace_id, fn workspace ->
      case fun.(workspace) do
        {:error, _reason} = error -> Repo.rollback({:asset_upload_failed, error})
        {:error, _reason, _details} = error -> Repo.rollback({:asset_upload_failed, error})
        result -> result
      end
    end)
  end

  defp unwrap_workspace_upload_transaction({:ok, result}), do: result
  defp unwrap_workspace_upload_transaction({:error, {:asset_upload_failed, error}}), do: error
  defp unwrap_workspace_upload_transaction({:error, reason}), do: {:error, reason}

  defp finalize_committed_upload_transaction(tracker, result) do
    case StorageCompensation.cleanup_unretained(tracker) do
      :ok -> result
      {:error, cleanup_reason} -> {:error, {:storage_cleanup_failed, result, cleanup_reason}}
    end
  end

  defp finalize_failed_upload_transaction(tracker, error) do
    case StorageCompensation.cleanup_after_rollback(tracker) do
      :ok -> error
      {:error, cleanup_reason} -> {:error, {:storage_cleanup_failed, error, cleanup_reason}}
    end
  end

  defp track_new_upload_blob(_blob_key, false), do: :ok
  defp track_new_upload_blob(blob_key, true), do: track_upload_storage_key(blob_key)

  defp retain_successful_upload(upload) do
    retain_upload_storage_key(upload.key)
    if upload.blob_created?, do: retain_upload_storage_key(upload.blob_key)
    :ok
  end

  defp track_upload_storage_key(storage_key) do
    case Process.get(@upload_tracker_process_key) do
      tracker when is_reference(tracker) -> StorageCompensation.track(tracker, storage_key)
      _tracker -> raise "asset upload storage tracker is not initialized"
    end
  end

  defp track_force_upload_storage_key(storage_key) do
    case Process.get(@upload_tracker_process_key) do
      tracker when is_reference(tracker) -> StorageCompensation.track_force_delete(tracker, storage_key)
      _tracker -> raise "asset upload storage tracker is not initialized"
    end
  end

  defp retain_upload_storage_key(storage_key) do
    case Process.get(@upload_tracker_process_key) do
      tracker when is_reference(tracker) -> StorageCompensation.retain_after_commit(tracker, storage_key)
      _tracker -> raise "asset upload storage tracker is not initialized"
    end
  end

  defp validate_asset_upload_attrs(attrs, upload_kind) do
    changeset =
      case upload_kind do
        :sanitized_svg -> Asset.create_sanitized_svg_changeset(%Asset{}, attrs)
        :generic -> Asset.create_changeset(%Asset{}, attrs)
      end

    if changeset.valid?, do: :ok, else: {:error, changeset}
  end

  defp sanitize_svg_upload(binary_data) when is_binary(binary_data) do
    with true <- String.valid?(binary_data),
         svg = binary_data |> strip_utf8_bom() |> String.trim(),
         true <- svg_root?(svg),
         sanitized = HtmlSanitizer.sanitize_html(svg),
         true <- svg_root?(sanitized) do
      {:ok, sanitized}
    else
      _ -> {:error, :invalid_svg}
    end
  end

  defp sanitize_svg_upload(_), do: {:error, :invalid_svg}

  defp strip_utf8_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_utf8_bom(binary), do: binary

  defp svg_root?(svg) when is_binary(svg) do
    case Floki.parse_fragment(svg) do
      {:ok, nodes} -> nodes |> Floki.find("svg") |> Enum.any?()
      _ -> false
    end
  end

  defp upload_metadata(attrs) do
    Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{})) || %{}
  end

  defp validate_binary_upload(binary_data, attrs, profile) do
    content_type = Map.get(attrs, :content_type) || Map.get(attrs, "content_type")

    UploadPolicy.validate(profile, %{
      content_type: content_type,
      size: byte_size(binary_data)
    })
  end

  defp ensure_original_asset(binary_data, attrs, project, user) do
    source_hash = BlobStore.compute_hash(binary_data)

    case get_asset_by_blob_hash(project.id, source_hash) do
      %Asset{} = asset ->
        {:ok, ensure_original_metadata(asset, binary_data, source_hash)}

      nil ->
        upload_original_asset(binary_data, attrs, project, user, source_hash)
    end
  end

  defp upload_original_asset(binary_data, attrs, project, user, source_hash) do
    metadata =
      binary_data
      |> image_metadata_from_binary()
      |> Map.merge(%{
        "source_blob_hash" => source_hash,
        "variant_profile" => "original"
      })
      |> Map.merge(Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{})))

    original_attrs =
      attrs
      |> normalize_asset_attrs()
      |> Map.merge(%{metadata: metadata, skip_variants: true})

    upload_binary_and_create_asset(binary_data, original_attrs, project, user)
  end

  defp normalize_asset_attrs(attrs) do
    %{
      filename: Map.get(attrs, :filename) || Map.get(attrs, "filename"),
      content_type: Map.get(attrs, :content_type) || Map.get(attrs, "content_type")
    }
  end

  defp ensure_original_metadata(asset, binary_data, source_hash) do
    metadata = asset.metadata || %{}

    if metadata["source_blob_hash"] && metadata["variant_profile"] do
      asset
    else
      updated_metadata =
        binary_data
        |> image_metadata_from_binary()
        |> Map.merge(metadata)
        |> Map.merge(%{
          "source_blob_hash" => source_hash,
          "variant_profile" => "original"
        })

      case update_asset(asset, %{metadata: updated_metadata}) do
        {:ok, updated} -> updated
        {:error, _} -> asset
      end
    end
  end

  defp materialize_asset_for_purpose(binary_data, original, project, user, purpose, profile) do
    source_hash = original.blob_hash || BlobStore.compute_hash(binary_data)
    metadata = original.metadata || %{}

    if requires_variant?(purpose, original.content_type, metadata) do
      case get_asset_by_source_profile(project.id, source_hash, profile.profile) do
        %Asset{} = variant ->
          {:ok, variant, %{reused: true, action: :attach_existing_variant}}

        nil ->
          create_variant_asset(binary_data, original, project, user, source_hash, purpose, profile)
      end
    else
      {:ok, original, %{reused: true, action: :attach_existing_original}}
    end
  end

  defp create_variant_asset(binary_data, original, project, user, source_hash, purpose, profile) do
    case generate_variant_binary(binary_data, purpose, profile) do
      {:ok, webp_data} ->
        upload_variant_asset(webp_data, original, project, user, source_hash, profile)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_variant_binary(binary_data, purpose, %{target: %{width: width, height: height}})
       when purpose in [:avatar, :banner] do
    ImageProcessor.resize_to_webp(binary_data, width, height)
  end

  defp generate_variant_binary(binary_data, :scene_background, _profile) do
    ImageProcessor.to_webp(binary_data)
  end

  defp upload_variant_asset(webp_data, original, project, user, source_hash, profile) do
    dimensions = image_metadata_from_binary(webp_data)

    variant_attrs = %{
      filename: Path.rootname(original.filename) <> ".webp",
      content_type: "image/webp",
      metadata:
        Map.merge(dimensions, %{
          "is_variant" => true,
          "original_asset_id" => original.id,
          "source_blob_hash" => source_hash,
          "variant_profile" => profile.profile
        }),
      skip_variants: true
    }

    with_workspace_upload_lock(project, fn _workspace ->
      with {:ok, variant} <- upload_binary_and_create_asset(webp_data, variant_attrs, project, user),
           {:ok, _updated_original} <- link_variant_to_original(original, variant, profile.profile) do
        {:ok, variant, %{reused: false, action: :created_variant}}
      end
    end)
  end

  defp image_metadata(%{width: width, height: height}) do
    %{}
    |> maybe_put_dimension("width", width)
    |> maybe_put_dimension("height", height)
  end

  defp image_metadata_from_binary(binary_data) do
    if ImageProcessor.available?() do
      case ImageProcessor.get_dimensions_from_binary(binary_data) do
        {:ok, %{width: width, height: height}} -> %{"width" => width, "height" => height}
        {:error, _} -> %{}
      end
    else
      %{}
    end
  end

  defp maybe_put_dimension(metadata, _key, nil), do: metadata
  defp maybe_put_dimension(metadata, key, value), do: Map.put(metadata, key, value)

  defp requires_variant?(purpose, content_type, metadata) do
    case ImageProcessor.needs_optimization?(content_type, metadata || %{}, purpose) do
      :skip -> false
      {:generate, _} -> true
    end
  end

  defp upload_decision_action(_original, %Asset{}, true), do: :attach_existing_variant
  defp upload_decision_action(%Asset{}, nil, true), do: :create_variant_from_existing_original
  defp upload_decision_action(%Asset{}, _variant, false), do: :attach_existing_original
  defp upload_decision_action(nil, _variant, true), do: :upload_original_and_create_variant
  defp upload_decision_action(nil, _variant, false), do: :upload_original_only

  defp decision_asset_id(_original, %Asset{id: id}, true), do: id
  defp decision_asset_id(%Asset{id: id}, _variant, false), do: id
  defp decision_asset_id(_original, _variant, _requires_variant?), do: nil

  defp get_asset_by_blob_hash(project_id, blob_hash) when is_binary(blob_hash) do
    Asset
    |> where(project_id: ^project_id, blob_hash: ^blob_hash)
    |> where([asset], is_nil(asset.deleted_at))
    |> where([a], fragment("coalesce(?->>'is_variant', 'false') != 'true'", a.metadata))
    |> order_by([a], asc: a.inserted_at, asc: a.id)
    |> limit(1)
    |> Repo.one()
  end

  defp get_asset_by_blob_hash(_project_id, _blob_hash), do: nil

  defp get_asset_by_source_profile(project_id, source_hash, profile) do
    Asset
    |> where([a], a.project_id == ^project_id and is_nil(a.deleted_at))
    |> where([a], fragment("?->>'source_blob_hash' = ?", a.metadata, ^source_hash))
    |> where([a], fragment("?->>'variant_profile' = ?", a.metadata, ^profile))
    |> order_by([a], asc: a.inserted_at, asc: a.id)
    |> limit(1)
    |> Repo.one()
  end

  defp maybe_schedule_variant(binary_data, asset, project, user, attrs) do
    purpose = Map.get(attrs, :purpose)
    skip = Map.get(attrs, :skip_variants, false)

    if purpose && !skip do
      queue_variant_generation(binary_data, asset, project, user, purpose)
    end
  end

  defp queue_variant_generation(binary_data, asset, project, user, purpose) do
    case Process.get(@post_commit_variant_jobs_process_key) do
      jobs when is_list(jobs) ->
        Process.put(
          @post_commit_variant_jobs_process_key,
          [{binary_data, asset, project, user, purpose} | jobs]
        )

        :ok

      _jobs ->
        schedule_variant_generation(binary_data, asset, project, user, purpose)
    end
  end

  defp schedule_post_commit_variant_jobs do
    jobs = Process.get(@post_commit_variant_jobs_process_key, [])
    Process.put(@post_commit_variant_jobs_process_key, [])

    jobs
    |> Enum.reverse()
    |> Enum.each(fn {binary_data, asset, project, user, purpose} ->
      schedule_variant_generation(binary_data, asset, project, user, purpose)
    end)
  end

  defp schedule_variant_generation(binary_data, asset, project, user, purpose) do
    Task.Supervisor.start_child(Storyarn.TaskSupervisor, fn ->
      maybe_generate_variant(binary_data, asset, project, user, purpose)
    end)
  end

  defp maybe_generate_variant(binary_data, asset, project, user, purpose) do
    if not String.starts_with?(asset.content_type, "image/") or
         not ImageProcessor.available?() do
      {:ok, asset}
    else
      case ImageProcessor.needs_optimization?(asset.content_type, asset.metadata || %{}, purpose) do
        :skip ->
          {:ok, asset}

        {:generate, %{crop: true, width: w, height: h}} ->
          do_generate_variant(
            binary_data,
            asset,
            project,
            user,
            &ImageProcessor.resize_to_webp(&1, w, h)
          )

        {:generate, %{crop: false}} ->
          do_generate_variant(binary_data, asset, project, user, &ImageProcessor.to_webp/1)
      end
    end
  end

  defp do_generate_variant(binary_data, original_asset, project, user, process_fn) do
    case process_fn.(binary_data) do
      {:ok, webp_data} ->
        upload_and_link_variant(webp_data, original_asset, project, user)

      {:error, reason} ->
        Logger.warning("[ImageOptimization] Failed to generate WebP for asset #{original_asset.id}: #{inspect(reason)}")

        {:ok, original_asset}
    end
  end

  defp upload_and_link_variant(webp_data, original_asset, project, user) do
    variant_attrs = %{
      filename: Path.rootname(original_asset.filename) <> ".webp",
      content_type: "image/webp",
      metadata: %{"is_variant" => true, "original_asset_id" => original_asset.id},
      skip_variants: true
    }

    with_workspace_upload_lock(project, fn _workspace ->
      with {:ok, variant} <- upload_binary_and_create_asset(webp_data, variant_attrs, project, user) do
        link_variant_to_original(original_asset, variant)
      end
    end)
  end

  defp link_variant_to_original(original_asset, variant) do
    updated_metadata =
      Map.merge(original_asset.metadata || %{}, %{
        "web_url" => variant.url,
        "web_asset_id" => variant.id
      })

    case update_asset(original_asset, %{metadata: updated_metadata}) do
      {:ok, updated_original} ->
        {:ok, updated_original}

      {:error, reason} ->
        Logger.warning("[ImageOptimization] Failed to link variant to asset #{original_asset.id}: #{inspect(reason)}")
        {:error, {:variant_link_failed, reason}}
    end
  end

  defp link_variant_to_original(original_asset, variant, profile) do
    metadata = original_asset.metadata || %{}
    profiles = Map.get(metadata, "variant_asset_ids", %{})

    updated_metadata =
      Map.put(metadata, "variant_asset_ids", Map.put(profiles, profile, variant.id))

    case update_asset(original_asset, %{metadata: updated_metadata}) do
      {:ok, updated_original} ->
        {:ok, updated_original}

      {:error, reason} ->
        Logger.warning("[ImageOptimization] Failed to link variant to asset #{original_asset.id}: #{inspect(reason)}")
        {:error, {:variant_link_failed, reason}}
    end
  end

  defp do_create_asset(project, user, attrs, :generic), do: do_create_asset(project, user, attrs)

  defp do_create_asset(%Project{} = project, user, attrs, :sanitized_svg) do
    project
    |> create_asset_record(uploaded_by_id(user), attrs, :sanitized_svg)
    |> track_asset_created(user, attrs)
  end

  defp do_create_asset(project, nil, attrs), do: create_asset(project, attrs)
  defp do_create_asset(project, user, attrs), do: create_asset(project, user, attrs)

  defp uploaded_by_id(%User{id: id}), do: id
  defp uploaded_by_id(_), do: nil

  defp track_asset_created({:ok, asset}, user, attrs) do
    properties = asset_analytics_properties(asset, attrs)

    case user do
      %User{} -> Analytics.track(user, "asset uploaded", properties)
      _ -> Analytics.track_system("asset uploaded", properties)
    end

    {:ok, asset}
  end

  defp track_asset_created(result, _user, _attrs), do: result

  defp asset_analytics_properties(asset, attrs) do
    metadata = asset.metadata || %{}

    %{
      asset_type: asset_type_for_content_type(asset.content_type),
      content_type: asset.content_type,
      created_variant: metadata["is_variant"] == true,
      project_id: asset.project_id,
      purpose: analytics_value(Map.get(attrs, :purpose) || Map.get(attrs, "purpose")),
      size_bucket: size_bucket(asset.size)
    }
  end

  defp asset_type_for_content_type(content_type) when is_binary(content_type) do
    content_type
    |> String.split("/", parts: 2)
    |> List.first()
  end

  defp asset_type_for_content_type(_content_type), do: nil

  defp size_bucket(size) when is_integer(size) and size < 100 * 1024, do: "under_100kb"
  defp size_bucket(size) when is_integer(size) and size < 1024 * 1024, do: "100kb_to_1mb"
  defp size_bucket(size) when is_integer(size) and size < 10 * 1024 * 1024, do: "1mb_to_10mb"
  defp size_bucket(size) when is_integer(size), do: "over_10mb"
  defp size_bucket(_size), do: nil

  defp analytics_value(value) when is_atom(value), do: Atom.to_string(value)
  defp analytics_value(value), do: value

  defp extract_image_metadata(path, content_type) do
    if String.starts_with?(content_type, "image/") and ImageProcessor.available?() do
      case ImageProcessor.get_dimensions(path) do
        {:ok, %{width: w, height: h}} -> %{"width" => w, "height" => h}
        {:error, _} -> %{}
      end
    else
      %{}
    end
  end

  # =============================================================================
  # Asset Type Checks & Display
  # =============================================================================

  @doc """
  Returns the optimized web URL if a variant exists, otherwise the original URL.

  Delegates to `Storyarn.Assets.Asset.display_url/1`.
  """
  defdelegate display_url(asset), to: Asset

  @doc """
  Checks if an asset is an image based on its content type.

  Delegates to `Storyarn.Assets.Asset.image?/1`.
  """
  defdelegate image?(asset), to: Asset

  @doc """
  Checks if an asset is an audio file based on its content type.

  Delegates to `Storyarn.Assets.Asset.audio?/1`.
  """
  defdelegate audio?(asset), to: Asset

  @doc """
  Checks if a content type is in the allowed list for uploads.

  Delegates to `Storyarn.Assets.Asset.allowed_content_type?/1`.
  """
  defdelegate allowed_content_type?(content_type), to: Asset

  # =============================================================================
  # Storage Delegations
  # =============================================================================

  @doc """
  Uploads a file to storage.

  This is a low-level storage operation and does not create or reserve an
  `Asset` row. Use `upload_binary_and_create_asset/4` whenever the object will
  be adopted by the database so compensation cannot race the separate insert.
  """
  defdelegate storage_upload(key, data, content_type), to: Storage, as: :upload

  @doc """
  Deletes a file from storage.

  Delegates to `Storyarn.Assets.Storage.delete/1`.
  """
  defdelegate storage_delete(key), to: Storage, as: :delete

  @doc """
  Downloads a file from storage as raw binary data.

  Delegates to `Storyarn.Assets.Storage.download/1`.
  """
  defdelegate storage_download(key), to: Storage, as: :download

  # =============================================================================
  # ImageProcessor Delegations
  # =============================================================================

  @doc """
  Checks if the image processor (ImageMagick) is available.

  Delegates to `Storyarn.Assets.ImageProcessor.available?/0`.
  """
  defdelegate image_processor_available?(), to: ImageProcessor, as: :available?

  @doc """
  Gets the dimensions of an image file.

  Delegates to `Storyarn.Assets.ImageProcessor.get_dimensions/1`.
  """
  defdelegate image_processor_get_dimensions(path), to: ImageProcessor, as: :get_dimensions

  @doc """
  Sanitizes a filename for safe storage.

  Strips path components, replaces unsafe characters, downcases, and limits length.
  """
  @spec sanitize_filename(String.t()) :: String.t()
  def sanitize_filename(filename) do
    sanitized =
      filename
      |> String.split(~r/[\/\\]/)
      |> List.last()
      |> String.replace(~r/[^\w\.\-]/, "_")
      |> String.downcase()
      |> String.slice(0, 255)

    case sanitized do
      value when value in ["", ".", ".."] -> "file"
      ".storyarn-copy" -> "_storyarn-copy"
      value -> value
    end
  end

  # =============================================================================
  # Export / Import helpers
  # =============================================================================

  @doc """
  Lists all assets for a project for export.
  Ordered by insertion time.
  """
  @spec list_assets_for_export(integer()) :: [asset()]
  def list_assets_for_export(project_id) do
    Repo.all(
      from(a in Asset,
        where: a.project_id == ^project_id and is_nil(a.deleted_at),
        order_by: [asc: a.inserted_at, asc: a.id]
      )
    )
  end

  @doc """
  Ensures every unique blob referenced by an active asset has canonical
  project-scoped recovery storage.

  Existing canonical objects are fully verified. A missing or corrupt object
  is reconstructed only from an original asset object whose size, content
  type, and SHA-256 match the persisted row. Duplicate logical assets share
  one repair attempt, with equivalent originals used as verified fallbacks.
  """
  @spec ensure_active_asset_blobs(pos_integer()) ::
          {:ok,
           %{
             asset_count: non_neg_integer(),
             blob_count: non_neg_integer(),
             repaired_blob_count: non_neg_integer()
           }}
          | {:error, term()}
  def ensure_active_asset_blobs(project_id) when is_integer(project_id) and project_id > 0 do
    project_id
    |> list_assets_for_export()
    |> ensure_asset_blobs()
  end

  def ensure_active_asset_blobs(_project_id), do: {:error, :invalid_project_id}

  @doc false
  @spec ensure_asset_blobs([Asset.t()]) ::
          {:ok,
           %{
             asset_count: non_neg_integer(),
             blob_count: non_neg_integer(),
             repaired_blob_count: non_neg_integer()
           }}
          | {:error, term()}
  def ensure_asset_blobs(assets) when is_list(assets) do
    if Enum.all?(assets, &match?(%Asset{}, &1)) do
      project_ids = assets |> Enum.map(& &1.project_id) |> Enum.uniq()

      if length(project_ids) <= 1,
        do: do_ensure_asset_blobs(assets, List.first(project_ids)),
        else: {:error, :invalid_asset_blob_inventory}
    else
      {:error, :invalid_asset_blob_inventory}
    end
  end

  def ensure_asset_blobs(_assets), do: {:error, :invalid_asset_blob_inventory}

  defp do_ensure_asset_blobs(assets, project_id) do
    blob_groups =
      assets
      |> Enum.group_by(&active_asset_blob_identity/1)
      |> Enum.sort_by(fn {identity, _assets} -> identity end)

    result =
      Enum.reduce_while(
        blob_groups,
        {:ok,
         %{
           asset_count: length(assets),
           blob_count: length(blob_groups),
           repaired_blob_count: 0
         }},
        fn {_identity, equivalent_assets}, {:ok, summary} ->
          case ensure_equivalent_asset_blob(equivalent_assets) do
            {:ok, _storage_key, :present} ->
              {:cont, {:ok, summary}}

            {:ok, _storage_key, :repaired} ->
              {:cont, {:ok, Map.update!(summary, :repaired_blob_count, &(&1 + 1))}}

            {:error, errors} ->
              first_asset = hd(equivalent_assets)

              {:halt,
               {:error,
                {:active_asset_blob_unavailable,
                 %{
                   asset_ids: Enum.map(equivalent_assets, & &1.id),
                   blob_hash: first_asset.blob_hash,
                   errors: errors
                 }}}}
          end
        end
      )

    report_active_asset_blob_repairs(result, project_id)
    result
  end

  @doc false
  @spec ensure_snapshot_asset_blobs(pos_integer(), [map()]) ::
          {:ok,
           %{
             asset_count: non_neg_integer(),
             blob_count: non_neg_integer(),
             repaired_blob_count: non_neg_integer()
           }}
          | {:error, term()}
  def ensure_snapshot_asset_blobs(project_id, blob_specs)
      when is_integer(project_id) and project_id > 0 and is_list(blob_specs) do
    with {:ok, specs} <- normalize_snapshot_blob_specs(blob_specs) do
      ensure_normalized_snapshot_asset_blobs(project_id, specs)
    end
  end

  def ensure_snapshot_asset_blobs(_project_id, _blob_specs), do: {:error, :invalid_snapshot_asset_blob_inventory}

  defp ensure_normalized_snapshot_asset_blobs(project_id, specs) do
    candidates = snapshot_blob_candidates(project_id, specs)

    candidates_by_identity =
      Enum.group_by(candidates, fn asset ->
        {asset.blob_hash, asset.size, asset.content_type, sanitized_svg_asset?(asset)}
      end)

    initial_summary =
      {:ok,
       %{
         asset_count: length(candidates),
         blob_count: length(specs),
         repaired_blob_count: 0
       }}

    result =
      Enum.reduce_while(specs, initial_summary, fn spec, summary ->
        ensure_snapshot_blob_spec(project_id, candidates_by_identity, spec, summary)
      end)

    report_active_asset_blob_repairs(result, project_id)
    result
  end

  defp snapshot_blob_candidates(project_id, specs) do
    captured_asset_ids = specs |> Enum.flat_map(& &1.asset_ids) |> Enum.uniq()

    Repo.all(
      from(asset in Asset,
        where: asset.project_id == ^project_id and asset.id in ^captured_asset_ids,
        order_by: [asc: asset.id]
      )
    )
  end

  defp ensure_snapshot_blob_spec(project_id, candidates_by_identity, spec, {:ok, summary}) do
    identity = {spec.blob_hash, spec.size, spec.content_type, spec.sanitized_svg}
    equivalent_assets = Map.get(candidates_by_identity, identity, [])

    project_id
    |> ensure_snapshot_blob(spec, equivalent_assets)
    |> update_snapshot_blob_summary(summary, spec)
  end

  defp update_snapshot_blob_summary({:ok, _storage_key, :present}, summary, _spec), do: {:cont, {:ok, summary}}

  defp update_snapshot_blob_summary({:ok, _storage_key, :repaired}, summary, _spec) do
    {:cont, {:ok, Map.update!(summary, :repaired_blob_count, &(&1 + 1))}}
  end

  defp update_snapshot_blob_summary({:error, errors}, _summary, spec) do
    {:halt,
     {:error,
      {:snapshot_asset_blob_unavailable,
       %{
         asset_ids: spec.asset_ids,
         blob_hash: spec.blob_hash,
         errors: errors
       }}}}
  end

  defp normalize_snapshot_blob_specs(blob_specs) do
    with {:ok, specs} <- Enum.reduce_while(blob_specs, {:ok, %{}}, &normalize_snapshot_blob_spec/2) do
      {:ok, materialize_snapshot_blob_specs(specs)}
    end
  end

  defp normalize_snapshot_blob_spec(
         %{
           blob_hash: blob_hash,
           size: size,
           content_type: content_type,
           sanitized_svg: sanitized_svg,
           asset_ids: asset_ids
         },
         {:ok, specs}
       ) do
    if valid_snapshot_blob_spec_shape?(blob_hash, size, content_type, sanitized_svg, asset_ids) do
      asset_ids = Enum.sort(asset_ids)
      identity = {blob_hash, size, content_type, sanitized_svg, asset_ids}

      validate_snapshot_blob_spec(specs, blob_hash, content_type, sanitized_svg, asset_ids, identity)
    else
      invalid_snapshot_blob_spec()
    end
  end

  defp normalize_snapshot_blob_spec(_invalid, _acc), do: invalid_snapshot_blob_spec()

  defp valid_snapshot_blob_spec_shape?(blob_hash, size, content_type, sanitized_svg, asset_ids) do
    is_binary(blob_hash) and is_integer(size) and size > 0 and is_binary(content_type) and
      content_type != "" and is_boolean(sanitized_svg) and is_list(asset_ids)
  end

  defp validate_snapshot_blob_spec(specs, blob_hash, content_type, sanitized_svg, asset_ids, identity) do
    cond do
      not Regex.match?(@sha256_regex, blob_hash) ->
        invalid_snapshot_blob_spec()

      not valid_snapshot_blob_content_type?(content_type, sanitized_svg) ->
        invalid_snapshot_blob_spec()

      not valid_captured_asset_ids?(asset_ids) ->
        invalid_snapshot_blob_spec()

      Map.has_key?(specs, blob_hash) and specs[blob_hash] != identity ->
        invalid_snapshot_blob_spec()

      true ->
        {:cont, {:ok, Map.put(specs, blob_hash, identity)}}
    end
  end

  defp valid_captured_asset_ids?(asset_ids) do
    asset_ids != [] and Enum.all?(asset_ids, &(is_integer(&1) and &1 > 0)) and
      length(asset_ids) == length(Enum.uniq(asset_ids))
  end

  defp invalid_snapshot_blob_spec, do: {:halt, {:error, :invalid_snapshot_asset_blob_inventory}}

  defp materialize_snapshot_blob_specs(specs) do
    specs
    |> Map.values()
    |> Enum.map(fn {blob_hash, size, content_type, sanitized_svg, asset_ids} ->
      %{
        blob_hash: blob_hash,
        size: size,
        content_type: content_type,
        sanitized_svg: sanitized_svg,
        asset_ids: asset_ids
      }
    end)
    |> Enum.sort_by(& &1.blob_hash)
  end

  defp ensure_snapshot_blob(project_id, spec, equivalent_assets) do
    case BlobStore.verify_asset_blob(project_id, spec.blob_hash, spec.size, spec.content_type,
           sanitized_svg: spec.sanitized_svg
         ) do
      {:ok, _storage_key, :present} = present ->
        present

      {:error, verification_reason} ->
        repair_snapshot_blob(equivalent_assets, verification_reason)
    end
  end

  defp repair_snapshot_blob(equivalent_assets, verification_reason) do
    equivalent_assets
    |> Enum.reduce_while({:error, []}, &try_snapshot_blob_candidate/2)
    |> normalize_snapshot_blob_repair(verification_reason)
  end

  defp try_snapshot_blob_candidate(asset, {:error, errors}) do
    case BlobStore.ensure_asset_blob(asset) do
      {:ok, _storage_key, _status} = success -> {:halt, success}
      {:error, reason} -> {:cont, {:error, [{asset.id, reason} | errors]}}
    end
  end

  defp normalize_snapshot_blob_repair({:error, []}, verification_reason), do: {:error, [{nil, verification_reason}]}

  defp normalize_snapshot_blob_repair({:error, errors}, _verification_reason), do: {:error, Enum.reverse(errors)}

  defp normalize_snapshot_blob_repair(success, _verification_reason), do: success

  defp sanitized_svg_asset?(%Asset{content_type: "image/svg+xml", metadata: %{"sanitized_svg" => true}}), do: true
  defp sanitized_svg_asset?(%Asset{}), do: false

  defp valid_snapshot_blob_content_type?("image/svg+xml", true), do: true

  defp valid_snapshot_blob_content_type?(content_type, false), do: Asset.allowed_content_type?(content_type)

  defp valid_snapshot_blob_content_type?(_content_type, _sanitized_svg), do: false

  defp active_asset_blob_identity(%Asset{blob_hash: blob_hash, content_type: content_type}) do
    {blob_hash, BlobStore.ext_from_content_type(content_type)}
  end

  defp ensure_equivalent_asset_blob(equivalent_assets) do
    equivalent_assets
    |> Enum.reduce_while({:error, []}, fn asset, {:error, errors} ->
      case BlobStore.ensure_asset_blob(asset) do
        {:ok, _storage_key, _status} = success -> {:halt, success}
        {:error, reason} -> {:cont, {:error, [{asset.id, reason} | errors]}}
      end
    end)
    |> case do
      {:error, errors} -> {:error, Enum.reverse(errors)}
      success -> success
    end
  end

  defp report_active_asset_blob_repairs({:ok, %{repaired_blob_count: repaired_blob_count}}, project_id)
       when repaired_blob_count > 0 do
    :telemetry.execute(
      [:storyarn, :assets, :canonical_blobs, :repaired],
      %{count: repaired_blob_count},
      %{project_id: project_id}
    )
  end

  defp report_active_asset_blob_repairs(_result, _project_id), do: :ok

  @doc """
  Counts all assets for a project.
  """
  @spec count_assets(integer(), list_opts()) :: non_neg_integer()
  def count_assets(project_id, opts \\ []) do
    from(a in Asset, where: a.project_id == ^project_id and is_nil(a.deleted_at))
    |> apply_content_type_filter(opts)
    |> apply_images_only_filter(opts)
    |> apply_search_filter(opts)
    |> Repo.aggregate(:count)
  end

  # =============================================================================
  # Import helpers (raw insert, no upload side effects)
  # =============================================================================

  @doc """
  Checks the complete logical size of one import and authorizes its asset rows.

  The caller must already hold the workspace storage-accounting lock. The
  authorization is process-scoped to the callback and tracks the remaining
  byte budget, so `import_asset/2` cannot insert more logical bytes than were
  checked against workspace capacity.
  """
  @spec with_import_capacity(Project.t(), non_neg_integer(), (-> result)) ::
          result
          | {:error,
             :asset_import_capacity_already_authorized
             | :invalid_storage_allocation
             | :storage_accounting_lock_required}
          | {:error, :limit_reached, map()}
        when result: term()
  def with_import_capacity(%Project{} = project, total_bytes, fun)
      when is_integer(total_bytes) and total_bytes >= 0 and is_function(fun, 0) do
    with true <- Billing.workspace_lock_held?(project.workspace_id),
         :ok <- Billing.can_upload_asset_for_project?(project, total_bytes) do
      with_import_capacity_marker(project, total_bytes, fun)
    else
      false -> {:error, :storage_accounting_lock_required}
      {:error, _reason, _details} = error -> error
      {:error, _reason} = error -> error
    end
  end

  def with_import_capacity(%Project{}, _total_bytes, _fun), do: {:error, :invalid_storage_allocation}

  @doc """
  Creates an asset record for an authorized import.

  This is a raw database insert with no upload logic or user tracking. It is
  only valid inside `with_import_capacity/3` while the matching workspace lock
  remains held.
  """
  @spec import_asset(Project.t(), attrs()) ::
          {:ok, asset()}
          | {:error, changeset()}
          | {:error,
             :asset_import_capacity_exceeded
             | :asset_import_capacity_required
             | :storage_accounting_lock_required}
  def import_asset(%Project{} = project, attrs) do
    changeset = Asset.create_changeset(%Asset{project_id: project.id}, attrs)

    with :ok <- validate_import_asset_authorization(project),
         {:ok, _locked_project} <- ProjectReferenceIntegrity.lock_active_project(project.id, :update),
         :ok <- lock_asset_family_references(%Asset{project_id: project.id}, attrs),
         :ok <- authorize_import_asset(project, changeset) do
      with_asset_storage_key_lock(attrs, fn -> Repo.insert(changeset) end)
    end
  end

  @doc false
  @spec import_snapshot_asset(Project.t(), pos_integer() | nil, attrs()) ::
          {:ok, asset()}
          | {:error, changeset()}
          | {:error,
             :asset_import_capacity_exceeded
             | :asset_import_capacity_required
             | :invalid_snapshot_asset_storage_key
             | :storage_accounting_lock_required}
  def import_snapshot_asset(%Project{} = project, uploaded_by_id, attrs)
      when is_nil(uploaded_by_id) or (is_integer(uploaded_by_id) and uploaded_by_id > 0) do
    upload_kind = snapshot_asset_upload_kind(attrs)

    changeset =
      asset_create_changeset(
        %Asset{project_id: project.id, uploaded_by_id: uploaded_by_id},
        attrs,
        upload_kind
      )

    with :ok <- validate_import_asset_authorization(project),
         :ok <- validate_snapshot_asset_storage_key(project.id, attrs),
         {:ok, _locked_project} <- lock_active_project_for_asset_write(project.id, project.workspace_id),
         :ok <- lock_asset_family_references(%Asset{project_id: project.id}, attrs),
         :ok <- authorize_import_asset(project, changeset) do
      with_asset_storage_key_lock(attrs, fn -> Repo.insert(changeset) end)
    end
  end

  def import_snapshot_asset(%Project{}, _uploaded_by_id, _attrs), do: {:error, :invalid_snapshot_asset_import}

  @doc false
  @spec update_imported_snapshot_asset_locked(Project.t(), asset(), map()) ::
          {:ok, asset()} | {:error, term()}
  def update_imported_snapshot_asset_locked(%Project{} = project, %Asset{project_id: project_id} = asset, metadata)
      when project.id == project_id and is_map(metadata) do
    with :ok <- validate_import_asset_authorization(project),
         {:ok, _locked_project} <- lock_active_project_for_asset_write(project.id, project.workspace_id),
         {:ok, locked_asset} <- lock_asset_for_write(asset.id, project.id),
         :ok <- lock_asset_family_references(locked_asset, %{metadata: metadata}) do
      locked_asset
      |> Asset.update_changeset(%{metadata: metadata})
      |> Repo.update()
    end
  end

  def update_imported_snapshot_asset_locked(_project, _asset, _metadata),
    do: {:error, :invalid_snapshot_asset_relationship_update}

  @doc false
  @spec import_snapshot_assets_locked(Project.t(), pos_integer() | nil, [attrs()]) ::
          {:ok, [asset()]}
          | {:error, {:snapshot_asset_batch_entry_failed, non_neg_integer(), term()} | term()}
  def import_snapshot_assets_locked(%Project{} = project, uploaded_by_id, attrs_list)
      when (is_nil(uploaded_by_id) or (is_integer(uploaded_by_id) and uploaded_by_id > 0)) and is_list(attrs_list) do
    with :ok <- validate_import_asset_authorization(project),
         {:ok, _locked_project} <- lock_active_project_for_asset_write(project.id, project.workspace_id),
         {:ok, changesets} <- prepare_snapshot_asset_changesets(project, uploaded_by_id, attrs_list),
         :ok <- lock_snapshot_asset_insert_family_references(project.id, changesets) do
      storage_keys = Enum.map(changesets, &Ecto.Changeset.get_field(&1, :key))

      StorageKeyLock.with_storage_key_locks(storage_keys, fn ->
        insert_snapshot_asset_changesets(changesets)
      end)
    end
  end

  def import_snapshot_assets_locked(_project, _uploaded_by_id, _attrs_list), do: {:error, :invalid_snapshot_asset_import}

  @doc false
  @spec update_imported_snapshot_assets_locked(Project.t(), [{asset(), map()}]) ::
          {:ok, [asset()]}
          | {:error, {:snapshot_asset_batch_entry_failed, non_neg_integer(), term()} | term()}
  def update_imported_snapshot_assets_locked(%Project{} = project, updates) when is_list(updates) do
    with :ok <- validate_import_asset_authorization(project),
         {:ok, _locked_project} <- lock_active_project_for_asset_write(project.id, project.workspace_id),
         {:ok, locked_assets} <- lock_snapshot_assets_for_update(project.id, updates),
         :ok <- lock_snapshot_asset_family_references(project.id, updates),
         {:ok, changesets} <- prepare_snapshot_asset_update_changesets(updates, locked_assets) do
      upsert_snapshot_asset_changesets(changesets)
    end
  end

  def update_imported_snapshot_assets_locked(_project, _updates),
    do: {:error, :invalid_snapshot_asset_relationship_update}

  defp with_import_capacity_marker(project, total_bytes, fun) do
    case Process.get(@import_capacity_process_key) do
      nil ->
        Process.put(@import_capacity_process_key, %{
          workspace_id: project.workspace_id,
          project_id: project.id,
          remaining_bytes: total_bytes
        })

        try do
          fun.()
        after
          Process.delete(@import_capacity_process_key)
        end

      _capacity ->
        {:error, :asset_import_capacity_already_authorized}
    end
  end

  defp prepare_snapshot_asset_changesets(project, uploaded_by_id, attrs_list) do
    attrs_list
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {attrs, index}, {:ok, changesets} ->
      upload_kind = snapshot_asset_upload_kind(attrs)

      changeset =
        asset_create_changeset(
          %Asset{project_id: project.id, uploaded_by_id: uploaded_by_id},
          attrs,
          upload_kind
        )

      result =
        with :ok <- validate_snapshot_asset_storage_key(project.id, attrs),
             true <- changeset.valid?,
             :ok <- consume_import_capacity(project, changeset) do
          {:ok, changeset}
        else
          false -> {:error, changeset}
          {:error, _reason} = error -> error
        end

      case result do
        {:ok, changeset} -> {:cont, {:ok, [changeset | changesets]}}
        {:error, reason} -> {:halt, {:error, {:snapshot_asset_batch_entry_failed, index, reason}}}
      end
    end)
    |> case do
      {:ok, changesets} -> {:ok, Enum.reverse(changesets)}
      {:error, _reason} = error -> error
    end
  end

  defp insert_snapshot_asset_changesets([]), do: {:ok, []}

  defp insert_snapshot_asset_changesets(changesets) do
    now = TimeHelpers.now()
    rows = Enum.map(changesets, &asset_insert_row(&1, now))

    with {:ok, assets} <- insert_snapshot_asset_batches(rows) do
      reorder_assets_by(rows, assets, :key)
    end
  end

  defp insert_snapshot_asset_batches(rows) do
    rows
    |> Enum.chunk_every(@snapshot_asset_batch_size)
    |> Enum.reduce_while({:ok, []}, fn batch, {:ok, assets} ->
      case Repo.insert_all(Asset, batch,
             on_conflict: :nothing,
             conflict_target: [:project_id, :key],
             returning: true
           ) do
        {count, inserted} when count == length(batch) ->
          {:cont, {:ok, [inserted | assets]}}

        {_count, _inserted} ->
          {:halt, {:error, :snapshot_asset_insert_conflict}}
      end
    end)
    |> flatten_snapshot_asset_batches()
  end

  defp lock_snapshot_assets_for_update(project_id, updates) do
    ids = Enum.map(updates, fn {asset, _metadata} -> asset.id end)

    assets =
      Repo.all(
        from asset in Asset,
          where: asset.project_id == ^project_id and asset.id in ^ids and is_nil(asset.deleted_at),
          order_by: [asc: asset.id],
          lock: "FOR UPDATE"
      )

    if length(ids) == MapSet.size(MapSet.new(ids)) and
         MapSet.new(Enum.map(assets, & &1.id)) == MapSet.new(ids),
       do: {:ok, Map.new(assets, &{&1.id, &1})},
       else: {:error, :snapshot_asset_inventory_mismatch}
  end

  defp lock_snapshot_asset_insert_family_references(project_id, changesets) do
    changesets
    |> Enum.with_index()
    |> Enum.map(fn {changeset, index} ->
      metadata = Ecto.Changeset.get_field(changeset, :metadata)
      {{:snapshot_asset_import, index}, metadata}
    end)
    |> lock_snapshot_asset_family_reference_specs(project_id)
  end

  defp lock_snapshot_asset_family_references(project_id, updates) do
    updates
    |> Enum.map(fn {asset, metadata} -> {{:asset_family, asset.id}, metadata} end)
    |> lock_snapshot_asset_family_reference_specs(project_id)
  end

  defp lock_snapshot_asset_family_reference_specs(entries, project_id) do
    entries
    |> Enum.reduce_while({:ok, []}, fn {context, metadata}, {:ok, specs} ->
      case Asset.family_reference_ids(metadata) do
        {:ok, ids} ->
          refs = Enum.map(ids, &{:asset, context, &1})
          {:cont, {:ok, refs ++ specs}}

        :error ->
          {:halt, {:error, :asset_family_identity_invalid}}
      end
    end)
    |> case do
      {:ok, specs} ->
        case ProjectReferenceIntegrity.lock_active_references(project_id, specs) do
          {:ok, _ids} -> :ok
          {:error, _reason} -> {:error, :asset_family_identity_invalid}
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp prepare_snapshot_asset_update_changesets(updates, locked_assets) do
    updates
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {{asset, metadata}, index}, {:ok, changesets} ->
      locked_asset = Map.fetch!(locked_assets, asset.id)
      changeset = Asset.update_changeset(locked_asset, %{metadata: metadata})

      if changeset.valid?,
        do: {:cont, {:ok, [changeset | changesets]}},
        else: {:halt, {:error, {:snapshot_asset_batch_entry_failed, index, changeset}}}
    end)
    |> case do
      {:ok, changesets} -> {:ok, Enum.reverse(changesets)}
      {:error, _reason} = error -> error
    end
  end

  defp upsert_snapshot_asset_changesets([]), do: {:ok, []}

  defp upsert_snapshot_asset_changesets(changesets) do
    now = TimeHelpers.now()
    rows = Enum.map(changesets, &asset_update_row(&1, now))

    with {:ok, assets} <- upsert_snapshot_asset_batches(rows) do
      reorder_assets_by(rows, assets, :id)
    end
  end

  defp upsert_snapshot_asset_batches(rows) do
    rows
    |> Enum.chunk_every(@snapshot_asset_batch_size)
    |> Enum.reduce_while({:ok, []}, fn batch, {:ok, assets} ->
      case Repo.insert_all(Asset, batch,
             on_conflict: {:replace, [:metadata, :updated_at]},
             conflict_target: [:id],
             returning: true
           ) do
        {count, updated} when count == length(batch) ->
          {:cont, {:ok, [updated | assets]}}

        {_count, _updated} ->
          {:halt, {:error, :snapshot_asset_relationship_update_failed}}
      end
    end)
    |> flatten_snapshot_asset_batches()
  end

  defp flatten_snapshot_asset_batches({:ok, batches}) do
    {:ok, batches |> Enum.reverse() |> Enum.concat()}
  end

  defp flatten_snapshot_asset_batches({:error, _reason} = error), do: error

  defp asset_insert_row(changeset, now) do
    changeset
    |> Ecto.Changeset.apply_changes()
    |> asset_fields()
    |> Map.delete(:id)
    |> Map.put(:inserted_at, now)
    |> Map.put(:updated_at, now)
  end

  defp asset_update_row(changeset, now) do
    changeset
    |> Ecto.Changeset.apply_changes()
    |> asset_fields()
    |> Map.put(:updated_at, now)
  end

  defp asset_fields(asset) do
    asset
    |> Map.from_struct()
    |> Map.take(Asset.__schema__(:fields))
  end

  defp reorder_assets_by(rows, assets, field) do
    assets_by_field = Map.new(assets, &{Map.fetch!(&1, field), &1})

    if map_size(assets_by_field) == length(rows) do
      {:ok, Enum.map(rows, &Map.fetch!(assets_by_field, Map.fetch!(&1, field)))}
    else
      {:error, :snapshot_asset_insert_result_mismatch}
    end
  end

  defp authorize_import_asset(project, changeset) do
    with :ok <- validate_import_asset_authorization(project) do
      consume_import_capacity(project, changeset)
    end
  end

  defp validate_import_asset_authorization(project) do
    if Billing.workspace_lock_held?(project.workspace_id) do
      case Process.get(@import_capacity_process_key) do
        %{workspace_id: workspace_id, project_id: project_id}
        when workspace_id == project.workspace_id and project_id == project.id ->
          :ok

        _capacity ->
          {:error, :asset_import_capacity_required}
      end
    else
      {:error, :storage_accounting_lock_required}
    end
  end

  defp snapshot_asset_upload_kind(attrs) do
    content_type = Map.get(attrs, :content_type, Map.get(attrs, "content_type"))
    metadata = Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))

    if content_type == "image/svg+xml" and metadata["sanitized_svg"] == true,
      do: :sanitized_svg,
      else: :generic
  end

  defp validate_snapshot_asset_storage_key(project_id, attrs) do
    key = Map.get(attrs, :key, Map.get(attrs, "key"))
    prefix = "projects/#{project_id}/assets/"

    case key do
      <<^prefix::binary, tail::binary>> ->
        validate_snapshot_asset_storage_tail(tail)

      _key ->
        {:error, :invalid_snapshot_asset_storage_key}
    end
  end

  defp validate_snapshot_asset_storage_tail(tail) do
    case String.split(tail, "/", trim: false) do
      [uuid, filename] -> validate_snapshot_asset_storage_parts(uuid, filename)
      _parts -> {:error, :invalid_snapshot_asset_storage_key}
    end
  end

  defp validate_snapshot_asset_storage_parts(uuid, filename) do
    with {:ok, _uuid} <- Ecto.UUID.cast(uuid),
         true <- filename == sanitize_filename(filename),
         true <- filename not in ["", ".", ".."] do
      :ok
    else
      _invalid -> {:error, :invalid_snapshot_asset_storage_key}
    end
  end

  defp consume_import_capacity(project, changeset) do
    case Process.get(@import_capacity_process_key) do
      %{workspace_id: workspace_id, project_id: project_id} = capacity
      when workspace_id == project.workspace_id and project_id == project.id ->
        consume_valid_import_size(capacity, changeset)

      _capacity ->
        {:error, :asset_import_capacity_required}
    end
  end

  defp consume_valid_import_size(capacity, %{valid?: true} = changeset) do
    size = Ecto.Changeset.get_field(changeset, :size)

    if size <= capacity.remaining_bytes do
      Process.put(@import_capacity_process_key, %{capacity | remaining_bytes: capacity.remaining_bytes - size})
      :ok
    else
      {:error, :asset_import_capacity_exceeded}
    end
  end

  defp consume_valid_import_size(_capacity, _changeset), do: :ok

  defp with_asset_storage_key_lock(attrs, fun) when is_map(attrs) and is_function(fun, 0) do
    case Map.get(attrs, :key, Map.get(attrs, "key")) do
      storage_key when is_binary(storage_key) ->
        StorageKeyLock.with_storage_key_lock(storage_key, fun)

      _storage_key ->
        fun.()
    end
  end
end
