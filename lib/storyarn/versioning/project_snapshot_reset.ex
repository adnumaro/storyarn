defmodule Storyarn.Versioning.ProjectSnapshotReset do
  @moduledoc """
  Environment- and workspace-scoped reset for pre-canonical project snapshots.

  The generated JSON plan is the durable audit and retry receipt. Execution
  accepts only the exact inventory recorded by a dry run, rejects new or
  replaced objects, checkpoints the shrinking inventory, and deletes database
  rows only after every scoped storage prefix re-lists empty.

  This one-time maintenance boundary intentionally invokes its injected storage
  adapter directly: the normal storage facade protects recoverable versioning
  objects from deletion. Safety instead comes from the pre-rollout guard, exact
  snapshot-root inventory, immutable provider identities, and a global write
  fence documented in the deployment runbook.
  """

  alias Storyarn.Assets.Storage
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning.SnapshotStorage

  @format "storyarn.project_snapshot_reset"
  @format_version 2
  @reset_receipts_migration 20_260_805_125_000
  @canonical_snapshot_rollout_migration 20_260_805_130_000
  @page_size 1_000
  @minimum_delete_checkpoint_size 100
  @max_delete_checkpoints 32
  @default_max_objects 250_000
  @max_plan_file_bytes 1_073_741_824
  @temporary_plan_write_attempts 5
  @sha256_regex ~r/\A[0-9a-f]{64}\z/
  @token_regex ~r/\A[A-Za-z0-9_-]{16}\z/
  @blob_filename_regex ~r/\A[0-9a-f]{64}\.[a-z0-9][a-z0-9-]{0,31}\z/
  @plan_keys Enum.sort(~w(
                 attempt_count authorization_digest completed_at environment format format_version
                 database_inventory_digest entity_version_row_ids inventory_digest last_error_code
                 objects prefixes prepared_at project_ids remaining_storage_keys snapshot_row_ids
                 status workspace_id
               ))

  @type plan :: map()

  @doc "Builds a read-only exact reset plan for one workspace and environment."
  @spec prepare(pos_integer(), String.t(), keyword()) :: {:ok, plan()} | {:error, term()}
  def prepare(workspace_id, expected_environment, opts \\ [])

  def prepare(workspace_id, expected_environment, opts)
      when is_integer(workspace_id) and workspace_id > 0 and is_binary(expected_environment) and is_list(opts) do
    repo = Keyword.get(opts, :repo, Repo)
    adapter = Keyword.get(opts, :storage_adapter, Storage.adapter())
    max_objects = Keyword.get(opts, :max_objects, @default_max_objects)

    result =
      with {:ok, environment} <- verify_environment(expected_environment, opts),
           :ok <- validate_max_objects(max_objects),
           :ok <- ensure_pre_rollout_reset_window(repo, opts),
           :ok <- ensure_reset_receipt_schema(repo),
           :ok <- ensure_workspace_exists(repo, workspace_id),
           {:ok, project_ids, snapshot_rows, entity_version_rows} <- load_scope(repo, workspace_id, max_objects),
           :ok <- validate_snapshot_row_identities(snapshot_rows),
           :ok <- validate_entity_version_row_identities(entity_version_rows),
           prefixes = reset_prefixes(project_ids),
           {:ok, objects} <- list_exact_inventory(adapter, prefixes, max_objects),
           :ok <- validate_objects(objects, project_ids),
           now = TimeHelpers.now(),
           plan =
             build_plan(
               environment,
               workspace_id,
               project_ids,
               snapshot_rows,
               entity_version_rows,
               prefixes,
               objects,
               now
             ),
           :ok <- validate_plan(plan) do
        {:ok, plan}
      end

    emit_prepare_failure(result, workspace_id, expected_environment)
    result
  end

  def prepare(_workspace_id, _expected_environment, _opts), do: {:error, :invalid_snapshot_reset_scope}

  @doc "Executes or resumes one previously prepared exact reset plan."
  @spec execute(plan(), String.t(), keyword()) :: {:ok, plan()} | {:error, term(), plan()}
  def execute(plan, confirmation_digest, opts \\ [])

  def execute(plan, confirmation_digest, opts) when is_map(plan) and is_binary(confirmation_digest) and is_list(opts) do
    repo = Keyword.get(opts, :repo, Repo)
    adapter = Keyword.get(opts, :storage_adapter, Storage.adapter())
    checkpoint = Keyword.get(opts, :checkpoint, fn _plan -> :ok end)

    result =
      with :ok <- validate_plan(plan),
           :ok <- verify_confirmation(plan, confirmation_digest),
           {:ok, environment} <- verify_environment(plan["environment"], opts),
           :ok <- ensure_pre_rollout_reset_window(repo, opts),
           :ok <- ensure_reset_receipt_schema(repo),
           {:ok, authorization_digest} <- authorize_execution(opts) do
        execute_authorized_plan(plan, environment, authorization_digest, repo, adapter, checkpoint)
      else
        {:error, reason} -> {:error, reason, plan}
      end

    emit_reset_result(result, plan, opts)
    result
  end

  def execute(plan, _confirmation_digest, opts) do
    result = {:error, :invalid_snapshot_reset_plan, plan}
    emit_reset_result(result, plan, opts)
    result
  end

  @doc "Reads and validates one persisted reset plan."
  @spec read_plan_file(Path.t()) :: {:ok, plan()} | {:error, term()}
  def read_plan_file(path) when is_binary(path) do
    with {:ok, bytes} <- read_owner_only_plan_file(path),
         {:ok, plan} <- Jason.decode(bytes),
         :ok <- validate_plan(plan) do
      {:ok, plan}
    end
  end

  def read_plan_file(_path), do: {:error, :invalid_snapshot_reset_plan_path}

  defp read_owner_only_plan_file(path) do
    expanded = Path.expand(path)

    case File.lstat(expanded) do
      {:ok, %File.Stat{type: :regular, mode: mode, size: size}}
      when size > 0 and size <= @max_plan_file_bytes ->
        if Bitwise.band(mode, 0o077) == 0,
          do: File.read(expanded),
          else: {:error, :unsafe_snapshot_reset_plan_file}

      {:ok, _unsafe} ->
        {:error, :unsafe_snapshot_reset_plan_file}

      {:error, reason} ->
        {:error, {:snapshot_reset_plan_read_failed, reason}}
    end
  end

  @doc "Persists a new owner-readable reset plan without overwriting evidence."
  @spec write_new_plan_file(Path.t(), plan()) :: :ok | {:error, term()}
  def write_new_plan_file(path, plan) when is_binary(path) do
    with :ok <- validate_plan(plan),
         {:ok, temporary} <- write_temporary_plan(path, plan) do
      case :file.make_link(String.to_charlist(temporary), String.to_charlist(Path.expand(path))) do
        :ok ->
          remove_temporary_plan_and_sync(temporary)

        {:error, :eexist} ->
          merge_persist_and_cleanup_errors(
            {:error, :snapshot_reset_plan_exists},
            remove_temporary_plan_and_sync(temporary)
          )

        {:error, reason} ->
          merge_persist_and_cleanup_errors(
            {:error, {:snapshot_reset_plan_persist_failed, reason}},
            remove_temporary_plan_and_sync(temporary)
          )
      end
    end
  end

  def write_new_plan_file(_path, _plan), do: {:error, :invalid_snapshot_reset_plan_path}

  @doc "Atomically checkpoints an existing reset plan."
  @spec write_plan_file(Path.t(), plan()) :: :ok | {:error, term()}
  def write_plan_file(path, plan) when is_binary(path) do
    with :ok <- validate_plan(plan),
         {:ok, temporary} <- write_temporary_plan(path, plan) do
      case File.rename(temporary, Path.expand(path)) do
        :ok ->
          sync_parent_directory(path)

        {:error, reason} ->
          merge_persist_and_cleanup_errors(
            {:error, {:snapshot_reset_plan_persist_failed, reason}},
            remove_temporary_plan_and_sync(temporary)
          )
      end
    end
  end

  def write_plan_file(_path, _plan), do: {:error, :invalid_snapshot_reset_plan_path}

  defp write_temporary_plan(path, plan) do
    expanded = Path.expand(path)
    directory = Path.dirname(expanded)
    contents = Jason.encode_to_iodata!(plan, pretty: true)

    with :ok <- ensure_owner_only_plan_directory(directory) do
      write_temporary_plan_file(
        directory,
        Path.basename(expanded),
        contents,
        @temporary_plan_write_attempts
      )
    end
  rescue
    exception -> {:error, {:snapshot_reset_plan_persist_failed, exception}}
  end

  defp write_temporary_plan_file(_directory, _basename, _contents, 0) do
    {:error, {:snapshot_reset_plan_persist_failed, :temporary_name_collision}}
  end

  defp write_temporary_plan_file(directory, basename, contents, attempts) do
    temporary = Path.join(directory, ".#{basename}.#{temporary_plan_token()}.tmp")

    case write_owner_only_temporary_plan(temporary, contents) do
      :ok ->
        {:ok, temporary}

      {:error, :eexist, :not_created} ->
        write_temporary_plan_file(directory, basename, contents, attempts - 1)

      {:error, reason, :not_created} ->
        {:error, {:snapshot_reset_plan_persist_failed, reason}}

      {:error, reason, :created} ->
        merge_persist_and_cleanup_errors(
          {:error, {:snapshot_reset_plan_persist_failed, reason}},
          remove_temporary_plan_and_sync(temporary)
        )
    end
  end

  defp write_owner_only_temporary_plan(path, contents) do
    case :file.open(String.to_charlist(path), [:write, :exclusive, :binary]) do
      {:ok, io_device} ->
        result =
          with :ok <- File.chmod(path, 0o600),
               :ok <- :file.write(io_device, contents) do
            :file.sync(io_device)
          end

        close_result = :file.close(io_device)

        case {result, close_result} do
          {:ok, :ok} ->
            :ok

          {{:error, reason}, :ok} ->
            {:error, reason, :created}

          {:ok, {:error, reason}} ->
            {:error, reason, :created}

          {{:error, reason}, {:error, close_reason}} ->
            {:error, {:file_operation_and_close_failed, reason, close_reason}, :created}
        end

      {:error, reason} ->
        {:error, reason, :not_created}
    end
  end

  defp temporary_plan_token do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp ensure_owner_only_plan_directory(directory) do
    case File.lstat(directory) do
      {:ok, %File.Stat{type: :directory, mode: mode}} ->
        if Bitwise.band(mode, 0o077) == 0,
          do: :ok,
          else: {:error, {:snapshot_reset_plan_persist_failed, :unsafe_snapshot_reset_plan_directory}}

      {:ok, _unsafe} ->
        {:error, {:snapshot_reset_plan_persist_failed, :unsafe_snapshot_reset_plan_directory}}

      {:error, reason} ->
        {:error, {:snapshot_reset_plan_persist_failed, {:snapshot_reset_plan_directory_unavailable, reason}}}
    end
  end

  defp remove_temporary_plan_and_sync(path) do
    remove_result = File.rm(path)
    sync_result = sync_parent_directory(path)

    case {remove_result, sync_result} do
      {:ok, :ok} ->
        :ok

      {{:error, reason}, :ok} ->
        {:error, {:snapshot_reset_plan_temporary_cleanup_failed, reason}}

      {:ok, {:error, reason}} ->
        {:error, reason}

      {{:error, remove_reason}, {:error, sync_reason}} ->
        {:error, {:snapshot_reset_plan_temporary_cleanup_failed, remove_reason, sync_reason}}
    end
  end

  defp merge_persist_and_cleanup_errors({:error, persist_reason}, :ok), do: {:error, persist_reason}

  defp merge_persist_and_cleanup_errors({:error, persist_reason}, {:error, cleanup_reason}) do
    {:error, {:snapshot_reset_plan_persist_and_cleanup_failed, persist_reason, cleanup_reason}}
  end

  defp sync_parent_directory(path) do
    directory = path |> Path.expand() |> Path.dirname() |> String.to_charlist()

    case :file.open(directory, [:read, :directory]) do
      {:ok, io_device} ->
        result = :file.sync(io_device)
        close_result = :file.close(io_device)

        case {result, close_result} do
          {:ok, :ok} ->
            :ok

          {{:error, reason}, :ok} ->
            {:error, {:snapshot_reset_plan_directory_sync_failed, reason}}

          {:ok, {:error, reason}} ->
            {:error, {:snapshot_reset_plan_directory_sync_failed, reason}}

          {{:error, reason}, {:error, close_reason}} ->
            {:error,
             {:snapshot_reset_plan_directory_sync_failed, {:file_operation_and_close_failed, reason, close_reason}}}
        end

      {:error, reason} ->
        {:error, {:snapshot_reset_plan_directory_sync_failed, reason}}
    end
  end

  defp execute_authorized_plan(
         %{"status" => "completed"} = plan,
         _environment,
         _authorization,
         repo,
         adapter,
         _checkpoint
       ) do
    case final_zero_state(repo, adapter, plan) do
      :complete -> validate_completed_reset_receipt(repo, plan)
      :incomplete -> {:error, :snapshot_reset_completed_state_changed, plan}
      {:error, reason} -> {:error, reason, plan}
    end
  end

  defp execute_authorized_plan(plan, environment, authorization_digest, repo, adapter, checkpoint) do
    case final_zero_state(repo, adapter, plan) do
      :complete -> recover_completed_plan(plan, environment, authorization_digest, repo, checkpoint)
      :incomplete -> execute_pending_plan(plan, environment, authorization_digest, repo, adapter, checkpoint)
      {:error, reason} -> {:error, reason, plan}
    end
  end

  defp recover_completed_plan(plan, environment, authorization_digest, repo, checkpoint) do
    running = mark_running(plan, authorization_digest)

    case checkpoint_plan(checkpoint, running) do
      :ok -> complete_execution(running, environment, repo, checkpoint)
      {:error, reason} -> fail_execution(running, {:snapshot_reset_checkpoint_failed, reason}, checkpoint)
    end
  end

  defp execute_pending_plan(plan, environment, authorization_digest, repo, adapter, checkpoint) do
    with :ok <- revalidate_database_scope(repo, plan),
         :ok <- revalidate_storage_scope(adapter, plan) do
      running = mark_running(plan, authorization_digest)
      execute_running_plan(running, environment, repo, adapter, checkpoint)
    else
      {:error, reason} -> {:error, reason, plan}
    end
  end

  defp mark_running(plan, authorization_digest) do
    plan
    |> Map.put("status", "running")
    |> Map.put("attempt_count", plan["attempt_count"] + 1)
    |> Map.put("authorization_digest", authorization_digest)
    |> Map.put("last_error_code", nil)
  end

  defp execute_running_plan(running, environment, repo, adapter, checkpoint) do
    with :ok <- checkpoint_plan(checkpoint, running),
         {:ok, storage_complete} <- delete_inventory(adapter, running, checkpoint),
         :ok <- verify_prefixes_empty(adapter, storage_complete["prefixes"]),
         :ok <- delete_snapshot_rows(repo, storage_complete) do
      complete_execution(storage_complete, environment, repo, checkpoint)
    else
      {:error, reason, failed_plan} -> {:error, reason, failed_plan}
      {:error, reason} -> fail_execution(running, reason, checkpoint)
    end
  end

  defp complete_execution(storage_complete, environment, repo, checkpoint) do
    case persist_or_validate_reset_receipt(repo, storage_complete, environment) do
      {:ok, completed_at} ->
        completed =
          storage_complete
          |> Map.put("status", "completed")
          |> Map.put("completed_at", DateTime.to_iso8601(completed_at))

        case checkpoint_plan(checkpoint, completed) do
          :ok ->
            {:ok, completed}

          {:error, reason} ->
            {:error, {:snapshot_reset_checkpoint_failed, reason}, completed}
        end

      {:error, reason} ->
        fail_execution(storage_complete, reason, checkpoint)
    end
  end

  @doc false
  def validate_plan(
        %{
          "format" => @format,
          "format_version" => @format_version,
          "environment" => environment,
          "workspace_id" => workspace_id,
          "project_ids" => project_ids,
          "snapshot_row_ids" => row_ids,
          "entity_version_row_ids" => entity_version_row_ids,
          "database_inventory_digest" => database_inventory_digest,
          "prefixes" => prefixes,
          "objects" => objects,
          "remaining_storage_keys" => remaining,
          "inventory_digest" => digest,
          "status" => status,
          "attempt_count" => attempt_count
        } = plan
      ) do
    valid? =
      with true <- Enum.sort(Map.keys(plan)) == @plan_keys,
           true <- valid_environment?(environment),
           true <- is_integer(workspace_id) and workspace_id > 0,
           true <- positive_unique_integers?(project_ids),
           true <- positive_unique_integers?(row_ids),
           true <- positive_unique_integers?(entity_version_row_ids),
           true <- valid_digest?(database_inventory_digest),
           true <- is_list(prefixes) and prefixes == reset_prefixes(project_ids),
           true <- is_list(objects) and Enum.all?(objects, &valid_plan_object?/1),
           true <- objects == Enum.sort_by(objects, & &1["key"]),
           true <- objects == Enum.uniq_by(objects, & &1["key"]),
           :ok <- validate_objects(objects, project_ids),
           true <- is_list(remaining) and Enum.all?(remaining, &is_binary/1),
           true <- remaining == Enum.uniq(remaining),
           object_keys = MapSet.new(objects, & &1["key"]),
           true <- Enum.all?(remaining, &MapSet.member?(object_keys, &1)),
           true <- is_binary(digest) and Regex.match?(@sha256_regex, digest),
           true <- Plug.Crypto.secure_compare(digest, inventory_digest(plan)),
           true <- status in ["prepared", "running", "failed", "completed"],
           true <- is_integer(attempt_count) and attempt_count >= 0,
           true <- valid_plan_state_metadata?(plan) do
        true
      else
        _invalid -> false
      end

    if valid?, do: :ok, else: {:error, :invalid_snapshot_reset_plan}
  end

  def validate_plan(_plan), do: {:error, :invalid_snapshot_reset_plan}

  defp valid_environment?(environment) when is_binary(environment) do
    byte_size(environment) in 1..128 and String.trim(environment) == environment and
      String.match?(environment, ~r/\A[A-Za-z0-9][A-Za-z0-9._-]*\z/)
  end

  defp valid_environment?(_environment), do: false

  defp valid_plan_state_metadata?(plan) do
    valid_timestamp?(plan["prepared_at"]) and valid_error_code?(plan["last_error_code"]) and
      valid_plan_status_metadata?(
        plan["status"],
        plan["attempt_count"],
        plan["authorization_digest"],
        plan["completed_at"]
      )
  end

  defp valid_plan_status_metadata?("prepared", 0, nil, nil), do: true

  defp valid_plan_status_metadata?(status, attempt_count, authorization_digest, nil)
       when status in ["running", "failed"] and attempt_count > 0, do: valid_digest?(authorization_digest)

  defp valid_plan_status_metadata?("completed", attempt_count, authorization_digest, completed_at) when attempt_count > 0,
    do: valid_digest?(authorization_digest) and valid_timestamp?(completed_at)

  defp valid_plan_status_metadata?(_status, _attempt_count, _authorization_digest, _completed_at), do: false

  defp valid_timestamp?(value) when is_binary(value), do: match?({:ok, _datetime, 0}, DateTime.from_iso8601(value))
  defp valid_timestamp?(_value), do: false

  defp valid_error_code?(nil), do: true
  defp valid_error_code?(value) when is_binary(value), do: byte_size(value) in 1..160
  defp valid_error_code?(_value), do: false

  defp valid_digest?(value), do: is_binary(value) and Regex.match?(@sha256_regex, value)

  defp verify_environment(expected_environment, opts) do
    current = Keyword.get(opts, :current_environment) || System.get_env("STORYARN_DEPLOYMENT_ENVIRONMENT")

    cond do
      not is_binary(expected_environment) or String.trim(expected_environment) == "" ->
        {:error, :snapshot_reset_environment_required}

      not is_binary(current) or String.trim(current) == "" ->
        {:error, :snapshot_reset_current_environment_unconfigured}

      current != expected_environment ->
        {:error, :snapshot_reset_environment_mismatch}

      true ->
        {:ok, current}
    end
  end

  defp authorize_execution(opts) do
    expected_digest =
      Keyword.get(opts, :expected_authorization_digest) ||
        System.get_env("STORYARN_SNAPSHOT_RESET_AUTHORIZATION_SHA256")

    supplied = Keyword.get(opts, :authorization) || System.get_env("STORYARN_SNAPSHOT_RESET_AUTHORIZATION")
    supplied_digest = if is_binary(supplied), do: sha256(supplied)

    if valid_digest?(expected_digest) and is_binary(supplied) and byte_size(supplied) >= 32 and
         Plug.Crypto.secure_compare(expected_digest, supplied_digest) do
      {:ok, supplied_digest}
    else
      {:error, :snapshot_reset_not_authorized}
    end
  end

  defp ensure_pre_rollout_reset_window(repo, opts) do
    case Keyword.get(opts, :rollout_guard) do
      guard when is_function(guard, 1) ->
        normalize_rollout_guard(guard.(repo))

      nil ->
        case repo.query("SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE version >= $1)", [
               @canonical_snapshot_rollout_migration
             ]) do
          {:ok, %{rows: [[false]]}} -> :ok
          {:ok, %{rows: [[true]]}} -> {:error, :snapshot_reset_rollout_already_applied}
          {:error, reason} -> {:error, {:snapshot_reset_database_failed, reason}}
          _invalid -> {:error, {:snapshot_reset_database_failed, :invalid_database_response}}
        end
    end
  rescue
    _exception -> {:error, :snapshot_reset_rollout_guard_failed}
  catch
    _kind, _reason -> {:error, :snapshot_reset_rollout_guard_failed}
  end

  defp normalize_rollout_guard(:ok), do: :ok
  defp normalize_rollout_guard({:error, _reason} = error), do: error
  defp normalize_rollout_guard(_invalid), do: {:error, :snapshot_reset_rollout_guard_failed}

  defp ensure_reset_receipt_schema(repo) do
    case repo.query(
           """
           SELECT
             to_regclass('public.project_snapshot_reset_receipts') IS NOT NULL AND
             EXISTS (SELECT 1 FROM schema_migrations WHERE version = $1)
           """,
           [@reset_receipts_migration]
         ) do
      {:ok, %{rows: [[true]]}} -> :ok
      {:ok, _result} -> {:error, :snapshot_reset_receipt_schema_unavailable}
      {:error, reason} -> {:error, {:snapshot_reset_database_failed, reason}}
    end
  end

  defp verify_confirmation(plan, confirmation_digest) do
    if Regex.match?(@sha256_regex, confirmation_digest) and
         Plug.Crypto.secure_compare(plan["inventory_digest"], confirmation_digest),
       do: :ok,
       else: {:error, :snapshot_reset_inventory_confirmation_mismatch}
  end

  defp validate_max_objects(max_objects) when is_integer(max_objects) and max_objects > 0, do: :ok
  defp validate_max_objects(_max_objects), do: {:error, :invalid_snapshot_reset_limit}

  defp ensure_workspace_exists(repo, workspace_id) do
    case repo.query("SELECT 1 FROM workspaces WHERE id = $1 LIMIT 1", [workspace_id]) do
      {:ok, %{num_rows: 1}} -> :ok
      {:ok, _result} -> {:error, :snapshot_reset_workspace_not_found}
      {:error, reason} -> {:error, {:snapshot_reset_database_failed, reason}}
    end
  end

  defp load_scope(repo, workspace_id, max_rows) do
    projects_query = "SELECT id FROM projects WHERE workspace_id = $1 ORDER BY id LIMIT $2"

    rows_query = """
    SELECT ps.id, ps.project_id, to_jsonb(ps)
    FROM project_snapshots ps
    JOIN projects p ON p.id = ps.project_id
    WHERE p.workspace_id = $1
    ORDER BY ps.id
    LIMIT $2
    """

    entity_versions_query = """
    SELECT ev.id, ev.project_id, ev.entity_type, ev.entity_id, ev.version_number,
           ev.storage_key, ev.snapshot_size_bytes, to_jsonb(ev)
    FROM entity_versions ev
    JOIN projects p ON p.id = ev.project_id
    WHERE p.workspace_id = $1
    ORDER BY ev.id
    LIMIT $2
    """

    query_limit = max_rows + 1

    with {:ok, %{rows: project_rows}} <- repo.query(projects_query, [workspace_id, query_limit]),
         {:ok, %{rows: snapshot_rows}} <- repo.query(rows_query, [workspace_id, query_limit]),
         {:ok, %{rows: entity_version_rows}} <- repo.query(entity_versions_query, [workspace_id, query_limit]),
         true <- Enum.all?([project_rows, snapshot_rows, entity_version_rows], &(length(&1) <= max_rows)) do
      project_ids = Enum.map(project_rows, fn [id] -> id end)

      snapshot_rows =
        Enum.map(snapshot_rows, fn [id, project_id, data] -> %{"id" => id, "project_id" => project_id, "data" => data} end)

      entity_version_rows =
        Enum.map(entity_version_rows, fn [
                                           id,
                                           project_id,
                                           entity_type,
                                           entity_id,
                                           version_number,
                                           storage_key,
                                           size,
                                           data
                                         ] ->
          %{
            "id" => id,
            "project_id" => project_id,
            "entity_type" => entity_type,
            "entity_id" => entity_id,
            "version_number" => version_number,
            "storage_key" => storage_key,
            "size" => size,
            "data" => data
          }
        end)

      {:ok, project_ids, snapshot_rows, entity_version_rows}
    else
      false -> {:error, :snapshot_reset_database_inventory_limit_exceeded}
      {:error, reason} -> {:error, {:snapshot_reset_database_failed, reason}}
    end
  end

  defp validate_snapshot_row_identities(rows) do
    if Enum.all?(rows, &valid_row_identity?/1),
      do: :ok,
      else: {:error, :unsafe_snapshot_reset_row_identity}
  end

  defp validate_entity_version_row_identities(rows) do
    if Enum.all?(rows, &valid_entity_version_row_identity?/1),
      do: :ok,
      else: {:error, :unsafe_entity_version_reset_row_identity}
  end

  defp valid_row_identity?(%{"id" => id, "project_id" => project_id, "data" => data})
       when is_integer(id) and id > 0 and is_integer(project_id) and project_id > 0 and is_map(data) do
    keys = Enum.reject([data["storage_key"], data["project_storage_key"], data["manifest_storage_key"]], &is_nil/1)

    prefix = data["object_prefix"]

    Enum.all?(keys, &valid_reset_key_for_project?(&1, project_id)) and
      (is_nil(prefix) or valid_object_set_prefix?(prefix, project_id))
  end

  defp valid_row_identity?(_row), do: false

  defp valid_entity_version_row_identity?(%{
         "id" => id,
         "project_id" => project_id,
         "entity_type" => entity_type,
         "entity_id" => entity_id,
         "version_number" => version_number,
         "storage_key" => storage_key,
         "size" => size,
         "data" => data
       })
       when is_integer(id) and id > 0 and is_integer(size) and size >= 0 and is_map(data) do
    expected_data = %{
      "entity_id" => entity_id,
      "entity_type" => entity_type,
      "id" => id,
      "project_id" => project_id,
      "snapshot_size_bytes" => size,
      "storage_key" => storage_key,
      "version_number" => version_number
    }

    Map.take(data, Map.keys(expected_data)) == expected_data and
      SnapshotStorage.entity_key?(storage_key, project_id, entity_type, entity_id, version_number)
  end

  defp valid_entity_version_row_identity?(_row), do: false

  defp reset_prefixes(project_ids) do
    project_ids
    |> Enum.map(&"projects/#{&1}/snapshots/")
    |> Enum.sort()
  end

  defp list_exact_inventory(adapter, prefixes, max_objects) do
    prefixes
    |> Enum.reduce_while({:ok, [], 0}, fn prefix, {:ok, objects, count} ->
      case list_prefix_pages(adapter, prefix, nil, objects, count, max_objects, MapSet.new()) do
        {:ok, listed, listed_count} -> {:cont, {:ok, listed, listed_count}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, reversed_objects, _count} ->
        objects = Enum.reverse(reversed_objects)
        objects = Enum.sort_by(objects, & &1["key"])

        if objects == Enum.uniq_by(objects, & &1["key"]),
          do: {:ok, objects},
          else: {:error, :duplicate_snapshot_reset_object}

      error ->
        error
    end
  end

  defp list_prefix_pages(adapter, prefix, cursor, objects, object_count, max_objects, seen_cursors) do
    with {:ok, %{objects: page, cursor: next_cursor}} <- safe_list_prefix(adapter, prefix, cursor),
         true <- is_list(page) and length(page) <= @page_size,
         {:ok, normalized} <- normalize_page(page, prefix),
         combined_count = object_count + length(normalized),
         true <- combined_count <= max_objects do
      combined = Enum.reduce(normalized, objects, &[&1 | &2])

      cond do
        is_nil(next_cursor) ->
          {:ok, combined, combined_count}

        not is_binary(next_cursor) or next_cursor == "" ->
          {:error, :invalid_snapshot_reset_cursor}

        normalized == [] ->
          {:error, :empty_snapshot_reset_page_with_cursor}

        MapSet.member?(seen_cursors, next_cursor) ->
          {:error, :repeated_snapshot_reset_cursor}

        true ->
          list_prefix_pages(
            adapter,
            prefix,
            next_cursor,
            combined,
            combined_count,
            max_objects,
            MapSet.put(seen_cursors, next_cursor)
          )
      end
    else
      false -> {:error, :snapshot_reset_inventory_limit_exceeded}
      {:error, reason} -> {:error, {:snapshot_reset_storage_list_failed, reason}}
      _invalid -> {:error, :invalid_snapshot_reset_storage_page}
    end
  end

  defp safe_list_prefix(adapter, prefix, cursor) do
    adapter.list_prefix(prefix, limit: @page_size, cursor: cursor)
  rescue
    _exception -> {:error, :storage_list_failed}
  catch
    _kind, _reason -> {:error, :storage_list_failed}
  end

  defp normalize_page(page, prefix) do
    normalized =
      Enum.map(page, fn
        %{key: key, size: size, identity: identity} ->
          %{"identity" => identity, "key" => key, "size" => size}

        %{"key" => key, "size" => size, "identity" => identity} ->
          %{"identity" => identity, "key" => key, "size" => size}

        _invalid ->
          nil
      end)

    if Enum.all?(normalized, fn
         %{"identity" => identity, "key" => key, "size" => size} ->
           is_binary(key) and String.starts_with?(key, prefix) and is_integer(size) and size >= 0 and
             valid_object_identity?(identity)

         _invalid ->
           false
       end),
       do: {:ok, normalized},
       else: {:error, :invalid_snapshot_reset_storage_page}
  end

  defp validate_objects(objects, project_ids) do
    if Enum.all?(objects, fn %{"key" => key} -> Enum.any?(project_ids, &valid_reset_key_for_project?(key, &1)) end),
      do: :ok,
      else: {:error, :unsafe_snapshot_reset_object}
  end

  defp valid_reset_key_for_project?(key, project_id) when is_binary(key) do
    legacy_prefix = "projects/#{project_id}/snapshots/project/"
    object_set_root = "projects/#{project_id}/snapshots/object-sets/v1/"
    entity_version_root = "projects/#{project_id}/snapshots/"

    cond do
      String.starts_with?(key, legacy_prefix) ->
        relative = String.replace_prefix(key, legacy_prefix, "")
        relative != "" and Storage.canonical_key?(relative) and String.ends_with?(relative, ".json.gz")

      String.starts_with?(key, object_set_root) ->
        valid_object_set_key?(String.replace_prefix(key, object_set_root, ""))

      String.starts_with?(key, entity_version_root) ->
        valid_entity_version_key?(String.replace_prefix(key, entity_version_root, ""))

      true ->
        false
    end
  end

  defp valid_reset_key_for_project?(_key, _project_id), do: false

  defp valid_object_set_prefix?(prefix, project_id) when is_binary(prefix) do
    root = "projects/#{project_id}/snapshots/object-sets/v1/ready/"
    token = String.replace_prefix(prefix, root, "")
    String.starts_with?(prefix, root) and Regex.match?(@token_regex, token)
  end

  defp valid_object_set_prefix?(_prefix, _project_id), do: false

  defp valid_object_set_key?(relative) do
    case String.split(relative, "/", parts: 3) do
      [state, token, path] when state in ["ready", "staging"] ->
        Regex.match?(@token_regex, token) and valid_object_set_relative_path?(path)

      _invalid ->
        false
    end
  end

  defp valid_object_set_relative_path?(path) when path in ["project.json", "manifest.json"], do: true

  defp valid_object_set_relative_path?("blobs/" <> filename), do: Regex.match?(@blob_filename_regex, filename)

  defp valid_object_set_relative_path?(_path), do: false

  defp valid_entity_version_key?(relative) do
    Regex.match?(~r/\A(?:sheet|flow|scene)\/[1-9][0-9]*\/[1-9][0-9]*-[0-9a-f]{16}\.json\.gz\z/, relative)
  end

  defp build_plan(environment, workspace_id, project_ids, snapshot_rows, entity_version_rows, prefixes, objects, now) do
    plan = %{
      "format" => @format,
      "format_version" => @format_version,
      "environment" => environment,
      "workspace_id" => workspace_id,
      "project_ids" => project_ids,
      "snapshot_row_ids" => Enum.map(snapshot_rows, & &1["id"]),
      "entity_version_row_ids" => Enum.map(entity_version_rows, & &1["id"]),
      "database_inventory_digest" => database_inventory_digest(snapshot_rows, entity_version_rows),
      "prefixes" => prefixes,
      "objects" => objects,
      "remaining_storage_keys" => Enum.map(objects, & &1["key"]),
      "inventory_digest" => nil,
      "status" => "prepared",
      "attempt_count" => 0,
      "authorization_digest" => nil,
      "last_error_code" => nil,
      "prepared_at" => DateTime.to_iso8601(now),
      "completed_at" => nil
    }

    Map.put(plan, "inventory_digest", inventory_digest(plan))
  end

  defp inventory_digest(plan) do
    [
      ["format", plan["format"]],
      ["format_version", plan["format_version"]],
      ["environment", plan["environment"]],
      ["workspace_id", plan["workspace_id"]],
      ["project_ids", plan["project_ids"]],
      ["snapshot_row_ids", plan["snapshot_row_ids"]],
      ["entity_version_row_ids", plan["entity_version_row_ids"]],
      ["database_inventory_digest", plan["database_inventory_digest"]],
      ["prefixes", plan["prefixes"]],
      ["objects", Enum.map(plan["objects"], &[&1["key"], &1["size"], &1["identity"]])]
    ]
    |> Jason.encode_to_iodata!()
    |> sha256()
  end

  defp sha256(value), do: :sha256 |> :crypto.hash(value) |> Base.encode16(case: :lower)

  defp positive_unique_integers?(values) when is_list(values) do
    values == Enum.uniq(values) and Enum.all?(values, &(is_integer(&1) and &1 > 0))
  end

  defp positive_unique_integers?(_values), do: false

  defp valid_plan_object?(%{"identity" => identity, "key" => key, "size" => size} = object) do
    Enum.sort(Map.keys(object)) == ["identity", "key", "size"] and is_binary(key) and is_integer(size) and size >= 0 and
      valid_object_identity?(identity)
  end

  defp valid_plan_object?(_object), do: false

  defp valid_object_identity?(identity) when is_binary(identity) do
    byte_size(identity) in 1..512 and String.valid?(identity) and String.trim(identity) == identity and
      not String.match?(identity, ~r/[\x00-\x1F\x7F]/u)
  end

  defp valid_object_identity?(_identity), do: false

  defp database_inventory_digest(snapshot_rows, entity_version_rows) do
    [canonical_term(snapshot_rows), canonical_term(entity_version_rows)]
    |> Jason.encode_to_iodata!()
    |> sha256()
  end

  defp canonical_term(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested} -> [to_string(key), canonical_term(nested)] end)
    |> Enum.sort_by(&hd/1)
  end

  defp canonical_term(value) when is_list(value), do: Enum.map(value, &canonical_term/1)
  defp canonical_term(value), do: value

  defp revalidate_database_scope(repo, plan) do
    with {:ok, project_ids, snapshot_rows, entity_version_rows} <-
           load_scope(repo, plan["workspace_id"], scope_validation_limit(plan)),
         true <- project_ids == plan["project_ids"],
         true <- Enum.map(snapshot_rows, & &1["id"]) == plan["snapshot_row_ids"],
         true <- Enum.map(entity_version_rows, & &1["id"]) == plan["entity_version_row_ids"],
         true <-
           database_inventory_digest(snapshot_rows, entity_version_rows) == plan["database_inventory_digest"] do
      :ok
    else
      false -> {:error, :snapshot_reset_database_scope_changed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp revalidate_storage_scope(adapter, plan) do
    with {:ok, current} <- list_exact_inventory(adapter, plan["prefixes"], length(plan["objects"]) + 1) do
      ensure_current_inventory_subset(current, plan["objects"])
    end
  end

  defp ensure_current_inventory_subset(current, original) do
    original_by_key = Map.new(original, &{&1["key"], {&1["size"], &1["identity"]}})

    if Enum.all?(current, fn object ->
         original_by_key[object["key"]] == {object["size"], object["identity"]}
       end),
       do: :ok,
       else: {:error, :snapshot_reset_storage_scope_changed}
  end

  defp delete_inventory(adapter, plan, checkpoint) do
    batch_size = delete_checkpoint_size(length(plan["remaining_storage_keys"]))
    objects_by_key = Map.new(plan["objects"], &{&1["key"], &1})

    plan["remaining_storage_keys"]
    |> Enum.chunk_every(batch_size)
    |> Enum.reduce_while(
      {:ok, plan},
      &delete_inventory_batch(&1, &2, objects_by_key, adapter, checkpoint)
    )
  end

  defp delete_checkpoint_size(remaining_count) do
    linear_checkpoint_size = div(remaining_count + @max_delete_checkpoints - 1, @max_delete_checkpoints)
    max(@minimum_delete_checkpoint_size, linear_checkpoint_size)
  end

  defp delete_inventory_batch(batch, {:ok, current_plan}, objects_by_key, adapter, checkpoint) do
    {deleted_count, failure} =
      Enum.reduce_while(batch, {0, nil}, fn key, state ->
        delete_inventory_object(key, state, objects_by_key, adapter)
      end)

    updated =
      Map.put(
        current_plan,
        "remaining_storage_keys",
        Enum.drop(current_plan["remaining_storage_keys"], deleted_count)
      )

    continue_after_delete_batch(failure, updated, checkpoint)
  end

  defp delete_inventory_object(key, {count, _failure}, objects_by_key, adapter) do
    with {:ok, object} <- Map.fetch(objects_by_key, key),
         :ok <- safe_conditional_delete(adapter, object) do
      {:cont, {count + 1, nil}}
    else
      :error -> {:halt, {count, :invalid_snapshot_reset_plan}}
      {:error, reason} -> {:halt, {count, reason}}
    end
  end

  defp continue_after_delete_batch(nil, updated, checkpoint) do
    case checkpoint_plan(checkpoint, updated) do
      :ok ->
        {:cont, {:ok, updated}}

      {:error, _reason} ->
        {:halt, {:error, :snapshot_reset_checkpoint_failed, mark_failed(updated, "checkpoint_failed")}}
    end
  end

  defp continue_after_delete_batch(failure, updated, checkpoint) do
    failed_plan = mark_failed(updated, reset_delete_error_code(failure))

    case checkpoint_plan(checkpoint, failed_plan) do
      :ok ->
        {:halt, {:error, reset_delete_error(failure), failed_plan}}

      {:error, _reason} ->
        {:halt, {:error, :snapshot_reset_checkpoint_failed, mark_failed(updated, "checkpoint_failed")}}
    end
  end

  defp reset_delete_error(:object_changed), do: :snapshot_reset_storage_scope_changed
  defp reset_delete_error(_reason), do: :snapshot_reset_storage_delete_failed

  defp reset_delete_error_code(:object_changed), do: "storage_scope_changed"
  defp reset_delete_error_code(_reason), do: "storage_delete_failed"

  defp verify_prefixes_empty(adapter, prefixes) do
    case list_exact_inventory(adapter, prefixes, 1) do
      {:ok, []} -> :ok
      {:ok, _objects} -> {:error, :snapshot_reset_final_inventory_not_empty}
      {:error, reason} -> {:error, reason}
    end
  end

  defp final_zero_state(repo, adapter, plan) do
    case verify_prefixes_empty(adapter, plan["prefixes"]) do
      :ok -> final_database_zero_state(repo, plan)
      {:error, :snapshot_reset_final_inventory_not_empty} -> :incomplete
      {:error, :snapshot_reset_inventory_limit_exceeded} -> :incomplete
      {:error, reason} -> {:error, reason}
    end
  end

  defp final_database_zero_state(repo, plan) do
    case verify_database_scope_empty(repo, plan) do
      :ok -> :complete
      {:error, :snapshot_reset_final_database_not_empty} -> :incomplete
      {:error, reason} -> {:error, reason}
    end
  end

  defp delete_snapshot_rows(repo, plan) do
    case repo.transaction(fn -> delete_snapshot_rows_transaction(repo, plan) end) do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, {:snapshot_reset_database_failed, reason}}
    end
  end

  defp delete_snapshot_rows_transaction(repo, plan) do
    snapshot_row_ids = plan["snapshot_row_ids"]
    entity_version_row_ids = plan["entity_version_row_ids"]

    with :ok <- lock_reset_workspace(repo, plan["workspace_id"]),
         :ok <- revalidate_database_scope(repo, plan),
         :ok <- clear_legacy_restoration_locks(repo, plan["workspace_id"]),
         {:ok, %{rows: deleted_entity_versions}} <-
           repo.query(
             """
             DELETE FROM entity_versions ev
             USING projects p
             WHERE ev.project_id = p.id AND p.workspace_id = $1 AND ev.id = ANY($2::bigint[])
             RETURNING ev.id
             """,
             [plan["workspace_id"], entity_version_row_ids]
           ),
         true <-
           exact_deleted_ids?(deleted_entity_versions, entity_version_row_ids),
         {:ok, %{rows: deleted_snapshots}} <-
           repo.query(
             """
             DELETE FROM project_snapshots ps
             USING projects p
             WHERE ps.project_id = p.id AND p.workspace_id = $1 AND ps.id = ANY($2::bigint[])
             RETURNING ps.id
             """,
             [plan["workspace_id"], snapshot_row_ids]
           ),
         true <- exact_deleted_ids?(deleted_snapshots, snapshot_row_ids),
         :ok <- verify_database_scope_empty(repo, plan) do
      :ok
    else
      false -> repo.rollback(:snapshot_reset_database_scope_changed)
      {:error, reason} -> repo.rollback(reason)
    end
  end

  defp exact_deleted_ids?(deleted_rows, expected_ids) do
    Enum.sort(Enum.map(deleted_rows, fn [id] -> id end)) == Enum.sort(expected_ids)
  end

  defp lock_reset_workspace(repo, workspace_id) do
    case repo.query("SELECT id FROM workspaces WHERE id = $1 FOR UPDATE", [workspace_id]) do
      {:ok, %{rows: [[^workspace_id]]}} -> :ok
      {:ok, _result} -> {:error, :snapshot_reset_workspace_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp clear_legacy_restoration_locks(repo, workspace_id) do
    case repo.query(
           """
           SELECT EXISTS (
             SELECT 1 FROM information_schema.columns
             WHERE table_name = 'projects' AND column_name = 'restoration_snapshot_id'
           )
           """,
           []
         ) do
      {:ok, %{rows: [[false]]}} ->
        :ok

      {:ok, %{rows: [[true]]}} ->
        case repo.query(
               """
               UPDATE projects
               SET restoration_in_progress = FALSE,
                   restoration_started_by_id = NULL,
                   restoration_started_at = NULL,
                   restoration_token = NULL,
                   restoration_claimed_by_job_id = NULL,
                   restoration_snapshot_id = NULL
               WHERE workspace_id = $1 AND restoration_snapshot_id IS NOT NULL
               """,
               [workspace_id]
             ) do
          {:ok, _result} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}

      _invalid ->
        {:error, :invalid_database_response}
    end
  end

  defp verify_database_scope_empty(repo, plan) do
    case load_scope(repo, plan["workspace_id"], scope_validation_limit(plan)) do
      {:ok, project_ids, [], []} ->
        if project_ids == plan["project_ids"],
          do: :ok,
          else: {:error, :snapshot_reset_database_scope_changed}

      {:ok, _project_ids, _snapshot_rows, _entity_version_rows} ->
        {:error, :snapshot_reset_final_database_not_empty}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp scope_validation_limit(plan) do
    [plan["project_ids"], plan["snapshot_row_ids"], plan["entity_version_row_ids"]]
    |> Enum.map(&length/1)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  defp persist_or_validate_reset_receipt(repo, plan, environment) do
    completed_at = TimeHelpers.now()
    identity = reset_receipt_identity(plan, environment)
    params = [plan["workspace_id"] | identity] ++ [plan["attempt_count"], completed_at]

    case repo.query(
           """
           INSERT INTO project_snapshot_reset_receipts (
             workspace_id, project_ids, environment, inventory_digest,
             database_inventory_digest, authorization_digest, object_count,
             object_bytes, snapshot_row_count, entity_version_row_count,
             attempt_count, completed_at
           )
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
           ON CONFLICT (workspace_id) DO NOTHING
           RETURNING completed_at
           """,
           params
         ) do
      {:ok, %{rows: [[persisted_at]]}} -> normalize_receipt_completed_at(persisted_at)
      {:ok, %{rows: []}} -> fetch_matching_reset_receipt(repo, plan, environment)
      {:error, reason} -> {:error, {:snapshot_reset_receipt_failed, reason}}
      _invalid -> {:error, :snapshot_reset_receipt_failed}
    end
  end

  defp validate_completed_reset_receipt(repo, plan) do
    case fetch_matching_reset_receipt(repo, plan, plan["environment"]) do
      {:ok, completed_at} ->
        if DateTime.to_iso8601(completed_at) == plan["completed_at"],
          do: {:ok, plan},
          else: {:error, :snapshot_reset_receipt_mismatch, plan}

      {:error, reason} ->
        {:error, reason, plan}
    end
  end

  defp fetch_matching_reset_receipt(repo, plan, environment) do
    case repo.query(
           """
           SELECT project_ids, environment, inventory_digest,
                  database_inventory_digest, authorization_digest, object_count,
                  object_bytes, snapshot_row_count, entity_version_row_count,
                  attempt_count, completed_at
           FROM project_snapshot_reset_receipts
           WHERE workspace_id = $1
           """,
           [plan["workspace_id"]]
         ) do
      {:ok, %{rows: [row]}} -> validate_reset_receipt_row(row, plan, environment)
      {:ok, %{rows: []}} -> {:error, :snapshot_reset_receipt_missing}
      {:error, reason} -> {:error, {:snapshot_reset_receipt_failed, reason}}
      _invalid -> {:error, :snapshot_reset_receipt_failed}
    end
  end

  defp validate_reset_receipt_row(row, plan, environment) do
    {identity, [receipt_attempt_count, completed_at]} = Enum.split(row, -2)

    if identity == reset_receipt_identity(plan, environment) and receipt_attempt_count > 0 do
      normalize_receipt_completed_at(completed_at)
    else
      {:error, :snapshot_reset_receipt_mismatch}
    end
  end

  defp normalize_receipt_completed_at(%DateTime{} = completed_at), do: {:ok, completed_at}

  defp normalize_receipt_completed_at(%NaiveDateTime{} = completed_at) do
    {:ok, DateTime.from_naive!(completed_at, "Etc/UTC")}
  end

  defp normalize_receipt_completed_at(_invalid), do: {:error, :snapshot_reset_receipt_mismatch}

  defp reset_receipt_identity(plan, environment) do
    [
      plan["project_ids"],
      environment,
      plan["inventory_digest"],
      plan["database_inventory_digest"],
      plan["authorization_digest"],
      length(plan["objects"]),
      Enum.reduce(plan["objects"], 0, &(&1["size"] + &2)),
      length(plan["snapshot_row_ids"]),
      length(plan["entity_version_row_ids"])
    ]
  end

  defp fail_execution(plan, reason, checkpoint) do
    failed = mark_failed(plan, reset_error_code(reason))
    _checkpoint_result = checkpoint_plan(checkpoint, failed)
    {:error, reason, failed}
  end

  defp checkpoint_plan(checkpoint, plan) do
    case checkpoint.(plan) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :invalid_checkpoint_response}
    end
  rescue
    _exception -> {:error, :checkpoint_failed}
  catch
    _kind, _reason -> {:error, :checkpoint_failed}
  end

  defp safe_conditional_delete(adapter, %{"key" => key, "identity" => identity}) do
    case adapter.delete_if_matches(key, identity) do
      :ok -> :ok
      {:error, :object_changed} -> {:error, :object_changed}
      _error -> {:error, :storage_delete_failed}
    end
  rescue
    _exception -> {:error, :storage_delete_failed}
  catch
    _kind, _reason -> {:error, :storage_delete_failed}
  end

  defp mark_failed(plan, code) when is_map(plan) do
    plan
    |> Map.put("status", "failed")
    |> Map.put("last_error_code", code |> to_string() |> String.slice(0, 160))
  end

  defp emit_reset_result({:ok, completed}, _original, _opts) do
    emit_reset_stop(completed, :completed, completed["environment"], nil)
  end

  defp emit_reset_result({:error, reason, failed}, original, opts) do
    plan = if is_map(failed), do: failed, else: original
    fallback_environment = if is_list(opts), do: Keyword.get(opts, :current_environment, "unknown"), else: "unknown"
    environment = plan_value(plan, "environment", fallback_environment)
    emit_reset_stop(plan, :error, environment, reset_error_code(reason))
  end

  defp emit_reset_result(_result, _plan, _opts), do: :ok

  defp emit_prepare_failure({:error, reason}, workspace_id, environment) do
    emit_reset_stop(%{"workspace_id" => workspace_id}, :error, environment, reset_error_code({:prepare, reason}))
  end

  defp emit_prepare_failure(_result, _workspace_id, _environment), do: :ok

  defp emit_reset_stop(plan, status, environment, error_code) do
    :telemetry.execute(
      [:storyarn, :snapshot, :reset, :stop],
      %{
        object_count: safe_length(plan_value(plan, "objects", [])),
        snapshot_row_count: safe_length(plan_value(plan, "snapshot_row_ids", [])),
        entity_version_row_count: safe_length(plan_value(plan, "entity_version_row_ids", [])),
        attempt_count: safe_non_negative_integer(plan_value(plan, "attempt_count", 0))
      },
      %{
        status: status,
        environment: environment,
        workspace_id: plan_value(plan, "workspace_id", nil),
        inventory_digest: plan_value(plan, "inventory_digest", nil),
        error_code: error_code
      }
    )
  end

  defp plan_value(plan, key, default) when is_map(plan), do: Map.get(plan, key, default)
  defp plan_value(_plan, _key, default), do: default

  defp safe_length(value) when is_list(value), do: length(value)
  defp safe_length(_value), do: 0

  defp safe_non_negative_integer(value) when is_integer(value) and value >= 0, do: value
  defp safe_non_negative_integer(_value), do: 0

  defp reset_error_code({:prepare, reason}), do: "prepare_#{stable_error_code(reason)}"
  defp reset_error_code(reason), do: stable_error_code(reason)

  defp stable_error_code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp stable_error_code(reason) when is_tuple(reason), do: tuple_error_code(reason)
  defp stable_error_code(_reason), do: "unexpected_error"

  defp tuple_error_code(reason) do
    reason
    |> Tuple.to_list()
    |> Enum.find(&is_atom/1)
    |> case do
      nil -> "unexpected_error"
      atom -> Atom.to_string(atom)
    end
  end
end
