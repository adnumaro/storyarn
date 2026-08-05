defmodule Storyarn.Versioning.ProjectSnapshotReset do
  @moduledoc """
  Two-stage environment reset for pre-canonical project snapshots.

  Workspace plans remove attributable rows and objects first. One final provider
  plan binds the exact latest workspace-receipt revisions and inventories every
  remaining strict snapshot key, including orphan roots. Each generated JSON
  plan is the durable audit and retry record. Execution accepts only its exact
  inventory, rejects new or replaced objects, and checkpoints the shrinking
  inventory before an immutable receipt is appended.

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
  @format_version 3
  @reset_receipts_migration 20_260_805_125_000
  @canonical_snapshot_rollout_migration 20_260_805_130_000
  @page_size 1_000
  @minimum_delete_checkpoint_size 100
  @max_delete_checkpoints 32
  @default_max_objects 250_000
  @default_max_scanned_objects 1_000_000
  @maximum_max_scanned_objects 10_000_000
  @max_bigint 9_223_372_036_854_775_807
  @max_plan_file_bytes 1_073_741_824
  @max_authorization_bytes 512
  @temporary_plan_write_attempts 5
  @sha256_regex ~r/\A[0-9a-f]{64}\z/
  @token_regex ~r/\A[A-Za-z0-9_-]{16}\z/
  @blob_filename_regex ~r/\A[0-9a-f]{64}\.[a-z0-9][a-z0-9-]{0,31}\z/
  @workspace_plan_keys Enum.sort(~w(
                           attempt_count authorization_digest completed_at environment format format_version
                           database_inventory_digest entity_version_row_ids inventory_digest last_error_code
                           objects plan_id prefixes prepared_at project_ids remaining_storage_keys scope
                           snapshot_row_ids status storage_namespace_fingerprint workspace_id
                         ))
  @provider_plan_keys Enum.sort(~w(
                          attempt_count authorization_digest completed_at environment format format_version
                          inventory_digest last_error_code max_scanned_objects objects plan_id prepared_at
                          remaining_storage_keys scanned_object_count scope status storage_namespace_fingerprint
                          workspace_receipt_ids
                        ))
  @provider_scan_prefix "projects/"

  defguardp valid_readiness_count(value) when is_integer(value) and value >= 0

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
           {:ok, namespace_fingerprint} <- storage_namespace_fingerprint(adapter),
           {:ok, project_ids, snapshot_rows, entity_version_rows} <- load_scope(repo, workspace_id, max_objects),
           :ok <- validate_snapshot_row_identities(snapshot_rows),
           :ok <- validate_entity_version_row_identities(entity_version_rows),
           prefixes = reset_prefixes(project_ids),
           {:ok, objects} <- list_exact_inventory(adapter, prefixes, max_objects),
           :ok <- validate_objects(objects, project_ids),
           plan =
             build_workspace_plan(
               environment,
               workspace_id,
               project_ids,
               snapshot_rows,
               entity_version_rows,
               prefixes,
               objects,
               namespace_fingerprint
             ),
           :ok <- validate_plan(plan) do
        {:ok, plan}
      end

    emit_prepare_failure(result, workspace_id, expected_environment)
    result
  end

  def prepare(_workspace_id, _expected_environment, _opts), do: {:error, :invalid_snapshot_reset_scope}

  @doc "Builds a read-only exact reset plan for every residual provider snapshot object."
  @spec prepare_provider(String.t(), keyword()) :: {:ok, plan()} | {:error, term()}
  def prepare_provider(expected_environment, opts \\ [])

  def prepare_provider(expected_environment, opts) when is_binary(expected_environment) and is_list(opts) do
    repo = Keyword.get(opts, :repo, Repo)
    adapter = Keyword.get(opts, :storage_adapter, Storage.adapter())
    max_objects = Keyword.get(opts, :max_objects, @default_max_objects)
    max_scanned_objects = Keyword.get(opts, :max_scanned_objects, @default_max_scanned_objects)

    result =
      with {:ok, environment} <- verify_environment(expected_environment, opts),
           :ok <- validate_max_objects(max_objects),
           :ok <- validate_max_scanned_objects(max_scanned_objects),
           :ok <- ensure_pre_rollout_reset_window(repo, opts),
           :ok <- ensure_reset_receipt_schema(repo),
           {:ok, namespace_fingerprint} <- storage_namespace_fingerprint(adapter),
           {:ok, workspace_receipt_ids} <-
             current_workspace_receipt_ids(repo, environment, namespace_fingerprint),
           {:ok, objects, scanned_object_count} <-
             list_global_snapshot_inventory(adapter, max_objects, max_scanned_objects),
           now = TimeHelpers.now(),
           plan =
             build_provider_plan(
               environment,
               workspace_receipt_ids,
               objects,
               scanned_object_count,
               max_scanned_objects,
               namespace_fingerprint,
               now
             ),
           :ok <- validate_plan(plan) do
        {:ok, plan}
      end

    emit_prepare_failure(result, nil, expected_environment)
    result
  end

  def prepare_provider(_expected_environment, _opts), do: {:error, :invalid_snapshot_reset_scope}

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
           :ok <- verify_storage_namespace(adapter, plan["storage_namespace_fingerprint"]),
           :ok <- ensure_pre_rollout_reset_window(repo, opts),
           :ok <- ensure_reset_receipt_schema(repo),
           :ok <- ensure_execution_scope_ready(repo, plan, environment),
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

  @doc false
  @spec read_authorization_file(Path.t()) :: {:ok, String.t()} | {:error, :unsafe_snapshot_reset_authorization_file}
  def read_authorization_file(path) when is_binary(path) do
    expanded = Path.expand(path)

    with {:ok, %File.Stat{type: :regular, mode: mode, size: size}} <- File.lstat(expanded),
         true <- Bitwise.band(mode, 0o077) == 0,
         true <- size > 0 and size <= @max_authorization_bytes + 1,
         {:ok, contents} <- File.read(expanded),
         authorization = String.trim(contents),
         true <- String.match?(authorization, ~r/\A[A-Za-z0-9_-]{32,512}\z/) do
      {:ok, authorization}
    else
      _invalid -> {:error, :unsafe_snapshot_reset_authorization_file}
    end
  end

  def read_authorization_file(_path), do: {:error, :unsafe_snapshot_reset_authorization_file}

  @doc "Verifies the global database receipt boundary required before lifecycle rollout."
  @spec verify_rollout_readiness(String.t(), keyword()) :: :ok | {:error, term()}
  def verify_rollout_readiness(expected_environment, opts \\ [])

  def verify_rollout_readiness(expected_environment, opts) when is_binary(expected_environment) and is_list(opts) do
    repo = Keyword.get(opts, :repo, Repo)
    adapter = Keyword.get(opts, :storage_adapter, Storage.adapter())

    with {:ok, environment} <- verify_environment(expected_environment, opts),
         {:ok, namespace_fingerprint} <- storage_namespace_fingerprint(adapter),
         {:ok, result} <- query_rollout_readiness(repo, environment, namespace_fingerprint) do
      validate_rollout_readiness_result(result)
    end
  rescue
    _exception -> {:error, :snapshot_reset_rollout_readiness_failed}
  catch
    _kind, _reason -> {:error, :snapshot_reset_rollout_readiness_failed}
  end

  def verify_rollout_readiness(_expected_environment, _opts), do: {:error, :snapshot_reset_environment_required}

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

  defp ensure_execution_scope_ready(_repo, %{"scope" => "workspace"}, _environment), do: :ok

  defp ensure_execution_scope_ready(repo, %{"scope" => "provider"} = plan, environment) do
    verify_workspace_rollout_readiness(
      repo,
      environment,
      plan["workspace_receipt_ids"],
      plan["storage_namespace_fingerprint"]
    )
  end

  defp execute_authorized_plan(
         %{"scope" => "workspace", "status" => "completed"} = plan,
         environment,
         _authorization,
         repo,
         adapter,
         _checkpoint
       ) do
    case fetch_matching_reset_receipt(repo, plan, environment) do
      {:ok, receipt} ->
        case final_zero_state(repo, adapter, plan) do
          :complete -> validate_completed_plan_receipt(plan, receipt)
          :incomplete -> {:error, :snapshot_reset_completed_state_changed, plan}
          {:error, reason} -> {:error, reason, plan}
        end

      {:error, reason} ->
        {:error, reason, plan}
    end
  end

  defp execute_authorized_plan(
         %{"scope" => "workspace"} = plan,
         environment,
         authorization_digest,
         repo,
         adapter,
         checkpoint
       ) do
    case fetch_optional_reset_receipt(repo, plan, environment) do
      {:ok, receipt} -> recover_existing_receipt(plan, receipt, repo, adapter, checkpoint)
      :missing -> execute_plan_without_receipt(plan, environment, authorization_digest, repo, adapter, checkpoint)
      {:error, reason} -> {:error, reason, plan}
    end
  end

  defp execute_authorized_plan(
         %{"scope" => "provider", "status" => "completed"} = plan,
         environment,
         _authorization,
         repo,
         adapter,
         _checkpoint
       ) do
    case fetch_matching_provider_reset_receipt(repo, plan, environment) do
      {:ok, receipt} ->
        case final_provider_zero_state(adapter, plan) do
          :complete -> validate_completed_plan_receipt(plan, receipt)
          :incomplete -> {:error, :snapshot_reset_completed_state_changed, plan}
          {:error, reason} -> {:error, reason, plan}
        end

      {:error, reason} ->
        {:error, reason, plan}
    end
  end

  defp execute_authorized_plan(
         %{"scope" => "provider"} = plan,
         environment,
         authorization_digest,
         repo,
         adapter,
         checkpoint
       ) do
    case fetch_optional_provider_reset_receipt(repo, plan, environment) do
      {:ok, receipt} ->
        recover_existing_provider_receipt(plan, receipt, adapter, checkpoint)

      :missing ->
        execute_provider_plan_without_receipt(plan, environment, authorization_digest, repo, adapter, checkpoint)

      {:error, reason} ->
        {:error, reason, plan}
    end
  end

  defp recover_existing_receipt(plan, receipt, repo, adapter, checkpoint) do
    case final_zero_state(repo, adapter, plan) do
      :complete -> checkpoint_completed_receipt(plan, receipt, checkpoint)
      :incomplete -> {:error, :snapshot_reset_completed_state_changed, plan}
      {:error, reason} -> {:error, reason, plan}
    end
  end

  defp execute_plan_without_receipt(plan, environment, authorization_digest, repo, adapter, checkpoint) do
    case final_zero_state(repo, adapter, plan) do
      :complete -> recover_completed_plan(plan, environment, authorization_digest, repo, checkpoint)
      :incomplete -> execute_pending_plan(plan, environment, authorization_digest, repo, adapter, checkpoint)
      {:error, reason} -> {:error, reason, plan}
    end
  end

  defp recover_completed_plan(plan, environment, authorization_digest, repo, checkpoint) do
    running = mark_running(plan, authorization_digest)

    case validate_workspace_receipt_params(running, environment) do
      :ok ->
        case checkpoint_plan(checkpoint, running) do
          :ok -> complete_execution(running, environment, repo, checkpoint)
          {:error, reason} -> fail_execution(running, {:snapshot_reset_checkpoint_failed, reason}, checkpoint)
        end

      {:error, reason} ->
        {:error, reason, plan}
    end
  end

  defp execute_pending_plan(plan, environment, authorization_digest, repo, adapter, checkpoint) do
    with :ok <- revalidate_database_scope(repo, plan),
         :ok <- revalidate_storage_scope(adapter, plan) do
      running = mark_running(plan, authorization_digest)

      case validate_workspace_receipt_params(running, environment) do
        :ok -> execute_running_plan(running, environment, repo, adapter, checkpoint)
        {:error, reason} -> {:error, reason, plan}
      end
    else
      {:error, reason} -> {:error, reason, plan}
    end
  end

  defp recover_existing_provider_receipt(plan, receipt, adapter, checkpoint) do
    case final_provider_zero_state(adapter, plan) do
      :complete -> checkpoint_completed_receipt(plan, receipt, checkpoint)
      :incomplete -> {:error, :snapshot_reset_completed_state_changed, plan}
      {:error, reason} -> {:error, reason, plan}
    end
  end

  defp execute_provider_plan_without_receipt(plan, environment, authorization_digest, repo, adapter, checkpoint) do
    case final_provider_zero_state(adapter, plan) do
      :complete -> recover_completed_provider_plan(plan, environment, authorization_digest, repo, checkpoint)
      :incomplete -> execute_pending_provider_plan(plan, environment, authorization_digest, repo, adapter, checkpoint)
      {:error, reason} -> {:error, reason, plan}
    end
  end

  defp recover_completed_provider_plan(plan, environment, authorization_digest, repo, checkpoint) do
    running = mark_running(plan, authorization_digest)

    case validate_provider_receipt_params(running, environment) do
      :ok ->
        case checkpoint_plan(checkpoint, running) do
          :ok -> complete_provider_execution(running, environment, repo, checkpoint)
          {:error, reason} -> fail_execution(running, {:snapshot_reset_checkpoint_failed, reason}, checkpoint)
        end

      {:error, reason} ->
        {:error, reason, plan}
    end
  end

  defp execute_pending_provider_plan(plan, environment, authorization_digest, repo, adapter, checkpoint) do
    case revalidate_provider_storage_scope(adapter, plan) do
      :ok ->
        running = mark_running(plan, authorization_digest)

        case validate_provider_receipt_params(running, environment) do
          :ok -> execute_running_provider_plan(running, environment, repo, adapter, checkpoint)
          {:error, reason} -> {:error, reason, plan}
        end

      {:error, reason} ->
        {:error, reason, plan}
    end
  end

  defp execute_running_provider_plan(running, environment, repo, adapter, checkpoint) do
    with :ok <- checkpoint_plan(checkpoint, running),
         {:ok, storage_complete} <- delete_inventory(adapter, running, checkpoint),
         :ok <- verify_global_provider_empty(adapter, running["max_scanned_objects"]),
         :ok <-
           verify_workspace_rollout_readiness(
             repo,
             environment,
             running["workspace_receipt_ids"],
             running["storage_namespace_fingerprint"]
           ) do
      complete_provider_execution(storage_complete, environment, repo, checkpoint)
    else
      {:error, reason, failed_plan} -> {:error, reason, failed_plan}
      {:error, reason} -> fail_execution(running, reason, checkpoint)
    end
  end

  defp complete_provider_execution(storage_complete, environment, repo, checkpoint) do
    case persist_or_validate_provider_reset_receipt(repo, storage_complete, environment) do
      {:ok, receipt} -> checkpoint_completed_receipt(storage_complete, receipt, checkpoint)
      {:error, reason} -> fail_execution(storage_complete, reason, checkpoint)
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
      {:ok, receipt} ->
        checkpoint_completed_receipt(storage_complete, receipt, checkpoint)

      {:error, reason} ->
        fail_execution(storage_complete, reason, checkpoint)
    end
  end

  defp checkpoint_completed_receipt(plan, receipt, checkpoint) do
    completed = completed_plan_from_receipt(plan, receipt)

    case checkpoint_plan(checkpoint, completed) do
      :ok -> {:ok, completed}
      {:error, reason} -> {:error, {:snapshot_reset_checkpoint_failed, reason}, completed}
    end
  end

  defp completed_plan_from_receipt(plan, receipt) do
    plan
    |> Map.put("status", "completed")
    |> Map.put("remaining_storage_keys", [])
    |> Map.put("authorization_digest", receipt.authorization_digest)
    |> Map.put("attempt_count", receipt.attempt_count)
    |> Map.put("completed_at", DateTime.to_iso8601(receipt.completed_at))
    |> Map.put("last_error_code", nil)
  end

  @doc false
  def validate_plan(
        %{
          "format" => @format,
          "format_version" => @format_version,
          "scope" => "workspace",
          "plan_id" => plan_id,
          "environment" => environment,
          "storage_namespace_fingerprint" => storage_namespace_fingerprint,
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
      with true <- Enum.sort(Map.keys(plan)) == @workspace_plan_keys,
           true <- valid_plan_id?(plan_id),
           true <- valid_environment?(environment),
           true <- valid_digest?(storage_namespace_fingerprint),
           true <- positive_bigint?(workspace_id),
           true <- positive_unique_bigints?(project_ids),
           true <- positive_unique_bigints?(row_ids),
           true <- positive_unique_bigints?(entity_version_row_ids),
           true <- valid_digest?(database_inventory_digest),
           true <- is_list(prefixes) and prefixes == reset_prefixes(project_ids),
           true <- valid_plan_objects?(objects),
           :ok <- validate_objects(objects, project_ids),
           true <- is_list(remaining) and Enum.all?(remaining, &is_binary/1),
           true <- remaining == Enum.uniq(remaining),
           object_keys = MapSet.new(objects, & &1["key"]),
           true <- Enum.all?(remaining, &MapSet.member?(object_keys, &1)),
           true <- is_binary(digest) and Regex.match?(@sha256_regex, digest),
           true <- Plug.Crypto.secure_compare(digest, inventory_digest(plan)),
           true <- status in ["prepared", "running", "failed", "completed"],
           true <- valid_attempt_count?(attempt_count),
           true <- status != "completed" or remaining == [],
           true <- valid_plan_state_metadata?(plan) do
        true
      else
        _invalid -> false
      end

    if valid?, do: :ok, else: {:error, :invalid_snapshot_reset_plan}
  end

  def validate_plan(
        %{
          "format" => @format,
          "format_version" => @format_version,
          "scope" => "provider",
          "plan_id" => plan_id,
          "environment" => environment,
          "storage_namespace_fingerprint" => storage_namespace_fingerprint,
          "workspace_receipt_ids" => workspace_receipt_ids,
          "scanned_object_count" => scanned_object_count,
          "max_scanned_objects" => max_scanned_objects,
          "objects" => objects,
          "remaining_storage_keys" => remaining,
          "inventory_digest" => digest,
          "status" => status,
          "attempt_count" => attempt_count
        } = plan
      ) do
    valid? =
      with true <- Enum.sort(Map.keys(plan)) == @provider_plan_keys,
           true <- valid_plan_id?(plan_id),
           true <- valid_environment?(environment),
           true <- valid_digest?(storage_namespace_fingerprint),
           true <- valid_workspace_receipt_ids?(workspace_receipt_ids),
           true <- valid_scanned_object_count?(scanned_object_count, max_scanned_objects),
           true <- valid_plan_objects?(objects),
           true <- scanned_object_count >= length(objects),
           :ok <- validate_provider_objects(objects),
           true <- is_list(remaining) and Enum.all?(remaining, &is_binary/1),
           true <- remaining == Enum.uniq(remaining),
           object_keys = MapSet.new(objects, & &1["key"]),
           true <- Enum.all?(remaining, &MapSet.member?(object_keys, &1)),
           true <- is_binary(digest) and Regex.match?(@sha256_regex, digest),
           true <- Plug.Crypto.secure_compare(digest, inventory_digest(plan)),
           true <- status in ["prepared", "running", "failed", "completed"],
           true <- valid_attempt_count?(attempt_count),
           true <- status != "completed" or remaining == [],
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

  defp valid_plan_id?(plan_id) when is_binary(plan_id), do: Ecto.UUID.cast(plan_id) == {:ok, plan_id}

  defp valid_plan_id?(_plan_id), do: false

  defp positive_bigint?(value), do: is_integer(value) and value > 0 and value <= @max_bigint

  defp valid_attempt_count?(value), do: is_integer(value) and value >= 0 and value < @max_bigint

  defp valid_scanned_object_count?(count, maximum) do
    is_integer(count) and count >= 0 and is_integer(maximum) and maximum > 0 and
      maximum <= @maximum_max_scanned_objects and count <= maximum
  end

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

  defp storage_namespace_fingerprint(adapter) do
    case adapter.namespace_fingerprint() do
      {:ok, fingerprint} when is_binary(fingerprint) ->
        if valid_digest?(fingerprint),
          do: {:ok, fingerprint},
          else: {:error, :snapshot_reset_storage_namespace_unavailable}

      _invalid ->
        {:error, :snapshot_reset_storage_namespace_unavailable}
    end
  rescue
    _exception -> {:error, :snapshot_reset_storage_namespace_unavailable}
  catch
    _kind, _reason -> {:error, :snapshot_reset_storage_namespace_unavailable}
  end

  defp verify_storage_namespace(adapter, expected_fingerprint) do
    with {:ok, current_fingerprint} <- storage_namespace_fingerprint(adapter),
         true <- Plug.Crypto.secure_compare(current_fingerprint, expected_fingerprint) do
      :ok
    else
      false -> {:error, :snapshot_reset_storage_namespace_changed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_environment(expected_environment, opts) do
    current = Keyword.get(opts, :current_environment) || System.get_env("STORYARN_DEPLOYMENT_ENVIRONMENT")

    cond do
      not valid_environment?(expected_environment) ->
        {:error, :snapshot_reset_environment_required}

      not valid_environment?(current) ->
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

    supplied = Keyword.get(opts, :authorization)
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
             to_regclass('public.project_snapshot_provider_reset_receipts') IS NOT NULL AND
             EXISTS (SELECT 1 FROM schema_migrations WHERE version = $1)
           """,
           [@reset_receipts_migration]
         ) do
      {:ok, %{rows: [[true]]}} -> :ok
      {:ok, _result} -> {:error, :snapshot_reset_receipt_schema_unavailable}
      {:error, reason} -> {:error, {:snapshot_reset_database_failed, reason}}
    end
  end

  defp query_rollout_readiness(repo, environment, namespace_fingerprint) do
    case repo.query(
           """
           WITH workspace_scopes AS (
             SELECT
               w.id AS workspace_id,
               COALESCE(
                 array_agg(p.id ORDER BY p.id) FILTER (WHERE p.id IS NOT NULL),
                 ARRAY[]::bigint[]
               ) AS project_ids
             FROM workspaces w
             LEFT JOIN projects p ON p.workspace_id = w.id
             GROUP BY w.id
           ),
           latest_receipts AS (
             SELECT DISTINCT ON (workspace_id)
               id,
               workspace_id,
               environment,
               project_ids,
               storage_namespace_fingerprint
             FROM project_snapshot_reset_receipts
             ORDER BY workspace_id, id DESC
           ),
           latest_provider_receipt AS (
             SELECT environment, workspace_receipt_ids, storage_namespace_fingerprint
             FROM project_snapshot_provider_reset_receipts
             ORDER BY id DESC
             LIMIT 1
           ),
           receipt_counts AS (
             SELECT
               count(*)::bigint AS workspace_count,
               count(*) FILTER (
                 WHERE
                   r.environment = $1 AND
                   r.project_ids = s.project_ids AND
                   r.storage_namespace_fingerprint = $3
               )::bigint AS matching_receipt_count,
               COALESCE(
                 array_agg(r.id ORDER BY r.id) FILTER (WHERE r.id IS NOT NULL),
                 ARRAY[]::bigint[]
               ) AS current_receipt_ids
             FROM workspace_scopes s
             LEFT JOIN latest_receipts r ON r.workspace_id = s.workspace_id
           )
           SELECT
             to_regclass('public.project_snapshot_reset_receipts') IS NOT NULL AND
               to_regclass('public.project_snapshot_provider_reset_receipts') IS NOT NULL AND
               EXISTS (SELECT 1 FROM schema_migrations WHERE version = $2),
             NOT EXISTS (SELECT 1 FROM project_snapshots),
             NOT EXISTS (SELECT 1 FROM entity_versions),
             workspace_count,
             matching_receipt_count,
             COALESCE(
               (
                 SELECT
                   environment = $1 AND
                   workspace_receipt_ids = current_receipt_ids AND
                   storage_namespace_fingerprint = $3
                 FROM latest_provider_receipt
               ),
               FALSE
             ),
             current_receipt_ids
           FROM receipt_counts
           """,
           [environment, @reset_receipts_migration, namespace_fingerprint]
         ) do
      {:ok, result} ->
        {:ok, result}

      {:error, %Postgrex.Error{postgres: %{code: :undefined_table}}} ->
        {:error, :snapshot_reset_receipt_schema_unavailable}

      {:error, reason} ->
        {:error, {:snapshot_reset_database_failed, reason}}

      _invalid ->
        {:error, :snapshot_reset_rollout_readiness_invalid_response}
    end
  end

  defp validate_rollout_readiness_result(%{
         rows: [
           [
             schema_ready,
             snapshots_empty,
             entity_versions_empty,
             workspace_count,
             matching_count,
             provider_receipt_matches,
             current_receipt_ids
           ]
         ]
       })
       when is_boolean(schema_ready) and is_boolean(snapshots_empty) and is_boolean(entity_versions_empty) and
              valid_readiness_count(workspace_count) and valid_readiness_count(matching_count) and
              is_boolean(provider_receipt_matches) and is_list(current_receipt_ids) do
    if valid_workspace_receipt_ids?(current_receipt_ids) do
      rollout_readiness_result(
        schema_ready,
        snapshots_empty,
        entity_versions_empty,
        workspace_count,
        matching_count,
        provider_receipt_matches
      )
    else
      {:error, :snapshot_reset_rollout_readiness_invalid_response}
    end
  end

  defp validate_rollout_readiness_result(_invalid), do: {:error, :snapshot_reset_rollout_readiness_invalid_response}

  defp current_workspace_receipt_ids(repo, environment, namespace_fingerprint) do
    with {:ok, result} <- query_rollout_readiness(repo, environment, namespace_fingerprint) do
      validate_workspace_rollout_readiness_result(result)
    end
  rescue
    _exception -> {:error, :snapshot_reset_rollout_readiness_failed}
  catch
    _kind, _reason -> {:error, :snapshot_reset_rollout_readiness_failed}
  end

  defp verify_workspace_rollout_readiness(repo, environment, expected_receipt_ids, namespace_fingerprint) do
    with {:ok, current_receipt_ids} <-
           current_workspace_receipt_ids(repo, environment, namespace_fingerprint),
         true <- current_receipt_ids == expected_receipt_ids do
      :ok
    else
      false -> {:error, :snapshot_reset_workspace_receipts_changed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_workspace_rollout_readiness_result(%{
         rows: [
           [
             schema_ready,
             snapshots_empty,
             entity_versions_empty,
             workspace_count,
             matching_count,
             _provider_receipt_matches,
             current_receipt_ids
           ]
         ]
       })
       when is_boolean(schema_ready) and is_boolean(snapshots_empty) and is_boolean(entity_versions_empty) and
              valid_readiness_count(workspace_count) and valid_readiness_count(matching_count) and
              is_list(current_receipt_ids) do
    if valid_workspace_receipt_ids?(current_receipt_ids) do
      workspace_rollout_readiness_result(
        schema_ready,
        snapshots_empty,
        entity_versions_empty,
        workspace_count,
        matching_count,
        current_receipt_ids
      )
    else
      {:error, :snapshot_reset_rollout_readiness_invalid_response}
    end
  end

  defp validate_workspace_rollout_readiness_result(_invalid),
    do: {:error, :snapshot_reset_rollout_readiness_invalid_response}

  defp workspace_rollout_readiness_result(
         false,
         _snapshots_empty,
         _entity_versions_empty,
         _count,
         _matching,
         _receipt_ids
       ), do: {:error, :snapshot_reset_receipt_schema_unavailable}

  defp workspace_rollout_readiness_result(true, false, _entity_versions_empty, _count, _matching, _receipt_ids),
    do: {:error, :snapshot_reset_rollout_database_not_empty}

  defp workspace_rollout_readiness_result(true, true, false, _count, _matching, _receipt_ids),
    do: {:error, :snapshot_reset_rollout_database_not_empty}

  defp workspace_rollout_readiness_result(true, true, true, count, count, receipt_ids) when is_list(receipt_ids),
    do: {:ok, receipt_ids}

  defp workspace_rollout_readiness_result(true, true, true, _count, _matching, _receipt_ids),
    do: {:error, :snapshot_reset_rollout_receipts_incomplete}

  defp rollout_readiness_result(
         false,
         _snapshots_empty,
         _entity_versions_empty,
         _workspace_count,
         _matching_count,
         _provider_receipt_matches
       ), do: {:error, :snapshot_reset_receipt_schema_unavailable}

  defp rollout_readiness_result(
         true,
         false,
         _entity_versions_empty,
         _workspace_count,
         _matching_count,
         _provider_receipt_matches
       ), do: {:error, :snapshot_reset_rollout_database_not_empty}

  defp rollout_readiness_result(true, true, false, _workspace_count, _matching_count, _provider_receipt_matches),
    do: {:error, :snapshot_reset_rollout_database_not_empty}

  defp rollout_readiness_result(true, true, true, count, count, true), do: :ok

  defp rollout_readiness_result(true, true, true, count, count, false),
    do: {:error, :snapshot_reset_rollout_provider_receipt_missing}

  defp rollout_readiness_result(true, true, true, _workspace_count, _matching_count, _provider_receipt_matches),
    do: {:error, :snapshot_reset_rollout_receipts_incomplete}

  defp verify_confirmation(plan, confirmation_digest) do
    if Regex.match?(@sha256_regex, confirmation_digest) and
         Plug.Crypto.secure_compare(plan["inventory_digest"], confirmation_digest),
       do: :ok,
       else: {:error, :snapshot_reset_inventory_confirmation_mismatch}
  end

  defp validate_max_objects(max_objects)
       when is_integer(max_objects) and max_objects > 0 and max_objects <= @default_max_objects, do: :ok

  defp validate_max_objects(_max_objects), do: {:error, :invalid_snapshot_reset_limit}

  defp validate_max_scanned_objects(maximum)
       when is_integer(maximum) and maximum > 0 and maximum <= @maximum_max_scanned_objects, do: :ok

  defp validate_max_scanned_objects(_maximum), do: {:error, :invalid_snapshot_reset_scanned_object_limit}

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

  defp list_global_snapshot_inventory(adapter, max_objects, max_scanned_objects) do
    case scan_global_snapshot_pages(adapter, nil, [], 0, 0, max_objects, max_scanned_objects, MapSet.new()) do
      {:ok, reversed_objects, _snapshot_count, scanned_count} ->
        objects = reversed_objects |> Enum.reverse() |> Enum.sort_by(& &1["key"])

        if objects == Enum.uniq_by(objects, & &1["key"]),
          do: {:ok, objects, scanned_count},
          else: {:error, :duplicate_snapshot_reset_object}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp scan_global_snapshot_pages(
         adapter,
         cursor,
         objects,
         object_count,
         scanned_count,
         max_objects,
         max_scanned_objects,
         seen_cursors
       ) do
    with {:ok, %{objects: page, cursor: next_cursor}} <- safe_list_prefix(adapter, @provider_scan_prefix, cursor),
         true <- is_list(page) and length(page) <= @page_size,
         {:ok, normalized} <- normalize_page(page, @provider_scan_prefix),
         {:ok, snapshot_objects} <- filter_global_snapshot_page(normalized),
         combined_count = object_count + length(snapshot_objects),
         combined_scanned_count = scanned_count + length(normalized),
         :ok <- ensure_inventory_count(combined_count, max_objects),
         :ok <- ensure_scanned_count(combined_scanned_count, max_scanned_objects) do
      combined = Enum.reduce(snapshot_objects, objects, &[&1 | &2])

      cond do
        is_nil(next_cursor) ->
          {:ok, combined, combined_count, combined_scanned_count}

        not is_binary(next_cursor) or next_cursor == "" ->
          {:error, :invalid_snapshot_reset_cursor}

        page == [] ->
          {:error, :empty_snapshot_reset_page_with_cursor}

        MapSet.member?(seen_cursors, next_cursor) ->
          {:error, :repeated_snapshot_reset_cursor}

        true ->
          scan_global_snapshot_pages(
            adapter,
            next_cursor,
            combined,
            combined_count,
            combined_scanned_count,
            max_objects,
            max_scanned_objects,
            MapSet.put(seen_cursors, next_cursor)
          )
      end
    else
      false -> {:error, :snapshot_reset_inventory_limit_exceeded}
      {:error, :snapshot_reset_scanned_object_limit_exceeded} = error -> error
      {:error, :snapshot_reset_inventory_limit_exceeded} = error -> error
      {:error, :unsafe_snapshot_reset_object} = error -> error
      {:error, reason} -> {:error, {:snapshot_reset_storage_list_failed, reason}}
      _invalid -> {:error, :invalid_snapshot_reset_storage_page}
    end
  end

  defp ensure_inventory_count(count, maximum) when count <= maximum, do: :ok
  defp ensure_inventory_count(_count, _maximum), do: {:error, :snapshot_reset_inventory_limit_exceeded}

  defp ensure_scanned_count(count, maximum) when count <= maximum, do: :ok
  defp ensure_scanned_count(_count, _maximum), do: {:error, :snapshot_reset_scanned_object_limit_exceeded}

  defp filter_global_snapshot_page(objects) do
    objects
    |> Enum.reduce_while({:ok, []}, fn object, {:ok, snapshots} ->
      case classify_global_provider_object(object) do
        :ignore -> {:cont, {:ok, snapshots}}
        {:snapshot, snapshot} -> {:cont, {:ok, [snapshot | snapshots]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, snapshots} -> {:ok, Enum.reverse(snapshots)}
      error -> error
    end
  end

  defp classify_global_provider_object(%{"key" => key} = object) do
    case String.split(key, "/", trim: false) do
      ["projects", project_id, "snapshots" | _tail] ->
        with {parsed_project_id, ""} when parsed_project_id > 0 <- Integer.parse(project_id),
             true <- valid_reset_key_for_project?(key, parsed_project_id) do
          {:snapshot, object}
        else
          _invalid -> {:error, :unsafe_snapshot_reset_object}
        end

      ["projects" | _non_snapshot] ->
        :ignore

      _invalid ->
        {:error, :invalid_snapshot_reset_storage_page}
    end
  end

  defp validate_provider_objects(objects) do
    if Enum.all?(objects, fn object -> match?({:snapshot, ^object}, classify_global_provider_object(object)) end),
      do: :ok,
      else: {:error, :unsafe_snapshot_reset_object}
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

  defp build_workspace_plan(
         environment,
         workspace_id,
         project_ids,
         snapshot_rows,
         entity_version_rows,
         prefixes,
         objects,
         storage_namespace_fingerprint
       ) do
    now = TimeHelpers.now()

    plan = %{
      "format" => @format,
      "format_version" => @format_version,
      "scope" => "workspace",
      "plan_id" => Ecto.UUID.generate(),
      "environment" => environment,
      "storage_namespace_fingerprint" => storage_namespace_fingerprint,
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

  defp build_provider_plan(
         environment,
         workspace_receipt_ids,
         objects,
         scanned_object_count,
         max_scanned_objects,
         storage_namespace_fingerprint,
         now
       ) do
    plan = %{
      "format" => @format,
      "format_version" => @format_version,
      "scope" => "provider",
      "plan_id" => Ecto.UUID.generate(),
      "environment" => environment,
      "storage_namespace_fingerprint" => storage_namespace_fingerprint,
      "workspace_receipt_ids" => workspace_receipt_ids,
      "scanned_object_count" => scanned_object_count,
      "max_scanned_objects" => max_scanned_objects,
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

  defp inventory_digest(%{"scope" => "workspace"} = plan) do
    [
      ["format", plan["format"]],
      ["format_version", plan["format_version"]],
      ["scope", plan["scope"]],
      ["plan_id", plan["plan_id"]],
      ["environment", plan["environment"]],
      ["storage_namespace_fingerprint", plan["storage_namespace_fingerprint"]],
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

  defp inventory_digest(%{"scope" => "provider"} = plan) do
    [
      ["format", plan["format"]],
      ["format_version", plan["format_version"]],
      ["scope", plan["scope"]],
      ["plan_id", plan["plan_id"]],
      ["environment", plan["environment"]],
      ["storage_namespace_fingerprint", plan["storage_namespace_fingerprint"]],
      ["workspace_receipt_ids", plan["workspace_receipt_ids"]],
      ["scanned_object_count", plan["scanned_object_count"]],
      ["max_scanned_objects", plan["max_scanned_objects"]],
      ["objects", Enum.map(plan["objects"], &[&1["key"], &1["size"], &1["identity"]])]
    ]
    |> Jason.encode_to_iodata!()
    |> sha256()
  end

  defp sha256(value), do: :sha256 |> :crypto.hash(value) |> Base.encode16(case: :lower)

  defp positive_unique_bigints?(values) when is_list(values) do
    values == Enum.uniq(values) and Enum.all?(values, &positive_bigint?/1)
  end

  defp positive_unique_bigints?(_values), do: false

  defp valid_workspace_receipt_ids?(values) when is_list(values) do
    values == Enum.sort(values) and positive_unique_bigints?(values)
  end

  defp valid_workspace_receipt_ids?(_values), do: false

  defp valid_plan_objects?(objects) when is_list(objects) and length(objects) <= @default_max_objects do
    Enum.all?(objects, &valid_plan_object?/1) and
      objects == Enum.sort_by(objects, & &1["key"]) and
      objects == Enum.uniq_by(objects, & &1["key"]) and
      object_bytes(objects) <= @max_bigint
  end

  defp valid_plan_objects?(_objects), do: false

  defp valid_plan_object?(%{"identity" => identity, "key" => key, "size" => size} = object) do
    Enum.sort(Map.keys(object)) == ["identity", "key", "size"] and is_binary(key) and is_integer(size) and
      size >= 0 and size <= @max_bigint and valid_object_identity?(identity)
  end

  defp valid_plan_object?(_object), do: false

  defp valid_object_identity?(identity) when is_binary(identity) do
    byte_size(identity) in 1..512 and String.valid?(identity) and String.trim(identity) == identity and
      not String.match?(identity, ~r/[\x00-\x1F\x7F]/u)
  end

  defp valid_object_identity?(_identity), do: false

  defp object_bytes(objects), do: Enum.reduce(objects, 0, &(&1["size"] + &2))

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

  defp revalidate_provider_storage_scope(adapter, plan) do
    with {:ok, current, _scanned_count} <-
           list_global_snapshot_inventory(
             adapter,
             length(plan["objects"]) + 1,
             plan["max_scanned_objects"]
           ) do
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
      {:ok, []} ->
        :ok

      {:ok, _objects} ->
        {:error, :snapshot_reset_final_inventory_not_empty}

      {:error, :snapshot_reset_inventory_limit_exceeded} ->
        {:error, :snapshot_reset_final_inventory_not_empty}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp verify_global_provider_empty(adapter, max_scanned_objects) do
    case list_global_snapshot_inventory(adapter, 1, max_scanned_objects) do
      {:ok, [], _scanned_count} -> :ok
      {:ok, _objects, _scanned_count} -> {:error, :snapshot_reset_final_inventory_not_empty}
      {:error, :snapshot_reset_inventory_limit_exceeded} -> {:error, :snapshot_reset_final_inventory_not_empty}
      {:error, reason} -> {:error, reason}
    end
  end

  defp final_provider_zero_state(adapter, plan) do
    case verify_global_provider_empty(adapter, plan["max_scanned_objects"]) do
      :ok -> :complete
      {:error, :snapshot_reset_final_inventory_not_empty} -> :incomplete
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
             WHERE table_schema = 'public' AND table_name = 'projects' AND
                   column_name = 'restoration_snapshot_id'
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
    params = reset_receipt_insert_params(plan, environment, completed_at)

    with :ok <- validate_workspace_receipt_params(plan, environment) do
      case repo.query(
             """
             INSERT INTO project_snapshot_reset_receipts (
               workspace_id, plan_id, project_ids, environment, inventory_digest,
               database_inventory_digest, storage_namespace_fingerprint,
               authorization_digest, object_count,
               object_bytes, snapshot_row_count, entity_version_row_count,
               attempt_count, completed_at
             )
             VALUES ($1, $2::text::uuid, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
             ON CONFLICT (workspace_id, plan_id) DO NOTHING
             RETURNING authorization_digest, attempt_count, completed_at
             """,
             params
           ) do
        {:ok, %{rows: [[authorization_digest, attempt_count, persisted_at]]}} ->
          normalize_reset_receipt(authorization_digest, attempt_count, persisted_at)

        {:ok, %{rows: []}} ->
          fetch_matching_reset_receipt(repo, plan, environment)

        {:error, reason} ->
          {:error, {:snapshot_reset_receipt_failed, reason}}

        _invalid ->
          {:error, :snapshot_reset_receipt_failed}
      end
    end
  end

  defp reset_receipt_insert_params(plan, environment, completed_at) do
    [
      plan["workspace_id"],
      plan["plan_id"],
      plan["project_ids"],
      environment,
      plan["inventory_digest"],
      plan["database_inventory_digest"],
      plan["storage_namespace_fingerprint"],
      plan["authorization_digest"],
      length(plan["objects"]),
      object_bytes(plan["objects"]),
      length(plan["snapshot_row_ids"]),
      length(plan["entity_version_row_ids"]),
      plan["attempt_count"],
      completed_at
    ]
  end

  defp validate_workspace_receipt_params(%{"scope" => "workspace"} = plan, environment) do
    with :ok <- validate_plan(plan),
         true <- plan["environment"] == environment,
         true <- plan["attempt_count"] > 0 do
      :ok
    else
      _invalid -> {:error, :invalid_snapshot_reset_receipt_params}
    end
  end

  defp validate_workspace_receipt_params(_plan, _environment), do: {:error, :invalid_snapshot_reset_receipt_params}

  defp validate_provider_receipt_params(%{"scope" => "provider"} = plan, environment) do
    with :ok <- validate_plan(plan),
         true <- plan["environment"] == environment,
         true <- plan["attempt_count"] > 0 do
      :ok
    else
      _invalid -> {:error, :invalid_snapshot_reset_receipt_params}
    end
  end

  defp validate_provider_receipt_params(_plan, _environment), do: {:error, :invalid_snapshot_reset_receipt_params}

  defp persist_or_validate_provider_reset_receipt(repo, plan, environment) do
    completed_at = TimeHelpers.now()

    with :ok <- validate_provider_receipt_params(plan, environment) do
      case repo.query(
             """
             INSERT INTO project_snapshot_provider_reset_receipts (
               plan_id, environment, inventory_digest, storage_namespace_fingerprint,
               authorization_digest, workspace_receipt_ids, object_count, object_bytes,
               scanned_object_count, max_scanned_objects, attempt_count, completed_at
             )
             VALUES ($1::text::uuid, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
             ON CONFLICT (plan_id) DO NOTHING
             RETURNING authorization_digest, attempt_count, completed_at
             """,
             [
               plan["plan_id"],
               environment,
               plan["inventory_digest"],
               plan["storage_namespace_fingerprint"],
               plan["authorization_digest"],
               plan["workspace_receipt_ids"],
               length(plan["objects"]),
               object_bytes(plan["objects"]),
               plan["scanned_object_count"],
               plan["max_scanned_objects"],
               plan["attempt_count"],
               completed_at
             ]
           ) do
        {:ok, %{rows: [[authorization_digest, attempt_count, persisted_at]]}} ->
          normalize_reset_receipt(authorization_digest, attempt_count, persisted_at)

        {:ok, %{rows: []}} ->
          fetch_matching_provider_reset_receipt(repo, plan, environment)

        {:error, reason} ->
          {:error, {:snapshot_reset_receipt_failed, reason}}

        _invalid ->
          {:error, :snapshot_reset_receipt_failed}
      end
    end
  end

  defp validate_completed_plan_receipt(plan, receipt) do
    valid? =
      plan["authorization_digest"] == receipt.authorization_digest and
        plan["attempt_count"] == receipt.attempt_count and
        plan["completed_at"] == DateTime.to_iso8601(receipt.completed_at)

    if valid?,
      do: {:ok, plan},
      else: {:error, :snapshot_reset_receipt_mismatch, plan}
  end

  defp fetch_optional_reset_receipt(repo, plan, environment) do
    case fetch_matching_reset_receipt(repo, plan, environment) do
      {:ok, receipt} -> {:ok, receipt}
      {:error, :snapshot_reset_receipt_missing} -> :missing
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_optional_provider_reset_receipt(repo, plan, environment) do
    case fetch_matching_provider_reset_receipt(repo, plan, environment) do
      {:ok, receipt} -> {:ok, receipt}
      {:error, :snapshot_reset_receipt_missing} -> :missing
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_matching_reset_receipt(repo, plan, environment) do
    case repo.query(
           """
           SELECT plan_id::text, project_ids, environment, inventory_digest,
                  database_inventory_digest, storage_namespace_fingerprint,
                  object_count, object_bytes,
                  snapshot_row_count, entity_version_row_count,
                  authorization_digest, attempt_count, completed_at
           FROM project_snapshot_reset_receipts
           WHERE workspace_id = $1 AND plan_id = $2::text::uuid
           """,
           [plan["workspace_id"], plan["plan_id"]]
         ) do
      {:ok, %{rows: [row]}} -> validate_reset_receipt_row(row, plan, environment)
      {:ok, %{rows: []}} -> {:error, :snapshot_reset_receipt_missing}
      {:error, reason} -> {:error, {:snapshot_reset_receipt_failed, reason}}
      _invalid -> {:error, :snapshot_reset_receipt_failed}
    end
  end

  defp fetch_matching_provider_reset_receipt(repo, plan, environment) do
    case repo.query(
           """
           SELECT plan_id::text, environment, inventory_digest, object_count,
                  object_bytes, scanned_object_count, max_scanned_objects,
                  workspace_receipt_ids, storage_namespace_fingerprint,
                  authorization_digest, attempt_count, completed_at
           FROM project_snapshot_provider_reset_receipts
           WHERE plan_id = $1::text::uuid
           """,
           [plan["plan_id"]]
         ) do
      {:ok, %{rows: [row]}} -> validate_provider_reset_receipt_row(row, plan, environment)
      {:ok, %{rows: []}} -> {:error, :snapshot_reset_receipt_missing}
      {:error, reason} -> {:error, {:snapshot_reset_receipt_failed, reason}}
      _invalid -> {:error, :snapshot_reset_receipt_failed}
    end
  end

  defp validate_reset_receipt_row(row, plan, environment) do
    {identity, [authorization_digest, receipt_attempt_count, completed_at]} = Enum.split(row, -3)

    if identity == reset_receipt_identity(plan, environment) do
      normalize_reset_receipt(authorization_digest, receipt_attempt_count, completed_at)
    else
      {:error, :snapshot_reset_receipt_mismatch}
    end
  end

  defp validate_provider_reset_receipt_row(row, plan, environment) do
    {identity, [authorization_digest, receipt_attempt_count, completed_at]} = Enum.split(row, -3)

    if identity == provider_reset_receipt_identity(plan, environment) do
      normalize_reset_receipt(authorization_digest, receipt_attempt_count, completed_at)
    else
      {:error, :snapshot_reset_receipt_mismatch}
    end
  end

  defp normalize_reset_receipt(authorization_digest, attempt_count, completed_at)
       when is_integer(attempt_count) and attempt_count > 0 do
    with true <- valid_digest?(authorization_digest),
         {:ok, normalized_at} <- normalize_receipt_completed_at(completed_at) do
      {:ok,
       %{
         authorization_digest: authorization_digest,
         attempt_count: attempt_count,
         completed_at: normalized_at
       }}
    else
      _invalid -> {:error, :snapshot_reset_receipt_mismatch}
    end
  end

  defp normalize_reset_receipt(_authorization_digest, _attempt_count, _completed_at),
    do: {:error, :snapshot_reset_receipt_mismatch}

  defp normalize_receipt_completed_at(%DateTime{} = completed_at), do: {:ok, completed_at}

  defp normalize_receipt_completed_at(%NaiveDateTime{} = completed_at) do
    {:ok, DateTime.from_naive!(completed_at, "Etc/UTC")}
  end

  defp normalize_receipt_completed_at(_invalid), do: {:error, :snapshot_reset_receipt_mismatch}

  defp reset_receipt_identity(plan, environment) do
    [
      plan["plan_id"],
      plan["project_ids"],
      environment,
      plan["inventory_digest"],
      plan["database_inventory_digest"],
      plan["storage_namespace_fingerprint"],
      length(plan["objects"]),
      object_bytes(plan["objects"]),
      length(plan["snapshot_row_ids"]),
      length(plan["entity_version_row_ids"])
    ]
  end

  defp provider_reset_receipt_identity(plan, environment) do
    [
      plan["plan_id"],
      environment,
      plan["inventory_digest"],
      length(plan["objects"]),
      object_bytes(plan["objects"]),
      plan["scanned_object_count"],
      plan["max_scanned_objects"],
      plan["workspace_receipt_ids"],
      plan["storage_namespace_fingerprint"]
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
