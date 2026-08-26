defmodule Storyarn.Sheets.Assets.Commands.Assets do
  @moduledoc """
  Sheet-owned asset writes and version materialization.

  Sheets intentionally reads and writes the shared asset tables through local
  projections. Storage is a technical adapter; Project asset commands and
  Project domain models are not part of this boundary.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Platform
  alias Storyarn.Platform.Shared.HtmlSanitizer
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo
  alias Storyarn.Sheets.Assets.Adapters.Images.Processor, as: ImageProcessor
  alias Storyarn.Sheets.Assets.Adapters.Storage.Compensation, as: AssetStorageCompensation
  alias Storyarn.Sheets.Assets.Adapters.Storage.Hashing, as: StorageHash
  alias Storyarn.Sheets.Assets.Adapters.Storage.Locks, as: StorageKeyLock
  alias Storyarn.Sheets.Assets.Adapters.Storage.Objects, as: Storage
  alias Storyarn.Sheets.Assets.Data.AssetRecord
  alias Storyarn.Sheets.Assets.Data.ProjectRecord
  alias Storyarn.Sheets.Assets.Data.ProjectSnapshotRecord
  alias Storyarn.Sheets.Assets.Data.StorageReservationRecord
  alias Storyarn.Sheets.Assets.Data.UserRecord
  alias Storyarn.Sheets.Assets.Data.WorkspaceRecord
  alias Storyarn.Sheets.Assets.Data.WorkspaceSnapshotImportRecord
  alias Storyarn.Sheets.Assets.Events

  require Logger

  @allowed_content_types ~w(
    image/jpeg image/png image/gif image/webp
    audio/mpeg audio/wav audio/ogg audio/webm
    application/pdf
  )
  @snapshot_content_types @allowed_content_types ++
                            ["image/svg+xml", "application/octet-stream"]
  @svg_content_type "image/svg+xml"
  @max_asset_size 52_428_800
  @sha256_regex ~r/\A[0-9a-f]{64}\z/
  @workspace_lock_key {__MODULE__, :workspace_lock}
  @accounting_version 1
  @active_workspace_import_statuses ~w(uploading queued running retrying)

  defguardp valid_version_asset_request_args(project_id, uploaded_by_id, blob_hash, source_key, metadata, opts)
            when is_integer(project_id) and project_id > 0 and
                   (is_nil(uploaded_by_id) or
                      (is_integer(uploaded_by_id) and uploaded_by_id > 0)) and
                   is_binary(blob_hash) and is_binary(source_key) and is_map(metadata) and is_list(opts)

  @spec upload_asset(String.t(), map(), map() | pos_integer(), map() | pos_integer(), keyword()) ::
          {:ok, AssetRecord.t()} | {:error, term()} | {:error, :limit_reached, map()}
  # sobelow_skip ["Traversal.FileModule"]
  def upload_asset(path, entry, project, user, opts \\ []) when is_binary(path) and is_map(entry) and is_list(opts) do
    binary = File.read!(path)

    content_type = Map.get(entry, :client_type)

    attrs = %{
      filename: Map.get(entry, :client_name),
      content_type: content_type,
      metadata: extract_image_metadata(path, content_type),
      purpose: Keyword.get(opts, :purpose)
    }

    create_binary_asset(binary, attrs, project, user)
  end

  @spec create_generated_asset(binary(), map(), map() | pos_integer(), map() | pos_integer() | nil) ::
          {:ok, AssetRecord.t()} | {:error, term()} | {:error, :limit_reached, map()}
  def create_generated_asset(binary, attrs, project, user \\ nil) do
    create_binary_asset(binary, attrs, project, user)
  end

  @spec create_binary_asset(binary(), map(), map() | pos_integer(), map() | pos_integer() | nil) ::
          {:ok, AssetRecord.t()} | {:error, term()} | {:error, :limit_reached, map()}
  def create_binary_asset(binary, attrs, project, user \\ nil) when is_binary(binary) and is_map(attrs) do
    create_uploaded_asset(
      binary,
      attrs,
      project_id!(project),
      optional_user_id!(user),
      event_subject(user),
      :generic
    )
  end

  @spec create_sanitized_svg_asset(binary(), map(), map() | pos_integer(), map() | pos_integer() | nil) ::
          {:ok, AssetRecord.t()} | {:error, term()} | {:error, :limit_reached, map()}
  def create_sanitized_svg_asset(binary, attrs, project, user \\ nil) when is_binary(binary) and is_map(attrs) do
    with @svg_content_type <- attr(attrs, :content_type),
         {:ok, sanitized_svg} <- sanitize_svg(binary) do
      attrs =
        attrs
        |> normalize_attrs()
        |> Map.put(:metadata, attrs |> metadata() |> Map.put("sanitized_svg", true))

      create_uploaded_asset(
        sanitized_svg,
        attrs,
        project_id!(project),
        optional_user_id!(user),
        event_subject(user),
        :sanitized_svg
      )
    else
      _invalid -> {:error, :invalid_svg}
    end
  end

  @doc false
  def run_asset_materialization_scope(opts, fun) when is_list(opts) and is_function(fun, 1) do
    case copy_tracker_scope(opts) do
      {:ok, tracker, owns_tracker?} ->
        scoped_opts = Keyword.put(opts, :asset_copy_tracker, tracker)

        try do
          scoped_opts
          |> fun.()
          |> finalize_owned_tracker(tracker, owns_tracker?)
        rescue
          error ->
            cleanup_owned_tracker!(tracker, owns_tracker?)
            reraise error, __STACKTRACE__
        catch
          kind, reason ->
            cleanup_owned_tracker!(tracker, owns_tracker?)
            :erlang.raise(kind, reason, __STACKTRACE__)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  def with_asset_copy_tracker(opts, fun) when is_list(opts) and is_function(fun, 1) do
    if Keyword.get(opts, :asset_mode) == :copy do
      with_copy_tracker(opts, fun)
    else
      fun.(opts)
    end
  end

  defp with_copy_tracker(opts, fun) do
    case Keyword.get(opts, :asset_copy_tracker) do
      tracker when is_reference(tracker) -> fun.(opts)
      _tracker -> with_owned_copy_tracker(opts, fun)
    end
  end

  defp with_owned_copy_tracker(opts, fun) do
    if Repo.in_transaction?() do
      {:error, :asset_copy_tracker_required_in_transaction}
    else
      tracker = AssetStorageCompensation.new()

      run_owned_asset_tracker(tracker, fn ->
        opts
        |> Keyword.put(:asset_copy_tracker, tracker)
        |> fun.()
      end)
    end
  end

  @doc false
  def with_project_storage_lock(project_id, fun) when is_integer(project_id) and project_id > 0 and is_function(fun, 0) do
    with {:ok, workspace_id} <- project_workspace_id(project_id) do
      previous_lock = Process.get(@workspace_lock_key)
      Process.put(@workspace_lock_key, workspace_id)

      try do
        fn ->
          with {:ok, _workspace} <- lock_workspace(workspace_id),
               {:ok, _project} <- lock_active_project(project_id, workspace_id) do
            normalize_locked_callback(fun.())
          else
            {:error, reason} -> Repo.rollback(reason)
          end
        end
        |> Repo.transaction(timeout: :infinity)
        |> normalize_locked_result()
      after
        restore_workspace_lock(previous_lock)
      end
    end
  end

  def with_project_storage_lock(_project_id, _fun), do: {:error, :project_not_found}

  @doc false
  def create_version_asset_from_storage(project_id, uploaded_by_id, blob_hash, source_key, metadata, opts \\ [])

  def create_version_asset_from_storage(project_id, uploaded_by_id, blob_hash, source_key, metadata, opts)
      when valid_version_asset_request_args(project_id, uploaded_by_id, blob_hash, source_key, metadata, opts) do
    caller_transactional? = Repo.in_transaction?()

    with :ok <- validate_version_request(blob_hash, source_key, metadata),
         :ok <- validate_user(uploaded_by_id),
         {:ok, tracker, owns_tracker?} <- asset_copy_tracker(opts, caller_transactional?) do
      run_version_asset_materialization(%{
        project_id: project_id,
        uploaded_by_id: uploaded_by_id,
        blob_hash: blob_hash,
        source_key: source_key,
        metadata: metadata,
        opts: Keyword.put(opts, :asset_copy_tracker, tracker),
        tracker: tracker,
        owns_tracker?: owns_tracker?,
        caller_transactional?: caller_transactional?
      })
    end
  end

  def create_version_asset_from_storage(_project_id, _uploaded_by_id, _blob_hash, _source_key, _metadata, _opts),
    do: {:error, :invalid_asset_materialization_request}

  defp run_version_asset_materialization(materialization) do
    materialization
    |> execute_version_asset_materialization()
    |> finalize_owned_tracker(materialization.tracker, materialization.owns_tracker?)
    |> normalize_materialization_result()
  rescue
    error ->
      cleanup_owned_tracker!(materialization.tracker, materialization.owns_tracker?)
      reraise error, __STACKTRACE__
  catch
    kind, reason ->
      cleanup_owned_tracker!(materialization.tracker, materialization.owns_tracker?)
      :erlang.raise(kind, reason, __STACKTRACE__)
  end

  defp execute_version_asset_materialization(%{caller_transactional?: true} = materialization) do
    with :ok <- require_workspace_lock(materialization.project_id) do
      create_version_asset_from_materialization(materialization)
    end
  end

  defp execute_version_asset_materialization(materialization) do
    with_project_storage_lock(materialization.project_id, fn ->
      create_version_asset_from_materialization(materialization)
    end)
  end

  defp create_version_asset_from_materialization(materialization) do
    create_version_asset_under_lock(
      materialization.project_id,
      materialization.uploaded_by_id,
      materialization.blob_hash,
      materialization.source_key,
      materialization.metadata,
      materialization.opts
    )
  end

  defp create_uploaded_asset(binary, attrs, project_id, uploaded_by_id, event_subject, upload_kind) do
    if Repo.in_transaction?() do
      {:error, :asset_upload_transaction_owner_required}
    else
      create_owned_uploaded_asset(binary, attrs, project_id, uploaded_by_id, event_subject, upload_kind)
    end
  end

  defp create_owned_uploaded_asset(binary, attrs, project_id, uploaded_by_id, event_subject, upload_kind) do
    with {:ok, upload} <- prepare_uploaded_asset(binary, attrs, project_id, uploaded_by_id, upload_kind) do
      finish_owned_uploaded_asset(upload, event_subject)
    end
  end

  defp finish_owned_uploaded_asset(upload, event_subject) do
    tracker = AssetStorageCompensation.new()

    result =
      run_owned_asset_tracker(tracker, fn ->
        with_project_storage_lock(upload.project_id, fn ->
          upload_prepared_asset_under_lock(upload, tracker)
        end)
      end)

    after_asset_created(
      result,
      upload.binary,
      upload.attrs,
      upload.project_id,
      upload.uploaded_by_id,
      event_subject
    )
  end

  defp prepare_uploaded_asset(binary, attrs, project_id, uploaded_by_id, upload_kind) do
    attrs = normalize_attrs(attrs)
    filename = sanitize_filename(attrs.filename)
    content_type = attrs.content_type
    size = byte_size(binary)
    blob_hash = sha256(binary)
    extension = extension_for(content_type)
    blob_key = blob_key(project_id, blob_hash, extension)
    asset_key = asset_key(project_id, filename)

    asset_attrs = %{
      filename: filename,
      content_type: content_type,
      size: size,
      key: asset_key,
      url: Storage.get_url(asset_key),
      metadata: attrs.metadata,
      blob_hash: blob_hash
    }

    with :ok <- validate_user(uploaded_by_id),
         :ok <- validate_upload_changeset(asset_attrs, project_id, uploaded_by_id, upload_kind) do
      {:ok,
       %{
         asset_attrs: asset_attrs,
         attrs: attrs,
         binary: binary,
         blob_hash: blob_hash,
         blob_key: blob_key,
         content_type: content_type,
         project_id: project_id,
         size: size,
         uploaded_by_id: uploaded_by_id,
         upload_kind: upload_kind
       }}
    end
  end

  defp upload_prepared_asset_under_lock(upload, tracker) do
    with :ok <- require_workspace_lock(upload.project_id) do
      StorageKeyLock.with_project_blob_lock(upload.blob_key, fn ->
        upload_prepared_asset_with_blob_lock(upload, tracker)
      end)
    end
  end

  defp upload_prepared_asset_with_blob_lock(upload, tracker) do
    with :ok <- check_storage_capacity(upload.project_id, upload.size),
         {:ok, blob_created?} <-
           ensure_uploaded_blob(
             tracker,
             upload.blob_key,
             upload.binary,
             upload.blob_hash,
             upload.size,
             upload.content_type
           ) do
      upload_and_insert_asset(
        tracker,
        upload.asset_attrs,
        upload.project_id,
        upload.uploaded_by_id,
        upload.upload_kind,
        upload.binary,
        upload.blob_key,
        blob_created?
      )
    end
  end

  defp run_owned_asset_tracker(tracker, fun) do
    finalize_owned_tracker(fun.(), tracker, true)
  rescue
    error ->
      cleanup_owned_tracker!(tracker, true)
      reraise error, __STACKTRACE__
  catch
    kind, reason ->
      cleanup_owned_tracker!(tracker, true)
      :erlang.raise(kind, reason, __STACKTRACE__)
  end

  defp ensure_uploaded_blob(tracker, blob_key, binary, blob_hash, size, content_type) do
    :ok = AssetStorageCompensation.track(tracker, blob_key)

    writer = fn ->
      case Storage.put_if_absent(blob_key, binary, content_type) do
        {:ok, _url, created?} when is_boolean(created?) -> {:ok, created?}
        {:error, reason} -> {:error, reason}
      end
    end

    ensure_written_blob(
      %{
        tracker: tracker,
        storage_key: blob_key,
        hash: blob_hash,
        size: size,
        content_type: content_type,
        writer: writer,
        verify_created?: false
      },
      2
    )
  end

  defp upload_and_insert_asset(
         tracker,
         asset_attrs,
         project_id,
         uploaded_by_id,
         upload_kind,
         binary,
         blob_key,
         blob_created?
       ) do
    upload = %{
      tracker: tracker,
      asset_attrs: asset_attrs,
      project_id: project_id,
      uploaded_by_id: uploaded_by_id,
      upload_kind: upload_kind,
      binary: binary,
      blob_key: blob_key,
      blob_created?: blob_created?
    }

    StorageKeyLock.with_storage_key_lock(asset_attrs.key, fn ->
      :ok = AssetStorageCompensation.track(tracker, asset_attrs.key)

      asset_attrs.key
      |> Storage.put_if_absent(binary, asset_attrs.content_type)
      |> handle_uploaded_asset_put(upload)
    end)
  end

  defp handle_uploaded_asset_put({:ok, url, true}, upload) do
    upload.asset_attrs
    |> Map.put(:url, url)
    |> insert_asset(upload.project_id, upload.uploaded_by_id, upload.upload_kind)
    |> retain_inserted_asset_storage(upload)
  end

  defp handle_uploaded_asset_put({:ok, _url, false}, upload) do
    :ok = AssetStorageCompensation.untrack(upload.tracker, upload.asset_attrs.key)
    {:error, :asset_storage_key_collision}
  end

  defp handle_uploaded_asset_put({:error, reason}, _upload), do: {:error, reason}

  defp retain_inserted_asset_storage({:ok, asset}, upload) do
    :ok = AssetStorageCompensation.retain_after_commit(upload.tracker, upload.asset_attrs.key)

    if upload.blob_created?,
      do: AssetStorageCompensation.retain_after_commit(upload.tracker, upload.blob_key)

    {:ok, asset}
  end

  defp retain_inserted_asset_storage({:error, _reason} = error, _upload), do: error

  defp insert_asset(attrs, project_id, uploaded_by_id, upload_kind) do
    now = TimeHelpers.now()

    asset = %AssetRecord{
      project_id: project_id,
      uploaded_by_id: uploaded_by_id,
      inserted_at: now,
      updated_at: now
    }

    asset
    |> asset_changeset(attrs, upload_kind)
    |> Repo.insert()
  end

  defp after_asset_created(
         {:ok, %AssetRecord{} = asset} = result,
         binary,
         attrs,
         project_id,
         uploaded_by_id,
         event_subject
       ) do
    Events.asset_uploaded(event_subject, asset, attrs)
    maybe_schedule_background_variant(binary, asset, attrs, project_id, uploaded_by_id)
    result
  end

  defp after_asset_created(result, _binary, _attrs, _project_id, _uploaded_by_id, _event_subject), do: result

  defp maybe_schedule_background_variant(binary, asset, attrs, project_id, uploaded_by_id) do
    purpose = attrs.purpose

    if purpose == :scene_background and not attrs.skip_variants do
      Task.Supervisor.start_child(Storyarn.TaskSupervisor, fn ->
        generate_background_variant(binary, asset, project_id, uploaded_by_id)
      end)
    end

    :ok
  end

  defp generate_background_variant(binary, asset, project_id, uploaded_by_id) do
    cond do
      not String.starts_with?(asset.content_type, "image/") ->
        {:ok, asset}

      not ImageProcessor.available?() ->
        {:ok, asset}

      not ImageProcessor.needs_scene_background_variant?(asset.content_type) ->
        {:ok, asset}

      true ->
        create_and_link_background_variant(binary, asset, project_id, uploaded_by_id)
    end
  end

  defp create_and_link_background_variant(binary, original, project_id, uploaded_by_id) do
    result =
      with {:ok, webp} <- ImageProcessor.to_webp(binary),
           {:ok, upload} <- prepare_background_variant(webp, original, project_id, uploaded_by_id) do
        run_background_variant_upload(upload, original)
      end

    handle_background_variant_result(result, original.id, uploaded_by_id)
  end

  defp prepare_background_variant(webp, original, project_id, uploaded_by_id) do
    prepare_uploaded_asset(
      webp,
      %{
        filename: Path.rootname(original.filename) <> ".webp",
        content_type: "image/webp",
        metadata: %{
          "is_variant" => true,
          "original_asset_id" => original.id
        },
        skip_variants: true
      },
      project_id,
      uploaded_by_id,
      :generic
    )
  end

  defp run_background_variant_upload(upload, original) do
    tracker = AssetStorageCompensation.new()

    run_owned_asset_tracker(tracker, fn ->
      with_project_storage_lock(upload.project_id, fn ->
        upload_and_link_background_variant_under_lock(upload, original, tracker)
      end)
    end)
  end

  defp upload_and_link_background_variant_under_lock(upload, original, tracker) do
    with {:ok, variant} <- upload_prepared_asset_under_lock(upload, tracker),
         {:ok, updated_original} <-
           link_background_variant_under_lock(original.id, variant.id, upload.project_id) do
      {:ok, {variant, updated_original, upload.attrs}}
    end
  end

  defp handle_background_variant_result(
         {:ok, {%AssetRecord{} = variant, %AssetRecord{} = updated_original, attrs}},
         _original_id,
         uploaded_by_id
       ) do
    Events.asset_uploaded(event_subject(uploaded_by_id), variant, attrs)
    {:ok, updated_original}
  end

  defp handle_background_variant_result(error, original_id, _uploaded_by_id) do
    Logger.warning("Sheet background variant generation failed for asset #{original_id}: #{inspect(error)}")
    error
  end

  defp link_background_variant_under_lock(original_id, variant_id, project_id) do
    asset_ids = Enum.sort([original_id, variant_id])

    assets =
      Repo.all(
        from(asset in AssetRecord,
          where:
            asset.id in ^asset_ids and asset.project_id == ^project_id and
              is_nil(asset.deleted_at),
          order_by: [asc: asset.id],
          lock: "FOR UPDATE"
        )
      )

    with %AssetRecord{} = original <- Enum.find(assets, &(&1.id == original_id)),
         %AssetRecord{} = variant <- Enum.find(assets, &(&1.id == variant_id)) do
      metadata =
        Map.merge(original.metadata || %{}, %{
          "web_url" => variant.url,
          "web_asset_id" => variant.id
        })

      original
      |> AssetRecord.update_metadata_changeset(metadata)
      |> Repo.update()
    else
      nil -> {:error, :asset_variant_link_target_not_found}
    end
  end

  defp create_version_asset_under_lock(project_id, uploaded_by_id, blob_hash, source_key, metadata, opts) do
    with :ok <- check_storage_capacity(project_id, metadata["size"]),
         {:ok, project} <- active_project(project_id) do
      destination_blob_key = blob_key(project_id, blob_hash, extension_for(metadata["content_type"]))

      StorageKeyLock.with_storage_key_locks(
        [source_key, destination_blob_key],
        fn ->
          create_version_asset_with_blob_locks(
            project,
            uploaded_by_id,
            blob_hash,
            source_key,
            destination_blob_key,
            metadata,
            opts
          )
        end
      )
    end
  end

  defp create_version_asset_with_blob_locks(
         project,
         uploaded_by_id,
         blob_hash,
         source_key,
         destination_blob_key,
         metadata,
         opts
       ) do
    with {:ok, blob_created?} <-
           ensure_materialization_blob(
             opts,
             source_key,
             destination_blob_key,
             blob_hash,
             metadata["size"],
             metadata["content_type"]
           ) do
      create_materialized_asset(
        project,
        uploaded_by_id,
        blob_hash,
        destination_blob_key,
        metadata,
        blob_created?,
        opts
      )
    end
  end

  defp ensure_materialization_blob(opts, source_key, destination_blob_key, blob_hash, size, content_type) do
    with :ok <- verify_storage_object(source_key, blob_hash, size, content_type) do
      ensure_verified_materialization_blob(
        opts,
        source_key,
        destination_blob_key,
        blob_hash,
        size,
        content_type
      )
    end
  end

  defp ensure_verified_materialization_blob(_opts, storage_key, storage_key, _blob_hash, _size, _content_type),
    do: {:ok, false}

  defp ensure_verified_materialization_blob(opts, source_key, destination_blob_key, blob_hash, size, content_type) do
    tracker = Keyword.fetch!(opts, :asset_copy_tracker)
    :ok = AssetStorageCompensation.track(tracker, destination_blob_key)

    source_key
    |> Storage.copy_if_absent(destination_blob_key)
    |> normalize_conditional_copy_result(tracker, destination_blob_key)
    |> handle_materialization_blob_copy(
      tracker,
      source_key,
      destination_blob_key,
      blob_hash,
      size,
      content_type
    )
  end

  defp handle_materialization_blob_copy(
         {:ok, created?},
         tracker,
         source_key,
         destination_blob_key,
         blob_hash,
         size,
         content_type
       ) do
    ensure_written_blob_after_result(
      %{
        tracker: tracker,
        storage_key: destination_blob_key,
        hash: blob_hash,
        size: size,
        content_type: content_type,
        writer: fn ->
          source_key
          |> Storage.copy_if_absent(destination_blob_key)
          |> normalize_conditional_copy_result(tracker, destination_blob_key)
        end,
        verify_created?: true
      },
      created?,
      2
    )
  end

  defp handle_materialization_blob_copy(
         {:error, _reason} = error,
         _tracker,
         _source_key,
         _destination_blob_key,
         _blob_hash,
         _size,
         _content_type
       ), do: error

  defp create_materialized_asset(project, uploaded_by_id, blob_hash, source_blob_key, metadata, blob_created?, opts) do
    filename = metadata["filename"]
    destination_key = asset_key(project.id, filename)
    now = TimeHelpers.now()

    attrs = %{
      filename: filename,
      content_type: metadata["content_type"],
      size: metadata["size"],
      key: destination_key,
      url: Storage.get_url(destination_key),
      metadata:
        Map.drop(metadata, [
          "filename",
          "content_type",
          "size",
          "key",
          "url",
          "project_id",
          "blob_key"
        ]),
      blob_hash: blob_hash
    }

    changeset =
      AssetRecord.snapshot_restore_changeset(
        %AssetRecord{
          project_id: project.id,
          uploaded_by_id: uploaded_by_id,
          inserted_at: now,
          updated_at: now
        },
        attrs
      )

    if changeset.valid? do
      copy_materialized_asset(
        changeset,
        source_blob_key,
        destination_key,
        blob_created?,
        opts
      )
    else
      {:error, changeset}
    end
  end

  defp copy_materialized_asset(changeset, source_blob_key, destination_key, blob_created?, opts) do
    tracker = Keyword.fetch!(opts, :asset_copy_tracker)

    copy = %{
      changeset: changeset,
      tracker: tracker,
      source_blob_key: source_blob_key,
      destination_key: destination_key,
      blob_created?: blob_created?
    }

    StorageKeyLock.with_storage_key_lock(destination_key, fn ->
      :ok = AssetStorageCompensation.track(tracker, destination_key)

      source_blob_key
      |> Storage.copy_if_absent(destination_key)
      |> handle_materialized_asset_copy(copy)
    end)
  end

  defp handle_materialized_asset_copy({:ok, true}, copy) do
    copy.changeset
    |> Repo.insert()
    |> retain_materialized_asset_storage(copy)
  end

  defp handle_materialized_asset_copy({:ok, false}, copy) do
    :ok = AssetStorageCompensation.untrack(copy.tracker, copy.destination_key)
    {:error, :asset_storage_key_collision}
  end

  defp handle_materialized_asset_copy(
         {:error,
          {:conditional_copy_cleanup_required, destination_created?, pending_cleanup_key, _cleanup_reason} = reason},
         copy
       )
       when is_boolean(destination_created?) and is_binary(pending_cleanup_key) do
    track_conditional_copy_cleanup(
      copy.tracker,
      copy.destination_key,
      destination_created?,
      pending_cleanup_key
    )

    {:error, reason}
  end

  defp handle_materialized_asset_copy({:error, reason}, _copy), do: {:error, reason}

  defp retain_materialized_asset_storage({:ok, asset}, copy) do
    :ok = AssetStorageCompensation.retain_after_commit(copy.tracker, copy.destination_key)

    if copy.blob_created?,
      do: AssetStorageCompensation.retain_after_commit(copy.tracker, copy.source_blob_key)

    {:ok, asset}
  end

  defp retain_materialized_asset_storage({:error, _reason} = error, _copy), do: error

  defp validate_version_request(blob_hash, source_key, metadata) do
    content_type = metadata["content_type"]

    valid? =
      Regex.match?(@sha256_regex, blob_hash) and
        Storage.canonical_key?(source_key) and
        valid_filename?(metadata["filename"]) and
        valid_snapshot_content_type?(content_type, metadata) and
        valid_snapshot_size?(metadata["size"])

    if valid?, do: :ok, else: {:error, :invalid_asset_materialization_request}
  end

  defp validate_upload_changeset(attrs, project_id, uploaded_by_id, upload_kind) do
    asset = %AssetRecord{project_id: project_id, uploaded_by_id: uploaded_by_id}
    changeset = asset_changeset(asset, attrs, upload_kind)

    if changeset.valid?, do: :ok, else: {:error, changeset}
  end

  defp asset_changeset(asset, attrs, :generic), do: AssetRecord.create_changeset(asset, attrs)

  defp asset_changeset(asset, attrs, :sanitized_svg), do: AssetRecord.create_sanitized_svg_changeset(asset, attrs)

  defp check_storage_capacity(project_id, requested_bytes) when is_integer(requested_bytes) and requested_bytes >= 0 do
    with {:ok, workspace_id} <- project_workspace_id(project_id) do
      used = workspace_storage_bytes(workspace_id)
      reserved = workspace_reservation_bytes(workspace_id) + workspace_import_reservation_bytes(workspace_id)
      limit = Platform.entitlement_limit(workspace_id, :storage_bytes_per_workspace)
      available = if is_integer(limit), do: max(limit - used, 0), else: 0

      if requested_bytes <= available do
        :ok
      else
        {:error, :limit_reached,
         %{
           resource: :storage_bytes_per_workspace,
           used: used,
           reserved: reserved,
           required: requested_bytes,
           available: available,
           limit: limit
         }}
      end
    end
  end

  defp workspace_storage_bytes(workspace_id) do
    workspace_asset_bytes(workspace_id) +
      workspace_snapshot_bytes(workspace_id) +
      workspace_reservation_bytes(workspace_id) +
      workspace_import_reservation_bytes(workspace_id)
  end

  defp workspace_asset_bytes(workspace_id) do
    Repo.one!(
      from(asset in AssetRecord,
        join: project in ProjectRecord,
        on: asset.project_id == project.id,
        where: project.workspace_id == ^workspace_id,
        select: type(coalesce(sum(asset.size), 0), :integer)
      )
    )
  end

  defp workspace_snapshot_bytes(workspace_id) do
    Repo.one!(
      from(snapshot in ProjectSnapshotRecord,
        join: project in ProjectRecord,
        on: snapshot.project_id == project.id,
        where:
          project.workspace_id == ^workspace_id and
            snapshot.lifecycle_state in ["ready", "deleting"] and
            snapshot.mode == "full" and
            snapshot.accounting_version == @accounting_version and
            not is_nil(snapshot.accounted_size_bytes),
        select: type(coalesce(sum(snapshot.accounted_size_bytes), 0), :integer)
      )
    )
  end

  defp workspace_reservation_bytes(workspace_id) do
    Repo.one!(
      from(reservation in StorageReservationRecord,
        where:
          reservation.workspace_id_snapshot == ^workspace_id and
            reservation.status == "active",
        select: type(coalesce(sum(reservation.reserved_bytes), 0), :integer)
      )
    )
  end

  defp workspace_import_reservation_bytes(workspace_id) do
    Repo.one!(
      from(snapshot_import in WorkspaceSnapshotImportRecord,
        where:
          snapshot_import.workspace_id == ^workspace_id and
            snapshot_import.status in ^@active_workspace_import_statuses,
        select: type(coalesce(sum(snapshot_import.reserved_bytes), 0), :integer)
      )
    )
  end

  defp verify_storage_object(storage_key, expected_hash, expected_size, expected_content_type) do
    case inspect_storage_object(storage_key, expected_hash, expected_size, expected_content_type) do
      {:ok, _stat} -> :ok
      {:error, {:verified_invalid, _stat, reason}} -> {:error, reason}
      {:error, _reason} = error -> error
    end
  end

  defp inspect_storage_object(storage_key, expected_hash, expected_size, expected_content_type) do
    with {:ok, stat} <- Storage.stat(storage_key) do
      storage_key
      |> verify_storage_object_from_stat(stat, expected_hash, expected_size, expected_content_type)
      |> classify_storage_verification(stat)
    end
  end

  defp classify_storage_verification(:ok, stat), do: {:ok, stat}

  defp classify_storage_verification({:error, reason} = error, stat) do
    if verified_corruption?(reason),
      do: {:error, {:verified_invalid, stat, reason}},
      else: error
  end

  defp verify_storage_object_from_stat(storage_key, stat, expected_hash, expected_size, expected_content_type) do
    with :ok <- verify_stored_size(stat, expected_size),
         :ok <- verify_stored_content_type(stat, expected_content_type),
         {:ok, actual_hash} <- stored_hash(storage_key, stat),
         true <- actual_hash == expected_hash do
      :ok
    else
      false -> {:error, :blob_hash_mismatch}
      {:error, _reason} = error -> error
    end
  end

  defp ensure_written_blob(write, repair_attempts) do
    case write.writer.() do
      {:ok, true} when not write.verify_created? ->
        :ok = AssetStorageCompensation.track(write.tracker, write.storage_key)
        {:ok, true}

      {:ok, created?} ->
        ensure_written_blob_after_result(write, created?, repair_attempts)

      {:error, _reason} = error ->
        error
    end
  end

  defp ensure_written_blob_after_result(write, created?, repair_attempts) do
    if created?,
      do: AssetStorageCompensation.track(write.tracker, write.storage_key)

    case inspect_storage_object(write.storage_key, write.hash, write.size, write.content_type) do
      {:ok, _stat} ->
        if not created?, do: AssetStorageCompensation.untrack(write.tracker, write.storage_key)
        {:ok, created?}

      {:error, {:verified_invalid, stat, reason}} ->
        repair_invalid_written_blob(write, created?, repair_attempts, stat, reason)

      {:error, reason} ->
        if not created?, do: AssetStorageCompensation.untrack(write.tracker, write.storage_key)
        {:error, reason}
    end
  end

  defp repair_invalid_written_blob(write, created?, repair_attempts, stat, reason) do
    case delete_if_unchanged(write.storage_key, stat) do
      :ok when repair_attempts > 0 ->
        ensure_written_blob(write, repair_attempts - 1)

      :ok ->
        :ok = AssetStorageCompensation.untrack(write.tracker, write.storage_key)
        {:error, reason}

      {:error, :object_changed} when repair_attempts > 0 ->
        ensure_written_blob(write, repair_attempts - 1)

      {:error, :object_changed} ->
        track_force_delete_if_preexisting(write, created?)
        {:error, :asset_blob_replacement_pending}

      {:error, delete_reason} ->
        track_force_delete_if_preexisting(write, created?)
        {:error, delete_reason}
    end
  end

  defp track_force_delete_if_preexisting(_write, true), do: :ok

  defp track_force_delete_if_preexisting(write, false),
    do: AssetStorageCompensation.track_force_delete(write.tracker, write.storage_key)

  defp delete_if_unchanged(storage_key, stat) do
    with {:ok, identity} <- storage_object_identity(storage_key, stat) do
      Storage.delete_if_matches(storage_key, identity)
    end
  end

  defp storage_object_identity(_storage_key, %{etag: etag}) when is_binary(etag) and etag != "", do: {:ok, etag}

  defp storage_object_identity(storage_key, %{size: size} = stat) when is_integer(size) and size >= 0,
    do: stored_hash(storage_key, stat)

  defp storage_object_identity(_storage_key, _stat), do: {:error, :invalid_asset_blob_identity}

  defp stored_hash(storage_key, %{size: size} = stat) when is_integer(size) and size >= 0 do
    with {:ok, chunks} <- Storage.stream(storage_key, 0, size, stream_opts(stat)) do
      StorageHash.sha256_chunks(chunks)
    end
  end

  defp stored_hash(_storage_key, _stat), do: {:error, :invalid_asset_blob_size}

  defp verified_corruption?(:blob_hash_mismatch), do: true
  defp verified_corruption?({:asset_blob_size_mismatch, _expected, _actual}), do: true
  defp verified_corruption?({:asset_blob_content_type_mismatch, _expected, _actual}), do: true
  defp verified_corruption?(_reason), do: false

  defp normalize_conditional_copy_result({:ok, created?}, _tracker, _destination_key) when is_boolean(created?),
    do: {:ok, created?}

  defp normalize_conditional_copy_result(
         {:error,
          {:conditional_copy_cleanup_required, destination_created?, pending_cleanup_key, _cleanup_reason} = reason},
         tracker,
         destination_key
       )
       when is_boolean(destination_created?) and is_binary(pending_cleanup_key) do
    track_conditional_copy_cleanup(
      tracker,
      destination_key,
      destination_created?,
      pending_cleanup_key
    )

    {:error, reason}
  end

  defp normalize_conditional_copy_result({:error, reason}, _tracker, _destination_key), do: {:error, reason}

  defp track_conditional_copy_cleanup(tracker, destination_key, destination_created?, pending_cleanup_key) do
    cond do
      destination_created? and
          match?({:ok, _project_id, _hash}, StorageKeyLock.project_blob_identity(destination_key)) ->
        AssetStorageCompensation.track(tracker, destination_key)

      not destination_created? ->
        AssetStorageCompensation.untrack(tracker, destination_key)

      true ->
        :ok
    end

    AssetStorageCompensation.track(tracker, pending_cleanup_key)
  end

  defp stream_opts(%{etag: etag}) when is_binary(etag) and etag != "", do: [etag: etag]
  defp stream_opts(_stat), do: []

  defp verify_stored_size(%{size: actual}, expected) when actual == expected, do: :ok

  defp verify_stored_size(%{size: actual}, expected), do: {:error, {:asset_blob_size_mismatch, expected, actual}}

  defp verify_stored_size(_stat, _expected), do: {:error, :invalid_asset_blob_size}

  defp verify_stored_content_type(%{content_type: actual}, expected) when is_binary(actual) and actual == expected,
    do: :ok

  defp verify_stored_content_type(%{content_type: "application/octet-stream"}, "audio/ogg"), do: :ok

  defp verify_stored_content_type(%{content_type: "video/webm"}, "audio/webm"), do: :ok

  defp verify_stored_content_type(%{content_type: actual}, expected),
    do: {:error, {:asset_blob_content_type_mismatch, expected, actual}}

  defp verify_stored_content_type(_stat, expected), do: {:error, {:asset_blob_content_type_mismatch, expected, nil}}

  defp lock_workspace(workspace_id) do
    case Repo.one(
           from(workspace in WorkspaceRecord,
             where: workspace.id == ^workspace_id,
             lock: "FOR UPDATE"
           )
         ) do
      %WorkspaceRecord{} = workspace -> {:ok, workspace}
      nil -> {:error, :workspace_not_found}
    end
  end

  defp active_project(project_id) do
    case Repo.one(
           from(project in ProjectRecord,
             where: project.id == ^project_id,
             lock: "FOR UPDATE"
           )
         ) do
      %ProjectRecord{deleted_at: nil} = project -> {:ok, project}
      %ProjectRecord{} -> {:error, :project_not_active}
      nil -> {:error, :project_not_found}
    end
  end

  defp lock_active_project(project_id, workspace_id) do
    case Repo.one(
           from(project in ProjectRecord,
             where:
               project.id == ^project_id and
                 project.workspace_id == ^workspace_id,
             lock: "FOR UPDATE"
           )
         ) do
      %ProjectRecord{deleted_at: nil} = project -> {:ok, project}
      %ProjectRecord{} -> {:error, :project_not_active}
      nil -> {:error, :project_not_found}
    end
  end

  defp project_workspace_id(project_id) do
    case Repo.one(
           from(project in ProjectRecord,
             where: project.id == ^project_id,
             select: project.workspace_id
           )
         ) do
      workspace_id when is_integer(workspace_id) and workspace_id > 0 -> {:ok, workspace_id}
      nil -> {:error, :project_not_found}
    end
  end

  defp validate_user(nil), do: :ok

  defp validate_user(user_id) when is_integer(user_id) and user_id > 0 do
    if Repo.exists?(from(user in UserRecord, where: user.id == ^user_id)),
      do: :ok,
      else: {:error, :user_not_found}
  end

  defp require_workspace_lock(project_id) do
    with {:ok, workspace_id} <- project_workspace_id(project_id) do
      if Process.get(@workspace_lock_key) == workspace_id,
        do: :ok,
        else: {:error, :asset_materialization_requires_workspace_lock}
    end
  end

  defp normalize_locked_callback({:error, _operation, reason, _changes}), do: Repo.rollback(reason)

  defp normalize_locked_callback({:error, reason, details}), do: Repo.rollback({reason, details})

  defp normalize_locked_callback({:error, reason}), do: Repo.rollback(reason)

  defp normalize_locked_callback(result), do: {:scene_asset_result, result}

  defp normalize_locked_result({:ok, {:scene_asset_result, result}}), do: result

  defp normalize_locked_result({:error, {:limit_reached, details}}), do: {:error, :limit_reached, details}

  defp normalize_locked_result({:error, reason}), do: {:error, reason}

  defp normalize_materialization_result({:error, :limit_reached, details}), do: {:error, {:limit_reached, details}}

  defp normalize_materialization_result(result), do: result

  defp copy_tracker_scope(opts) do
    if Keyword.get(opts, :pre_materialized_assets) == true do
      {:ok, Keyword.get(opts, :asset_copy_tracker), false}
    else
      asset_copy_tracker(opts, Repo.in_transaction?())
    end
  end

  defp asset_copy_tracker(opts, caller_transactional?) do
    case Keyword.get(opts, :asset_copy_tracker) do
      tracker when is_reference(tracker) ->
        {:ok, tracker, false}

      _tracker when caller_transactional? ->
        {:error, :asset_copy_tracker_required_in_transaction}

      _tracker ->
        {:ok, AssetStorageCompensation.new(), true}
    end
  end

  defp finalize_owned_tracker(result, _tracker, false), do: result

  defp finalize_owned_tracker(result, tracker, true) do
    cleanup =
      if successful_result?(result) do
        AssetStorageCompensation.cleanup_unretained(tracker)
      else
        AssetStorageCompensation.cleanup_after_rollback(tracker)
      end

    case cleanup do
      :ok -> result
      {:error, reason} -> {:error, {:asset_storage_cleanup_failed, result, reason}}
    end
  end

  defp cleanup_owned_tracker!(_tracker, false), do: :ok

  defp cleanup_owned_tracker!(tracker, true) do
    case AssetStorageCompensation.cleanup_after_rollback(tracker) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("Sheet asset cleanup failed while preserving an exception: #{inspect(reason)}")
    end
  rescue
    cleanup_error ->
      Logger.error(
        "Sheet asset cleanup raised while preserving an exception: " <>
          Exception.message(cleanup_error)
      )
  end

  defp successful_result?(result) when is_tuple(result) and tuple_size(result) > 0, do: elem(result, 0) == :ok

  defp successful_result?(_result), do: false

  defp restore_workspace_lock(nil), do: Process.delete(@workspace_lock_key)
  defp restore_workspace_lock(previous), do: Process.put(@workspace_lock_key, previous)

  defp normalize_attrs(attrs) do
    %{
      filename: attr(attrs, :filename),
      content_type: attr(attrs, :content_type),
      metadata: metadata(attrs),
      purpose: attr(attrs, :purpose),
      skip_variants: attr(attrs, :skip_variants) == true
    }
  end

  defp metadata(attrs) do
    case attr(attrs, :metadata) do
      value when is_map(value) -> value
      _value -> %{}
    end
  end

  defp attr(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))

  defp sanitize_svg(binary) do
    with true <- String.valid?(binary),
         svg = binary |> strip_utf8_bom() |> String.trim(),
         true <- svg_root?(svg),
         sanitized = HtmlSanitizer.sanitize_html(svg),
         true <- svg_root?(sanitized) do
      {:ok, sanitized}
    else
      _invalid -> {:error, :invalid_svg}
    end
  end

  defp strip_utf8_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_utf8_bom(binary), do: binary

  defp svg_root?(svg) do
    case Floki.parse_fragment(svg) do
      {:ok, nodes} -> nodes |> Floki.find("svg") |> Enum.any?()
      _invalid -> false
    end
  end

  defp valid_filename?(filename) when is_binary(filename) do
    String.valid?(filename) and String.trim(filename) != "" and
      sanitize_filename(filename) not in ["", ".", ".."]
  end

  defp valid_filename?(_filename), do: false

  defp valid_snapshot_content_type?("image/svg+xml", metadata), do: metadata["sanitized_svg"] == true
  defp valid_snapshot_content_type?(content_type, _metadata), do: content_type in @snapshot_content_types

  defp extract_image_metadata(path, content_type) when is_binary(content_type) do
    if String.starts_with?(content_type, "image/") and ImageProcessor.available?() do
      case ImageProcessor.dimensions(path) do
        {:ok, %{width: width, height: height}} -> %{"width" => width, "height" => height}
        {:error, _reason} -> %{}
      end
    else
      %{}
    end
  end

  defp extract_image_metadata(_path, _content_type), do: %{}

  defp valid_snapshot_size?(size), do: is_integer(size) and size >= 0 and size <= @max_asset_size

  defp sha256(binary), do: :sha256 |> :crypto.hash(binary) |> Base.encode16(case: :lower)

  defp asset_key(project_id, filename) do
    "projects/#{project_id}/assets/#{Ecto.UUID.generate()}/#{sanitize_filename(filename)}"
  end

  defp blob_key(project_id, hash, extension) do
    "projects/#{project_id}/blobs/#{hash}.#{extension}"
  end

  defp extension_for("image/jpeg"), do: "jpg"
  defp extension_for("image/png"), do: "png"
  defp extension_for("image/gif"), do: "gif"
  defp extension_for("image/webp"), do: "webp"
  defp extension_for("image/svg+xml"), do: "svg"
  defp extension_for("audio/mpeg"), do: "mp3"
  defp extension_for("audio/wav"), do: "wav"
  defp extension_for("audio/ogg"), do: "ogg"
  defp extension_for("audio/webm"), do: "webm"
  defp extension_for("application/pdf"), do: "pdf"
  defp extension_for("application/octet-stream"), do: "bin"

  defp extension_for(content_type) when is_binary(content_type) do
    content_type
    |> String.split("/")
    |> List.last()
    |> String.split("+")
    |> List.first()
  end

  defp extension_for(_content_type), do: "bin"

  defp sanitize_filename(filename) when is_binary(filename) do
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

  defp sanitize_filename(_filename), do: "file"

  defp project_id!(%{id: id}), do: project_id!(id)
  defp project_id!(id) when is_integer(id) and id > 0, do: id

  defp project_id!(value), do: raise(ArgumentError, "expected a Sheet project identity, got: #{inspect(value)}")

  defp user_id!(%{id: id}), do: user_id!(id)
  defp user_id!(id) when is_integer(id) and id > 0, do: id

  defp user_id!(value), do: raise(ArgumentError, "expected a Sheet user identity, got: #{inspect(value)}")

  defp optional_user_id!(nil), do: nil
  defp optional_user_id!(user), do: user_id!(user)

  defp event_subject(nil), do: :system
  defp event_subject(%{id: id}), do: event_subject(id)
  defp event_subject(id) when is_integer(id) and id > 0, do: {:user_id, id}
end
