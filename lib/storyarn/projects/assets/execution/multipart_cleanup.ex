# The persisted phases below are intentionally explicit: collapsing their branches
# would make crash/replay and compare-and-swap outcomes harder to audit.
# credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
# credo:disable-for-this-file Credo.Check.Refactor.Nesting
defmodule Storyarn.Projects.Assets.MultipartCleanup do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Assets.StorageCleanupMultipartUpload
  alias Storyarn.Projects.Assets.StorageCleanupRequest
  alias Storyarn.Repo

  require Logger

  @claim_lease_seconds 30 * 60
  @claim_safety_margin_ms 5_000
  @max_failures 12
  @max_cleanup_targets 30_001
  @max_references_per_request 100_000
  @max_residue_cycles 20
  @inventory_batch_size 100
  @initial_retry_seconds 5
  @max_retry_seconds 60 * 60
  @force_delete_prefix "__storyarn_force_delete__:"
  @replayable_blocked_errors ~w(provider_namespace_changed)
  @phases ~w(
    discover
    abort
    delete
    quiet
    verify_inventory
    verify_references
    verify_objects
    verify_final_inventory
    confirmed
    blocked
  )

  @type result :: :ok | {:deferred, pos_integer()} | {:error, [String.t()]}
  @type cleanup_target :: %{stored: String.t(), key: String.t()}
  @type targets :: %{stored: [String.t()], all: [cleanup_target()], multipart: [cleanup_target()]}

  @doc false
  @spec process(pos_integer(), [String.t()], keyword()) :: result()
  def process(cleanup_request_id, cleanup_targets, opts \\ [])

  def process(cleanup_request_id, cleanup_targets, opts)
      when is_integer(cleanup_request_id) and cleanup_request_id > 0 and is_list(cleanup_targets) and is_list(opts) do
    with {:ok, config} <- config(opts),
         {:ok, targets} <- normalize_targets(cleanup_targets) do
      run(cleanup_request_id, targets, config)
    else
      {:error, _reason} -> {:error, cleanup_targets}
    end
  rescue
    exception ->
      Logger.error("Exact multipart cleanup raised error=#{safe_exception(exception)}")
      {:error, cleanup_targets}
  catch
    kind, _reason ->
      Logger.error("Exact multipart cleanup stopped error=#{safe_failure_kind(kind)}")
      {:error, cleanup_targets}
  end

  def process(_cleanup_request_id, cleanup_targets, _opts) when is_list(cleanup_targets), do: {:error, cleanup_targets}
  def process(_cleanup_request_id, _cleanup_targets, _opts), do: {:error, []}

  @doc false
  @spec reopen_confirmed(pos_integer()) :: :ok | {:error, term()}
  def reopen_confirmed(cleanup_request_id) when is_integer(cleanup_request_id) and cleanup_request_id > 0 do
    fn ->
      case lock_request(cleanup_request_id) do
        %StorageCleanupRequest{multipart_cleanup_phase: "confirmed"} = request ->
          request
          |> StorageCleanupRequest.multipart_cleanup_changeset(%{
            multipart_cleanup_phase: "discover",
            multipart_cleanup_cursor: 0,
            multipart_cleanup_residue_count: 0,
            multipart_cleanup_inventory_complete: false,
            multipart_cleanup_claim_token: nil,
            multipart_cleanup_claim_expires_at: nil,
            multipart_cleanup_failure_count: 0,
            multipart_cleanup_next_attempt_at: nil,
            multipart_cleanup_last_error_code: nil,
            multipart_quiescence_started_at: nil,
            multipart_quiescence_not_before: nil
          })
          |> Repo.update()
          |> normalize_update_result(:multipart_cleanup_state_not_persisted)

        %StorageCleanupRequest{} ->
          {:error, :multipart_cleanup_request_not_confirmed}

        nil ->
          {:error, :storage_cleanup_request_not_found}
      end
    end
    |> Repo.transact()
    |> normalize_transaction_result()
  end

  def reopen_confirmed(_cleanup_request_id), do: {:error, :invalid_storage_cleanup_request}

  @doc false
  @spec resume_for_replay(pos_integer()) :: :ok | {:error, term()}
  def resume_for_replay(cleanup_request_id) when is_integer(cleanup_request_id) and cleanup_request_id > 0 do
    fn ->
      now = database_clock_now()

      case lock_request(cleanup_request_id) do
        %StorageCleanupRequest{
          multipart_cleanup_phase: "blocked",
          multipart_cleanup_last_error_code: error_code
        } = request
        when error_code in @replayable_blocked_errors ->
          reset_blocked_request_for_replay(request)

        %StorageCleanupRequest{
          multipart_cleanup_phase: "blocked",
          multipart_cleanup_last_error_code: error_code
        } ->
          {:error, {:multipart_cleanup_manual_repair_required, error_code}}

        %StorageCleanupRequest{} = request ->
          if active_claim?(request, now) do
            {:error, :multipart_cleanup_still_processing}
          else
            clear_retry_state_for_replay(request)
          end

        nil ->
          {:error, :storage_cleanup_request_not_found}
      end
    end
    |> Repo.transact()
    |> normalize_transaction_result()
  end

  def resume_for_replay(_cleanup_request_id), do: {:error, :invalid_storage_cleanup_request}

  defp reset_blocked_request_for_replay(request) do
    request
    |> StorageCleanupRequest.multipart_cleanup_changeset(%{
      multipart_cleanup_phase: "discover",
      multipart_cleanup_cursor: 0,
      multipart_cleanup_residue_count: 0,
      multipart_cleanup_inventory_complete: false,
      multipart_cleanup_claim_token: nil,
      multipart_cleanup_claim_expires_at: nil,
      multipart_cleanup_failure_count: 0,
      multipart_cleanup_next_attempt_at: nil,
      multipart_cleanup_last_error_code: nil,
      multipart_quiescence_started_at: nil,
      multipart_quiescence_not_before: nil
    })
    |> Repo.update()
    |> normalize_update_result(:multipart_cleanup_replay_not_persisted)
  end

  defp clear_retry_state_for_replay(request) do
    request
    |> StorageCleanupRequest.multipart_cleanup_changeset(%{
      multipart_cleanup_claim_token: nil,
      multipart_cleanup_claim_expires_at: nil,
      multipart_cleanup_failure_count: 0,
      multipart_cleanup_next_attempt_at: nil,
      multipart_cleanup_last_error_code: nil
    })
    |> Repo.update()
    |> normalize_update_result(:multipart_cleanup_replay_not_persisted)
  end

  defp config(opts) do
    allowed = [
      :consume?,
      :list_fun,
      :abort_fun,
      :state_fun,
      :object_policy_fun,
      :object_delete_fun,
      :stat_fun,
      :namespace_fun,
      :authorize_fun,
      :step_limit
    ]

    config = %{
      consume?: Keyword.get(opts, :consume?, false) == true,
      list_fun:
        Keyword.get(opts, :list_fun, fn key ->
          Storage.list_incomplete_multipart_uploads(key, batch_size: @inventory_batch_size)
        end),
      abort_fun: Keyword.get(opts, :abort_fun, &Storage.abort_incomplete_multipart_upload/2),
      state_fun: Keyword.get(opts, :state_fun, &Storage.incomplete_multipart_upload_state/2),
      object_policy_fun: Keyword.get(opts, :object_policy_fun, fn _target -> :delete end),
      object_delete_fun: Keyword.get(opts, :object_delete_fun, &Storage.delete_if_matches/2),
      stat_fun: Keyword.get(opts, :stat_fun, &Storage.object_probe/1),
      namespace_fun: Keyword.get(opts, :namespace_fun, &Storage.namespace_fingerprint/0),
      authorize_fun: Keyword.get(opts, :authorize_fun, fn _targets -> :ok end),
      step_limit: Keyword.get(opts, :step_limit, 1)
    }

    valid? =
      Keyword.keyword?(opts) and Enum.all?(Keyword.keys(opts), &(&1 in allowed)) and
        is_function(config.list_fun, 1) and is_function(config.abort_fun, 2) and
        is_function(config.state_fun, 2) and is_function(config.object_delete_fun, 2) and
        is_function(config.object_policy_fun, 1) and
        is_function(config.stat_fun, 1) and is_function(config.namespace_fun, 0) and
        is_function(config.authorize_fun, 1) and is_integer(config.step_limit) and
        config.step_limit in 1..100

    if valid?, do: {:ok, config}, else: {:error, :invalid_multipart_cleanup_options}
  end

  defp normalize_targets(cleanup_targets) do
    with true <- cleanup_targets != [] and length(cleanup_targets) <= @max_cleanup_targets,
         true <- length(Enum.uniq(cleanup_targets)) == length(cleanup_targets),
         {:ok, entries} <- normalize_target_entries(cleanup_targets),
         true <- length(Enum.uniq_by(entries, & &1.key)) == length(entries),
         multipart when multipart != [] <- Enum.filter(entries, &Storage.multipart_cleanup_key?(&1.key)) do
      {:ok, %{stored: cleanup_targets, all: entries, multipart: multipart}}
    else
      _invalid -> {:error, :invalid_multipart_cleanup_targets}
    end
  end

  defp normalize_target_entries(cleanup_targets) do
    cleanup_targets
    |> Enum.reduce_while({:ok, []}, fn stored, {:ok, entries} ->
      case provider_key(stored) do
        {:ok, key} -> {:cont, {:ok, [%{stored: stored, key: key} | entries]}}
        :error -> {:halt, {:error, :invalid_multipart_cleanup_target}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      {:error, _reason} = error -> error
    end
  end

  defp provider_key(@force_delete_prefix <> key) do
    if Storage.canonical_key?(key), do: {:ok, key}, else: :error
  end

  defp provider_key(key) when is_binary(key) do
    if Storage.canonical_key?(key), do: {:ok, key}, else: :error
  end

  defp provider_key(_target), do: :error

  defp run(cleanup_request_id, targets, config) do
    run_steps(cleanup_request_id, targets, config, config.step_limit)
  end

  defp run_steps(cleanup_request_id, targets, config, steps_left) do
    case claim_request(cleanup_request_id, targets) do
      {:ok, request} ->
        case run_claimed(request, targets, config) do
          {:deferred, 1} when steps_left > 1 ->
            run_steps(cleanup_request_id, targets, config, steps_left - 1)

          result ->
            result
        end

      {:deferred, seconds} ->
        {:deferred, seconds}

      {:error, _reason} ->
        {:error, targets.stored}
    end
  end

  defp run_claimed(%StorageCleanupRequest{multipart_cleanup_phase: "confirmed"} = request, targets, config),
    do: dispatch_phase(request, targets, config)

  defp run_claimed(request, targets, config) do
    Storage.with_operation_deadline(provider_step_deadline_ms(), fn ->
      case validate_provider_namespace(request, config.namespace_fun) do
        :ok -> dispatch_phase(request, targets, config)
        {:error, :provider_namespace_changed} -> block_claim(request, "provider_namespace_changed", targets)
        {:error, error_code} -> fail_claim(request, error_code, targets)
      end
    end)
  rescue
    _exception -> fail_claim(request, "multipart_cleanup_execution_error", targets)
  catch
    _kind, _reason -> fail_claim(request, "multipart_cleanup_execution_error", targets)
  end

  defp provider_step_deadline_ms do
    min(
      Storage.multipart_upload_part_deadline_ms(),
      @claim_lease_seconds * 1_000 - @claim_safety_margin_ms
    )
  end

  defp dispatch_phase(%StorageCleanupRequest{multipart_cleanup_phase: "discover"} = request, targets, config),
    do: discover_one_key(request, targets, config.list_fun)

  defp dispatch_phase(%StorageCleanupRequest{multipart_cleanup_phase: "abort"} = request, targets, config) do
    case next_reference_to_abort(request) do
      %StorageCleanupMultipartUpload{} = upload -> abort_persisted_reference(request, upload, targets, config)
      nil -> advance_after_abort(request, targets)
    end
  end

  defp dispatch_phase(%StorageCleanupRequest{multipart_cleanup_phase: "delete"} = request, targets, config),
    do: delete_one_object(request, targets, config)

  defp dispatch_phase(%StorageCleanupRequest{multipart_cleanup_phase: "quiet"} = request, targets, _config),
    do: transition_phase(request, targets, "verify_inventory", %{multipart_cleanup_cursor: 0})

  defp dispatch_phase(%StorageCleanupRequest{multipart_cleanup_phase: "verify_inventory"} = request, targets, config),
    do: verify_inventory_key(request, targets, config.list_fun, :verify_references)

  defp dispatch_phase(%StorageCleanupRequest{multipart_cleanup_phase: "verify_references"} = request, targets, config),
    do: verify_retained_reference(request, targets, config.state_fun)

  defp dispatch_phase(%StorageCleanupRequest{multipart_cleanup_phase: "verify_objects"} = request, targets, config),
    do: verify_object(request, targets, config)

  defp dispatch_phase(
         %StorageCleanupRequest{multipart_cleanup_phase: "verify_final_inventory"} = request,
         targets,
         config
       ), do: verify_inventory_key(request, targets, config.list_fun, {:confirmed, config.consume?})

  defp dispatch_phase(%StorageCleanupRequest{multipart_cleanup_phase: "confirmed"} = request, targets, config),
    do: maybe_consume_confirmed(request, targets, config.consume?)

  defp dispatch_phase(request, targets, _config), do: fail_claim(request, "invalid_multipart_cleanup_phase", targets)

  defp claim_request(cleanup_request_id, targets) do
    fn ->
      now = database_clock_now()

      case lock_request(cleanup_request_id) do
        nil -> {:ok, {:error, :storage_cleanup_request_not_found}}
        request -> prepare_and_claim(request, targets, now)
      end
    end
    |> Repo.transact()
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp prepare_and_claim(request, targets, now) do
    cond do
      request.storage_keys != targets.stored ->
        {:ok, {:error, :storage_cleanup_batch_not_owned}}

      request.multipart_cleanup_phase == "blocked" ->
        {:ok, {:error, :multipart_cleanup_blocked}}

      request.multipart_cleanup_phase == "confirmed" ->
        {:ok, {:ok, request}}

      is_nil(request.multipart_cleanup_phase) and is_nil(request.provider_namespace_fingerprint) ->
        block_unbound_legacy_request(request)

      is_nil(request.multipart_cleanup_phase) ->
        initialize_and_claim(request, now)

      deferred_until?(request.multipart_cleanup_next_attempt_at, now) ->
        {:ok, {:deferred, seconds_until(request.multipart_cleanup_next_attempt_at, now)}}

      request.multipart_cleanup_phase == "discover" and request.multipart_cleanup_generation == 0 and
          deferred_until?(request.multipart_quiescence_not_before, now) ->
        {:ok, {:deferred, seconds_until(request.multipart_quiescence_not_before, now)}}

      request.multipart_cleanup_phase == "quiet" and deferred_until?(request.multipart_quiescence_not_before, now) ->
        {:ok, {:deferred, seconds_until(request.multipart_quiescence_not_before, now)}}

      active_claim?(request, now) ->
        {:ok, {:deferred, seconds_until(request.multipart_cleanup_claim_expires_at, now)}}

      expired_claim?(request, now) ->
        retire_expired_claim(request, now)

      true ->
        persist_claim(request, now)
    end
  end

  defp block_unbound_legacy_request(request) do
    request
    |> StorageCleanupRequest.multipart_cleanup_changeset(%{
      multipart_cleanup_phase: "blocked",
      multipart_cleanup_last_error_code: "legacy_multipart_identity_unbound"
    })
    |> Repo.update()
    |> case do
      {:ok, _request} -> {:ok, {:error, :multipart_cleanup_identity_unbound}}
      {:error, _changeset} -> {:error, :multipart_cleanup_state_not_persisted}
    end
  end

  defp initialize_and_claim(request, now) do
    request
    |> StorageCleanupRequest.multipart_cleanup_changeset(%{
      multipart_cleanup_phase: "discover",
      multipart_cleanup_cursor: 0,
      multipart_cleanup_claim_token: Ecto.UUID.generate(),
      multipart_cleanup_claim_expires_at: DateTime.add(now, @claim_lease_seconds, :second)
    })
    |> Repo.update()
    |> case do
      {:ok, request} -> {:ok, {:ok, request}}
      {:error, _changeset} -> {:error, :multipart_cleanup_claim_not_persisted}
    end
  end

  defp persist_claim(request, now) do
    request
    |> StorageCleanupRequest.multipart_cleanup_changeset(%{
      multipart_cleanup_claim_token: Ecto.UUID.generate(),
      multipart_cleanup_claim_expires_at: DateTime.add(now, @claim_lease_seconds, :second)
    })
    |> Repo.update()
    |> case do
      {:ok, request} -> {:ok, {:ok, request}}
      {:error, _changeset} -> {:error, :multipart_cleanup_claim_not_persisted}
    end
  end

  defp active_claim?(request, now) do
    is_binary(request.multipart_cleanup_claim_token) and
      match?(%DateTime{}, request.multipart_cleanup_claim_expires_at) and
      DateTime.after?(request.multipart_cleanup_claim_expires_at, now)
  end

  defp expired_claim?(request, now) do
    is_binary(request.multipart_cleanup_claim_token) and
      match?(%DateTime{}, request.multipart_cleanup_claim_expires_at) and
      not DateTime.after?(request.multipart_cleanup_claim_expires_at, now)
  end

  defp retire_expired_claim(request, now) do
    failures = request.multipart_cleanup_failure_count + 1

    attrs =
      if failures >= @max_failures do
        %{
          multipart_cleanup_phase: "blocked",
          multipart_cleanup_claim_token: nil,
          multipart_cleanup_claim_expires_at: nil,
          multipart_cleanup_failure_count: failures,
          multipart_cleanup_next_attempt_at: nil,
          multipart_cleanup_last_error_code: "multipart_cleanup_claim_expired"
        }
      else
        %{
          multipart_cleanup_claim_token: nil,
          multipart_cleanup_claim_expires_at: nil,
          multipart_cleanup_failure_count: failures,
          multipart_cleanup_next_attempt_at: DateTime.add(now, retry_seconds(failures), :second),
          multipart_cleanup_last_error_code: "multipart_cleanup_claim_expired"
        }
      end

    request
    |> StorageCleanupRequest.multipart_cleanup_changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, %{multipart_cleanup_phase: "blocked"}} -> {:ok, {:error, :multipart_cleanup_blocked}}
      {:ok, updated} -> {:ok, {:deferred, seconds_until(updated.multipart_cleanup_next_attempt_at, now)}}
      {:error, _changeset} -> {:error, :multipart_cleanup_failure_not_persisted}
    end
  end

  defp validate_provider_namespace(request, namespace_fun) do
    with :ok <- ensure_provider_io_outside_database(),
         {:ok, fingerprint} <- safe_namespace(namespace_fun) do
      if fingerprint == request.provider_namespace_fingerprint,
        do: :ok,
        else: {:error, :provider_namespace_changed}
    end
  end

  defp discover_one_key(request, targets, list_fun) do
    case Enum.at(targets.multipart, request.multipart_cleanup_cursor) do
      %{key: key} ->
        case safe_list(list_fun, key) do
          {:ok, inventory} -> persist_discovery(request, key, inventory, targets)
          {:error, error_code} -> fail_claim(request, error_code, targets)
        end

      nil ->
        transition_phase(request, targets, "delete", %{
          multipart_cleanup_cursor: 0,
          multipart_cleanup_inventory_complete: true
        })
    end
  end

  defp safe_list(list_fun, key) do
    with :ok <- ensure_provider_io_outside_database() do
      case list_fun.(key) do
        {:ok, %{uploads: uploads, inventory_complete: complete?}}
        when is_list(uploads) and length(uploads) <= @inventory_batch_size and is_boolean(complete?) ->
          cond do
            not Enum.all?(uploads, &valid_upload_reference?(&1, key)) ->
              {:error, "invalid_multipart_inventory_response"}

            length(Enum.uniq(uploads)) != length(uploads) ->
              {:error, "invalid_multipart_inventory_response"}

            uploads == [] and not complete? ->
              {:error, "multipart_inventory_incomplete_empty"}

            true ->
              {:ok, %{uploads: uploads, inventory_complete: complete?}}
          end

        {:error, _reason} ->
          {:error, "multipart_inventory_provider_error"}

        _invalid ->
          {:error, "invalid_multipart_inventory_response"}
      end
    end
  rescue
    _exception -> {:error, "multipart_inventory_provider_error"}
  catch
    _kind, _reason -> {:error, "multipart_inventory_provider_error"}
  end

  defp valid_upload_reference?(%{key: key, upload_id: upload_id}, expected_key)
       when key == expected_key and is_binary(upload_id),
       do: upload_id != "" and byte_size(upload_id) <= 4_096 and String.valid?(upload_id)

  defp valid_upload_reference?(_upload, _expected_key), do: false

  defp persist_discovery(request, key, inventory, targets) do
    next_cursor =
      if inventory.inventory_complete,
        do: request.multipart_cleanup_cursor + 1,
        else: request.multipart_cleanup_cursor

    next_phase =
      cond do
        inventory.uploads != [] -> "abort"
        next_cursor >= length(targets.multipart) -> "delete"
        true -> "discover"
      end

    cursor = if next_phase == "delete", do: 0, else: next_cursor
    complete? = inventory.inventory_complete and next_cursor >= length(targets.multipart)

    result =
      Repo.transact(fn ->
        with %StorageCleanupRequest{} = current <- lock_request(request.id),
             true <- current_claim?(current, request),
             %{key: ^key} <- Enum.at(targets.multipart, current.multipart_cleanup_cursor) do
          generation = current.multipart_cleanup_generation + 1
          now = database_clock_now()

          mark_retained_references_already_aborted(current.id, generation, now)

          case upsert_observed_references(current.id, inventory.uploads, now) do
            {:ok, new_reference_count} ->
              no_progress? = not inventory.inventory_complete and new_reference_count == 0

              residue_count =
                if no_progress?,
                  do: current.multipart_cleanup_residue_count + 1,
                  else: current.multipart_cleanup_residue_count

              blocked? = residue_count > @max_residue_cycles

              attrs = %{
                multipart_cleanup_phase: if(blocked?, do: "blocked", else: next_phase),
                multipart_cleanup_generation: generation,
                multipart_cleanup_cursor: if(blocked?, do: current.multipart_cleanup_cursor, else: cursor),
                multipart_cleanup_residue_count: residue_count,
                multipart_cleanup_inventory_complete: if(blocked?, do: false, else: complete?),
                multipart_cleanup_claim_token: nil,
                multipart_cleanup_claim_expires_at: nil,
                multipart_cleanup_failure_count: 0,
                multipart_cleanup_next_attempt_at: nil,
                multipart_cleanup_last_error_code: if(blocked?, do: "multipart_discovery_stalled"),
                multipart_quiescence_started_at: nil,
                multipart_quiescence_not_before: nil
              }

              case current |> StorageCleanupRequest.multipart_cleanup_changeset(attrs) |> Repo.update() do
                {:ok, _request} -> {:ok, if(blocked?, do: :blocked, else: :ok)}
                {:error, _changeset} = error -> error
              end

            {:error, _reason} = error ->
              error
          end
        else
          false -> {:error, :stale_multipart_cleanup_claim}
          nil -> {:error, :storage_cleanup_request_not_found}
          _different_target -> {:error, :stale_multipart_cleanup_cursor}
        end
      end)

    case result do
      {:ok, :ok} ->
        emit_transition("discover", next_phase)
        {:deferred, 1}

      {:ok, :blocked} ->
        report_discovery_stalled(request)
        {:error, targets.stored}

      {:error, :multipart_upload_reference_budget_exhausted} ->
        block_claim(request, "multipart_reference_budget_exhausted", targets)

      {:error, _reason} ->
        persistence_failure(request, targets)
    end
  end

  defp next_reference_to_abort(request) do
    Repo.one(
      from(upload in StorageCleanupMultipartUpload,
        where: upload.cleanup_request_id == ^request.id,
        where:
          is_nil(upload.last_aborted_generation) or
            upload.last_aborted_generation < ^request.multipart_cleanup_generation,
        order_by: [asc: upload.id],
        limit: 1
      )
    )
  end

  defp abort_persisted_reference(request, upload, targets, config) do
    with :ok <- safe_authorize(config.authorize_fun, [upload.storage_key]),
         :ok <- ensure_provider_io_outside_database(),
         :ok <- safe_abort(config.abort_fun, upload.storage_key, upload.upload_id) do
      persist_aborted_reference(request, upload, targets)
    else
      {:error, error_code} -> fail_claim(request, error_code, targets)
    end
  end

  defp safe_abort(abort_fun, key, upload_id) do
    case abort_fun.(key, upload_id) do
      :ok -> :ok
      {:error, _reason} -> {:error, "multipart_abort_provider_error"}
      _invalid -> {:error, "invalid_multipart_abort_response"}
    end
  rescue
    _exception -> {:error, "multipart_abort_provider_error"}
  catch
    _kind, _reason -> {:error, "multipart_abort_provider_error"}
  end

  defp persist_aborted_reference(request, upload, targets) do
    result =
      Repo.transact(fn ->
        with %StorageCleanupRequest{} = current <- lock_request(request.id),
             true <- current_claim?(current, request),
             %StorageCleanupMultipartUpload{} = current_upload <- Repo.get(StorageCleanupMultipartUpload, upload.id),
             true <- current_upload.cleanup_request_id == current.id,
             {:ok, _upload} <-
               current_upload
               |> Ecto.Changeset.change(
                 last_aborted_generation: current.multipart_cleanup_generation,
                 last_absent_generation: nil,
                 updated_at: database_clock_now()
               )
               |> Repo.update(),
             {:ok, _request} <- release_claim(current) do
          {:ok, :ok}
        else
          false -> {:error, :stale_multipart_cleanup_claim}
          nil -> {:error, :storage_cleanup_request_not_found}
          {:error, _reason} = error -> error
        end
      end)

    case result do
      {:ok, :ok} ->
        emit_outcome("abort", "reference_aborted")
        {:deferred, 1}

      {:error, _reason} ->
        persistence_failure(request, targets)
    end
  end

  defp advance_after_abort(request, targets) do
    next_phase = if request.multipart_cleanup_inventory_complete, do: "delete", else: "discover"
    cursor = if next_phase == "delete", do: 0, else: request.multipart_cleanup_cursor
    transition_phase(request, targets, next_phase, %{multipart_cleanup_cursor: cursor})
  end

  defp delete_one_object(request, targets, config) do
    case Enum.at(targets.all, request.multipart_cleanup_cursor) do
      %{stored: stored, key: key} ->
        case safe_object_policy(config.object_policy_fun, stored) do
          :delete ->
            with :ok <- ensure_provider_io_outside_database(),
                 {:ok, object_state} <- safe_object_state(config.stat_fun, key) do
              delete_observed_object(request, targets, config, key, object_state)
            else
              {:error, error_code} -> fail_claim(request, error_code, targets)
            end

          :retain ->
            with :ok <- ensure_provider_io_outside_database(),
                 {:ok, object_state} <- safe_object_state(config.stat_fun, key) do
              retain_observed_object(request, targets, object_state)
            else
              {:error, error_code} -> fail_claim(request, error_code, targets)
            end

          {:error, error_code} ->
            fail_claim(request, error_code, targets)
        end

      nil ->
        enter_quiet(request, targets)
    end
  end

  defp safe_authorize(authorize_fun, targets) do
    case authorize_fun.(targets) do
      :ok -> :ok
      {:error, _reason} -> {:error, "multipart_cleanup_not_authorized"}
      _invalid -> {:error, "invalid_multipart_authorization_response"}
    end
  rescue
    _exception -> {:error, "multipart_cleanup_authorization_error"}
  catch
    _kind, _reason -> {:error, "multipart_cleanup_authorization_error"}
  end

  defp safe_object_policy(policy_fun, target) do
    case policy_fun.(target) do
      :delete ->
        :delete

      :retain ->
        :retain

      {:error, :force_cleanup_identity_verification_failed} ->
        {:error, "force_cleanup_identity_verification_failed"}

      {:error, _reason} ->
        {:error, "multipart_cleanup_not_authorized"}

      _invalid ->
        {:error, "invalid_multipart_object_policy_response"}
    end
  rescue
    _exception -> {:error, "multipart_cleanup_authorization_error"}
  catch
    _kind, _reason -> {:error, "multipart_cleanup_authorization_error"}
  end

  defp delete_observed_object(request, targets, _config, _key, :absent_now),
    do: persist_object_outcome(request, targets, "object_absent_now")

  defp delete_observed_object(request, targets, config, key, {:present, identity}) do
    case safe_object_delete(config.object_delete_fun, key, identity) do
      :ok -> persist_object_outcome(request, targets, "object_deleted")
      :changed -> restart_discovery(request, targets)
      {:error, error_code} -> fail_claim(request, error_code, targets)
    end
  end

  defp retain_observed_object(request, targets, {:present, _identity}),
    do: persist_object_outcome(request, targets, "object_retained")

  defp retain_observed_object(request, targets, :absent_now), do: fail_claim(request, "retained_object_missing", targets)

  defp safe_object_delete(delete_fun, key, identity) do
    case delete_fun.(key, identity) do
      :ok -> :ok
      {:error, :object_changed} -> :changed
      {:error, _reason} -> {:error, "multipart_object_delete_provider_error"}
      _invalid -> {:error, "invalid_multipart_object_delete_response"}
    end
  rescue
    _exception -> {:error, "multipart_object_delete_provider_error"}
  catch
    _kind, _reason -> {:error, "multipart_object_delete_provider_error"}
  end

  defp persist_object_outcome(request, targets, outcome) do
    next_cursor = request.multipart_cleanup_cursor + 1

    if next_cursor >= length(targets.all) do
      case enter_quiet(request, targets) do
        {:deferred, _seconds} = result ->
          emit_outcome("delete", outcome)
          result

        {:error, _failed_targets} = error ->
          error
      end
    else
      case transition_claimed(request, %{multipart_cleanup_cursor: next_cursor}) do
        :ok ->
          emit_outcome("delete", outcome)
          {:deferred, 1}

        {:error, _reason} ->
          persistence_failure(request, targets)
      end
    end
  end

  defp enter_quiet(request, targets) do
    result =
      Repo.transact(fn ->
        with %StorageCleanupRequest{} = current <- lock_request(request.id),
             true <- current_claim?(current, request) do
          now = database_clock_now()
          not_before = DateTime.add(now, Storage.multipart_cleanup_quiescence_seconds(), :second)

          current
          |> StorageCleanupRequest.multipart_cleanup_changeset(%{
            multipart_cleanup_phase: "quiet",
            multipart_cleanup_generation: current.multipart_cleanup_generation + 1,
            multipart_cleanup_cursor: 0,
            multipart_cleanup_inventory_complete: true,
            multipart_cleanup_claim_token: nil,
            multipart_cleanup_claim_expires_at: nil,
            multipart_cleanup_failure_count: 0,
            multipart_cleanup_next_attempt_at: nil,
            multipart_cleanup_last_error_code: nil,
            multipart_quiescence_started_at: now,
            multipart_quiescence_not_before: not_before
          })
          |> Repo.update()
          |> case do
            {:ok, _request} -> {:ok, seconds_until(not_before, now)}
            {:error, _changeset} -> {:error, :multipart_cleanup_state_not_persisted}
          end
        else
          false -> {:error, :stale_multipart_cleanup_claim}
          nil -> {:error, :storage_cleanup_request_not_found}
        end
      end)

    case result do
      {:ok, seconds} ->
        emit_transition("delete", "quiet")
        {:deferred, seconds}

      {:error, _reason} ->
        persistence_failure(request, targets)
    end
  end

  defp verify_inventory_key(request, targets, list_fun, complete_phase) do
    case Enum.at(targets.multipart, request.multipart_cleanup_cursor) do
      %{key: key} ->
        case safe_list(list_fun, key) do
          {:ok, %{uploads: uploads} = inventory} when uploads != [] ->
            persist_confirmation_residue(request, inventory, targets)

          {:ok, %{inventory_complete: true}} ->
            advance_verified_inventory(request, targets, complete_phase)

          {:ok, _incomplete} ->
            fail_claim(request, "multipart_inventory_incomplete_empty", targets)

          {:error, error_code} ->
            fail_claim(request, error_code, targets)
        end

      nil ->
        finish_inventory_phase(request, targets, complete_phase)
    end
  end

  defp advance_verified_inventory(request, targets, complete_phase) do
    next_cursor = request.multipart_cleanup_cursor + 1

    if next_cursor >= length(targets.multipart) do
      finish_inventory_phase(request, targets, complete_phase)
    else
      case transition_claimed(request, %{multipart_cleanup_cursor: next_cursor}) do
        :ok -> {:deferred, 1}
        {:error, _reason} -> persistence_failure(request, targets)
      end
    end
  end

  defp finish_inventory_phase(request, targets, :verify_references),
    do: transition_phase(request, targets, "verify_references", %{multipart_cleanup_cursor: 0})

  defp finish_inventory_phase(request, targets, {:confirmed, consume?}), do: persist_confirmed(request, targets, consume?)

  defp persist_confirmation_residue(request, inventory, targets) do
    result =
      Repo.transact(fn ->
        with %StorageCleanupRequest{} = current <- lock_request(request.id),
             true <- current_claim?(current, request) do
          generation = current.multipart_cleanup_generation + 1
          residue_count = current.multipart_cleanup_residue_count + 1
          now = database_clock_now()

          mark_retained_references_already_aborted(current.id, generation, now)

          with {:ok, _new_reference_count} <- upsert_observed_references(current.id, inventory.uploads, now),
               {:ok, _request} <- persist_residue_state(current, generation, residue_count) do
            {:ok, if(residue_count > @max_residue_cycles, do: :blocked, else: :retry)}
          else
            {:error, _reason} = error -> error
          end
        else
          false -> {:error, :stale_multipart_cleanup_claim}
          nil -> {:error, :storage_cleanup_request_not_found}
        end
      end)

    case result do
      {:ok, :retry} ->
        emit_transition(request.multipart_cleanup_phase, "abort")
        {:deferred, 1}

      {:ok, :blocked} ->
        report_residue_budget_exhausted(request)
        {:error, targets.stored}

      {:error, :multipart_upload_reference_budget_exhausted} ->
        block_claim(request, "multipart_reference_budget_exhausted", targets)

      {:error, _reason} ->
        persistence_failure(request, targets)
    end
  end

  defp persist_residue_state(request, generation, residue_count) do
    blocked? = residue_count > @max_residue_cycles

    attrs = %{
      multipart_cleanup_phase: if(blocked?, do: "blocked", else: "abort"),
      multipart_cleanup_generation: generation,
      multipart_cleanup_cursor: 0,
      multipart_cleanup_residue_count: residue_count,
      multipart_cleanup_inventory_complete: false,
      multipart_cleanup_claim_token: nil,
      multipart_cleanup_claim_expires_at: nil,
      multipart_cleanup_failure_count: 0,
      multipart_cleanup_next_attempt_at: nil,
      multipart_cleanup_last_error_code: if(blocked?, do: "multipart_residue_budget_exhausted"),
      multipart_quiescence_started_at: nil,
      multipart_quiescence_not_before: nil
    }

    request
    |> StorageCleanupRequest.multipart_cleanup_changeset(attrs)
    |> Repo.update()
  end

  defp verify_retained_reference(request, targets, state_fun) do
    case next_reference_to_confirm(request) do
      %StorageCleanupMultipartUpload{} = upload ->
        with :ok <- ensure_provider_io_outside_database(),
             {:ok, state} <- safe_upload_state(state_fun, upload.storage_key, upload.upload_id) do
          case state do
            :present -> persist_present_reference(request, upload, targets)
            :absent_now -> persist_reference_absence(request, upload, targets)
          end
        else
          {:error, error_code} -> fail_claim(request, error_code, targets)
        end

      nil ->
        transition_phase(request, targets, "verify_objects", %{multipart_cleanup_cursor: 0})
    end
  end

  defp next_reference_to_confirm(request) do
    Repo.one(
      from(upload in StorageCleanupMultipartUpload,
        where: upload.cleanup_request_id == ^request.id,
        where:
          is_nil(upload.last_absent_generation) or
            upload.last_absent_generation < ^request.multipart_cleanup_generation,
        order_by: [asc: upload.id],
        limit: 1
      )
    )
  end

  defp safe_upload_state(state_fun, key, upload_id) do
    case state_fun.(key, upload_id) do
      {:ok, state} when state in [:present, :absent_now] -> {:ok, state}
      {:error, _reason} -> {:error, "multipart_state_provider_error"}
      _invalid -> {:error, "invalid_multipart_state_response"}
    end
  rescue
    _exception -> {:error, "multipart_state_provider_error"}
  catch
    _kind, _reason -> {:error, "multipart_state_provider_error"}
  end

  defp persist_present_reference(request, upload, targets) do
    result =
      Repo.transact(fn ->
        with %StorageCleanupRequest{} = current <- lock_request(request.id),
             true <- current_claim?(current, request),
             %StorageCleanupMultipartUpload{} = current_upload <- Repo.get(StorageCleanupMultipartUpload, upload.id),
             true <- current_upload.cleanup_request_id == current.id do
          generation = current.multipart_cleanup_generation + 1
          residue_count = current.multipart_cleanup_residue_count + 1
          now = database_clock_now()
          mark_retained_references_already_aborted(current.id, generation, now)

          with {:ok, _upload} <-
                 current_upload
                 |> Ecto.Changeset.change(
                   last_aborted_generation: nil,
                   last_absent_generation: nil,
                   updated_at: now
                 )
                 |> Repo.update(),
               {:ok, _request} <- persist_residue_state(current, generation, residue_count) do
            {:ok, if(residue_count > @max_residue_cycles, do: :blocked, else: :retry)}
          else
            {:error, _reason} = error -> error
          end
        else
          false -> {:error, :stale_multipart_cleanup_claim}
          nil -> {:error, :storage_cleanup_request_not_found}
        end
      end)

    case result do
      {:ok, :retry} ->
        emit_transition("verify_references", "abort")
        {:deferred, 1}

      {:ok, :blocked} ->
        report_residue_budget_exhausted(request)
        {:error, targets.stored}

      {:error, _reason} ->
        persistence_failure(request, targets)
    end
  end

  defp persist_reference_absence(request, upload, targets) do
    result =
      Repo.transact(fn ->
        with %StorageCleanupRequest{} = current <- lock_request(request.id),
             true <- current_claim?(current, request),
             %StorageCleanupMultipartUpload{} = current_upload <- Repo.get(StorageCleanupMultipartUpload, upload.id),
             true <- current_upload.cleanup_request_id == current.id,
             {:ok, _upload} <-
               current_upload
               |> Ecto.Changeset.change(
                 last_absent_generation: current.multipart_cleanup_generation,
                 updated_at: database_clock_now()
               )
               |> Repo.update(),
             {:ok, _request} <- release_claim(current) do
          {:ok, :ok}
        else
          false -> {:error, :stale_multipart_cleanup_claim}
          nil -> {:error, :storage_cleanup_request_not_found}
          {:error, _reason} = error -> error
        end
      end)

    case result do
      {:ok, :ok} ->
        emit_outcome("verify_references", "reference_absent_now")
        {:deferred, 1}

      {:error, _reason} ->
        persistence_failure(request, targets)
    end
  end

  defp verify_object(request, targets, config) do
    case Enum.at(targets.all, request.multipart_cleanup_cursor) do
      %{stored: stored, key: key} ->
        case safe_object_policy(config.object_policy_fun, stored) do
          :retain ->
            with :ok <- ensure_provider_io_outside_database(),
                 {:ok, state} <- safe_object_state(config.stat_fun, key) do
              case state do
                {:present, _identity} -> advance_verified_object(request, targets)
                :absent_now -> fail_claim(request, "retained_object_missing", targets)
              end
            else
              {:error, error_code} -> fail_claim(request, error_code, targets)
            end

          :delete ->
            with :ok <- ensure_provider_io_outside_database(),
                 {:ok, state} <- safe_object_state(config.stat_fun, key) do
              case state do
                {:present, _identity} -> restart_discovery(request, targets)
                :absent_now -> advance_verified_object(request, targets)
              end
            else
              {:error, error_code} -> fail_claim(request, error_code, targets)
            end

          {:error, error_code} ->
            fail_claim(request, error_code, targets)
        end

      nil ->
        transition_phase(request, targets, "verify_final_inventory", %{multipart_cleanup_cursor: 0})
    end
  end

  defp safe_object_state(stat_fun, key) do
    case stat_fun.(key) do
      {:ok, %{size: size, content_type: content_type, identity: identity}}
      when is_integer(size) and size >= 0 and is_binary(content_type) and content_type != "" and
             is_binary(identity) and identity != "" ->
        {:ok, {:present, identity}}

      {:error, :enoent} ->
        {:ok, :absent_now}

      {:error, {:http_error, 404, _response}} ->
        {:ok, :absent_now}

      {:error, _reason} ->
        {:error, "multipart_object_stat_provider_error"}

      _invalid ->
        {:error, "invalid_multipart_object_stat_response"}
    end
  rescue
    _exception -> {:error, "multipart_object_stat_provider_error"}
  catch
    _kind, _reason -> {:error, "multipart_object_stat_provider_error"}
  end

  defp restart_discovery(request, targets) do
    residue_count = request.multipart_cleanup_residue_count + 1

    attrs =
      if residue_count > @max_residue_cycles do
        %{
          multipart_cleanup_phase: "blocked",
          multipart_cleanup_residue_count: residue_count,
          multipart_cleanup_last_error_code: "multipart_residue_budget_exhausted"
        }
      else
        %{
          multipart_cleanup_phase: "discover",
          multipart_cleanup_cursor: 0,
          multipart_cleanup_residue_count: residue_count,
          multipart_cleanup_inventory_complete: false,
          multipart_quiescence_started_at: nil,
          multipart_quiescence_not_before: nil
        }
      end

    case transition_claimed(request, attrs) do
      :ok when residue_count > @max_residue_cycles ->
        report_residue_budget_exhausted(request)
        {:error, targets.stored}

      :ok ->
        emit_transition(request.multipart_cleanup_phase, "discover")
        {:deferred, 1}

      {:error, _reason} ->
        persistence_failure(request, targets)
    end
  end

  defp advance_verified_object(request, targets) do
    next_cursor = request.multipart_cleanup_cursor + 1

    if next_cursor >= length(targets.all) do
      transition_phase(request, targets, "verify_final_inventory", %{multipart_cleanup_cursor: 0})
    else
      case transition_claimed(request, %{multipart_cleanup_cursor: next_cursor}) do
        :ok -> {:deferred, 1}
        {:error, _reason} -> persistence_failure(request, targets)
      end
    end
  end

  defp persist_confirmed(request, targets, consume?) do
    result =
      Repo.transact(fn ->
        with %StorageCleanupRequest{} = current <- lock_request(request.id),
             true <- current_claim?(current, request) do
          current
          |> StorageCleanupRequest.multipart_cleanup_changeset(%{
            multipart_cleanup_phase: "confirmed",
            multipart_cleanup_cursor: 0,
            multipart_cleanup_inventory_complete: true,
            multipart_cleanup_claim_token: nil,
            multipart_cleanup_claim_expires_at: nil,
            multipart_cleanup_failure_count: 0,
            multipart_cleanup_next_attempt_at: nil,
            multipart_cleanup_last_error_code: nil
          })
          |> Repo.update()
          |> normalize_update_result(:multipart_cleanup_confirmation_not_persisted)
        else
          false -> {:error, :stale_multipart_cleanup_claim}
          nil -> {:error, :storage_cleanup_request_not_found}
        end
      end)

    case result do
      {:ok, :ok} ->
        emit_transition("verify_final_inventory", "confirmed")
        maybe_consume_confirmed(%{request | multipart_cleanup_phase: "confirmed"}, targets, consume?)

      {:error, _reason} ->
        persistence_failure(request, targets)
    end
  end

  defp maybe_consume_confirmed(request, targets, true) when request.owner_kind == "storage_compensation",
    do: consume_confirmed_request(request.id, targets)

  defp maybe_consume_confirmed(%{owner_kind: "snapshot_lifecycle"}, _targets, _consume?), do: :ok
  defp maybe_consume_confirmed(_request, _targets, false), do: :ok
  defp maybe_consume_confirmed(_request, targets, true), do: {:error, targets.stored}

  defp consume_confirmed_request(cleanup_request_id, targets) do
    fn ->
      case lock_request(cleanup_request_id) do
        %StorageCleanupRequest{
          owner_kind: "storage_compensation",
          multipart_cleanup_phase: "confirmed",
          multipart_cleanup_claim_token: nil
        } = request ->
          request
          |> Repo.delete()
          |> normalize_update_result(:multipart_cleanup_receipt_not_consumed)

        %StorageCleanupRequest{} ->
          {:error, :multipart_cleanup_receipt_not_consumable}

        nil ->
          {:ok, :ok}
      end
    end
    |> Repo.transact()
    |> case do
      {:ok, :ok} -> :ok
      {:error, _reason} -> {:error, targets.stored}
    end
  end

  defp transition_phase(request, targets, next_phase, attrs) do
    previous_phase = request.multipart_cleanup_phase

    case transition_claimed(request, Map.put(attrs, :multipart_cleanup_phase, next_phase)) do
      :ok ->
        emit_transition(previous_phase, next_phase)
        {:deferred, 1}

      {:error, _reason} ->
        persistence_failure(request, targets)
    end
  end

  defp transition_claimed(request, attrs) do
    attrs =
      attrs
      |> Map.put(:multipart_cleanup_claim_token, nil)
      |> Map.put(:multipart_cleanup_claim_expires_at, nil)

    fn ->
      with %StorageCleanupRequest{} = current <- lock_request(request.id),
           true <- current_claim?(current, request) do
        current
        |> StorageCleanupRequest.multipart_cleanup_changeset(attrs)
        |> Repo.update()
        |> normalize_update_result(:multipart_cleanup_state_not_persisted)
      else
        false -> {:error, :stale_multipart_cleanup_claim}
        nil -> {:error, :storage_cleanup_request_not_found}
      end
    end
    |> Repo.transact()
    |> normalize_transaction_result()
  end

  defp release_claim(request) do
    request
    |> StorageCleanupRequest.multipart_cleanup_changeset(%{
      multipart_cleanup_claim_token: nil,
      multipart_cleanup_claim_expires_at: nil
    })
    |> Repo.update()
  end

  defp current_claim?(current, claimed) do
    current.multipart_cleanup_phase == claimed.multipart_cleanup_phase and
      current.multipart_cleanup_generation == claimed.multipart_cleanup_generation and
      current.multipart_cleanup_cursor == claimed.multipart_cleanup_cursor and
      current.multipart_cleanup_claim_token == claimed.multipart_cleanup_claim_token and
      is_binary(current.multipart_cleanup_claim_token)
  end

  defp upsert_observed_references(_cleanup_request_id, [], _now), do: {:ok, 0}

  defp upsert_observed_references(cleanup_request_id, uploads, now) do
    rows =
      Enum.map(uploads, fn %{key: key, upload_id: upload_id} ->
        %{
          cleanup_request_id: cleanup_request_id,
          storage_key: key,
          upload_id: upload_id,
          reference_digest: StorageCleanupMultipartUpload.reference_digest(key, upload_id),
          last_aborted_generation: nil,
          last_absent_generation: nil,
          inserted_at: now,
          updated_at: now
        }
      end)

    existing_count =
      Repo.aggregate(
        from(upload in StorageCleanupMultipartUpload, where: upload.cleanup_request_id == ^cleanup_request_id),
        :count
      )

    existing_digests =
      from(upload in StorageCleanupMultipartUpload,
        where: upload.cleanup_request_id == ^cleanup_request_id,
        select: upload.reference_digest
      )
      |> Repo.all()
      |> MapSet.new()

    new_count = Enum.count(rows, &(not MapSet.member?(existing_digests, &1.reference_digest)))

    if existing_count + new_count > @max_references_per_request do
      {:error, :multipart_upload_reference_budget_exhausted}
    else
      case persist_observed_references(cleanup_request_id, rows, now) do
        :ok -> {:ok, new_count}
        {:error, _reason} = error -> error
      end
    end
  end

  defp persist_observed_references(cleanup_request_id, rows, now) do
    {_count, _rows} =
      Repo.insert_all(StorageCleanupMultipartUpload, rows,
        conflict_target: [:cleanup_request_id, :reference_digest],
        on_conflict: [set: [last_aborted_generation: nil, last_absent_generation: nil, updated_at: now]]
      )

    digests = Enum.map(rows, & &1.reference_digest)

    persisted =
      from(upload in StorageCleanupMultipartUpload,
        where: upload.cleanup_request_id == ^cleanup_request_id and upload.reference_digest in ^digests,
        select: {upload.reference_digest, upload.storage_key, upload.upload_id}
      )
      |> Repo.all()
      |> MapSet.new()

    expected = MapSet.new(rows, &{&1.reference_digest, &1.storage_key, &1.upload_id})

    if persisted == expected, do: :ok, else: {:error, :multipart_upload_reference_not_persisted}
  end

  defp mark_retained_references_already_aborted(cleanup_request_id, generation, now) do
    Repo.update_all(
      from(upload in StorageCleanupMultipartUpload, where: upload.cleanup_request_id == ^cleanup_request_id),
      set: [last_aborted_generation: generation, last_absent_generation: nil, updated_at: now]
    )

    :ok
  end

  defp fail_claim(request, error_code, targets) when is_atom(error_code),
    do: fail_claim(request, Atom.to_string(error_code), targets)

  defp fail_claim(request, error_code, targets) when is_binary(error_code) do
    safe_code = normalize_error_code(error_code)

    persisted? =
      case Repo.transact(fn -> persist_failure(request, safe_code) end) do
        {:ok, :ok} -> true
        {:error, _reason} -> false
      end

    logged_code = if persisted?, do: safe_code, else: "multipart_cleanup_failure_not_persisted"

    Logger.warning(
      "Exact multipart cleanup failed phase=#{safe_phase(request.multipart_cleanup_phase)} code=#{logged_code}"
    )

    emit_failure(request.multipart_cleanup_phase, logged_code)
    {:error, targets.stored}
  end

  defp persistence_failure(request, targets), do: fail_claim(request, "multipart_cleanup_state_not_persisted", targets)

  defp persist_failure(request, safe_code) do
    with %StorageCleanupRequest{} = current <- lock_request(request.id),
         true <- current_claim?(current, request) do
      failures = current.multipart_cleanup_failure_count + 1

      attrs =
        if failures >= @max_failures do
          %{
            multipart_cleanup_phase: "blocked",
            multipart_cleanup_claim_token: nil,
            multipart_cleanup_claim_expires_at: nil,
            multipart_cleanup_failure_count: failures,
            multipart_cleanup_next_attempt_at: nil,
            multipart_cleanup_last_error_code: safe_code
          }
        else
          %{
            multipart_cleanup_claim_token: nil,
            multipart_cleanup_claim_expires_at: nil,
            multipart_cleanup_failure_count: failures,
            multipart_cleanup_next_attempt_at: DateTime.add(database_clock_now(), retry_seconds(failures), :second),
            multipart_cleanup_last_error_code: safe_code
          }
        end

      current
      |> StorageCleanupRequest.multipart_cleanup_changeset(attrs)
      |> Repo.update()
      |> normalize_update_result(:multipart_cleanup_failure_not_persisted)
    else
      false -> {:error, :stale_multipart_cleanup_claim}
      nil -> {:error, :storage_cleanup_request_not_found}
    end
  end

  defp block_claim(request, error_code, targets) do
    safe_code = normalize_error_code(error_code)

    attrs = %{
      multipart_cleanup_phase: "blocked",
      multipart_cleanup_claim_token: nil,
      multipart_cleanup_claim_expires_at: nil,
      multipart_cleanup_next_attempt_at: nil,
      multipart_cleanup_last_error_code: safe_code
    }

    persisted? = transition_claimed(request, attrs) == :ok
    logged_code = if persisted?, do: safe_code, else: "multipart_cleanup_block_not_persisted"

    Logger.error(
      "Exact multipart cleanup blocked phase=#{safe_phase(request.multipart_cleanup_phase)} code=#{logged_code}"
    )

    emit_failure(request.multipart_cleanup_phase, logged_code)
    {:error, targets.stored}
  end

  defp report_residue_budget_exhausted(request) do
    Logger.error(
      "Exact multipart cleanup blocked phase=#{safe_phase(request.multipart_cleanup_phase)} code=multipart_residue_budget_exhausted"
    )

    emit_failure(request.multipart_cleanup_phase, "multipart_residue_budget_exhausted")
  end

  defp report_discovery_stalled(request) do
    Logger.error(
      "Exact multipart cleanup blocked phase=#{safe_phase(request.multipart_cleanup_phase)} code=multipart_discovery_stalled"
    )

    emit_failure(request.multipart_cleanup_phase, "multipart_discovery_stalled")
  end

  defp safe_namespace(namespace_fun) do
    case namespace_fun.() do
      {:ok, fingerprint} when is_binary(fingerprint) and byte_size(fingerprint) == 64 ->
        if String.match?(fingerprint, ~r/\A[0-9a-f]{64}\z/),
          do: {:ok, fingerprint},
          else: {:error, :provider_namespace_unavailable}

      _unavailable ->
        {:error, :provider_namespace_unavailable}
    end
  rescue
    _exception -> {:error, :provider_namespace_unavailable}
  catch
    _kind, _reason -> {:error, :provider_namespace_unavailable}
  end

  defp ensure_provider_io_outside_database do
    if Repo.in_transaction?() or Repo.checked_out?(),
      do: {:error, "provider_io_inside_database_checkout"},
      else: :ok
  end

  defp deferred_until?(%DateTime{} = timestamp, now), do: DateTime.after?(timestamp, now)
  defp deferred_until?(_timestamp, _now), do: false

  defp retry_seconds(failure_count) do
    exponent = min(max(failure_count - 1, 0), 9)
    min(@initial_retry_seconds * Integer.pow(2, exponent), @max_retry_seconds)
  end

  defp lock_request(cleanup_request_id) do
    Repo.one(
      from(request in StorageCleanupRequest,
        where: request.id == ^cleanup_request_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp database_clock_now do
    %Postgrex.Result{rows: [[now]]} = Repo.query!("SELECT clock_timestamp()")
    DateTime.truncate(now, :second)
  end

  defp seconds_until(not_before, now), do: max(DateTime.diff(not_before, now, :second), 1)

  defp normalize_update_result({:ok, _record}, _error), do: {:ok, :ok}
  defp normalize_update_result({:error, _changeset}, error), do: {:error, error}

  defp normalize_transaction_result({:ok, :ok}), do: :ok
  defp normalize_transaction_result({:error, reason}), do: {:error, reason}

  defp normalize_error_code(code) do
    if byte_size(code) <= 100 and String.match?(code, ~r/\A[a-z][a-z0-9_]*\z/),
      do: code,
      else: "multipart_cleanup_error"
  end

  defp safe_phase(phase) when phase in @phases, do: phase
  defp safe_phase(_phase), do: "unknown"

  defp safe_exception(exception) when is_exception(exception), do: inspect(exception.__struct__)
  defp safe_exception(_exception), do: "unknown_exception"

  defp safe_failure_kind(kind) when kind in [:throw, :exit, :error], do: Atom.to_string(kind)
  defp safe_failure_kind(_kind), do: "unknown_failure"

  defp emit_transition(from, to) do
    :telemetry.execute(
      [:storyarn, :assets, :multipart_cleanup, :transition],
      %{count: 1},
      %{from: safe_phase(from), to: safe_phase(to)}
    )
  end

  defp emit_outcome(phase, outcome) do
    :telemetry.execute(
      [:storyarn, :assets, :multipart_cleanup, :operation],
      %{count: 1},
      %{phase: safe_phase(phase), outcome: outcome}
    )
  end

  defp emit_failure(phase, error_code) do
    :telemetry.execute(
      [:storyarn, :assets, :multipart_cleanup, :failure],
      %{count: 1},
      %{phase: safe_phase(phase), error_code: error_code}
    )
  end
end
