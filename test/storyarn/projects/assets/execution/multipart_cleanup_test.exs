defmodule Storyarn.Projects.Assets.MultipartCleanupTest do
  use Storyarn.DataCase, async: false

  import ExUnit.CaptureLog

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Assets.MultipartCleanup
  alias Storyarn.Projects.Assets.StorageCleanupMultipartUpload
  alias Storyarn.Projects.Assets.StorageCleanupRequest

  @fingerprint String.duplicate("a", 64)
  @key "projects/42/snapshots/archives/v2/staging/cleanupLease0001/snapshot.zip"
  @upload_id "opaque-upload-id"
  @failure_event [:storyarn, :assets, :multipart_cleanup, :failure]

  test "persists the exact upload reference before dispatching its remote abort" do
    request = insert_cleanup_request!()
    test_pid = self()

    opts =
      cleanup_opts(
        list_fun: fn @key ->
          {:ok,
           %{
             uploads: [%{key: @key, upload_id: @upload_id}],
             inventory_complete: true
           }}
        end,
        abort_fun: fn @key, @upload_id ->
          send(test_pid, {:provider_checkout_state, Repo.in_transaction?(), Repo.checked_out?()})

          upload =
            Repo.get_by!(StorageCleanupMultipartUpload,
              cleanup_request_id: request.id,
              storage_key: @key,
              upload_id: @upload_id
            )

          persisted_request = Repo.get!(StorageCleanupRequest, request.id)
          send(test_pid, {:durable_before_abort, upload.id, persisted_request.multipart_cleanup_phase})
          :ok
        end
      )

    assert {:deferred, 1} = MultipartCleanup.process(request.id, [@key], opts)
    refute_received {:durable_before_abort, _, _}

    assert %StorageCleanupMultipartUpload{
             storage_key: @key,
             upload_id: @upload_id,
             last_aborted_generation: nil
           } = Repo.get_by!(StorageCleanupMultipartUpload, cleanup_request_id: request.id)

    assert %StorageCleanupRequest{multipart_cleanup_phase: "abort"} =
             Repo.get!(StorageCleanupRequest, request.id)

    assert {:deferred, 1} = MultipartCleanup.process(request.id, [@key], opts)
    assert_received {:provider_checkout_state, false, false}
    assert_received {:durable_before_abort, upload_id, "abort"} when is_integer(upload_id)

    assert %StorageCleanupMultipartUpload{
             storage_key: @key,
             upload_id: @upload_id,
             last_aborted_generation: 1
           } = Repo.get_by!(StorageCleanupMultipartUpload, cleanup_request_id: request.id)
  end

  test "persists provider references for a force-delete cleanup target" do
    force_target = "__storyarn_force_delete__:" <> @key

    request =
      %StorageCleanupRequest{}
      |> StorageCleanupRequest.changeset(%{
        storage_keys: [force_target],
        provider_namespace_fingerprint: @fingerprint,
        multipart_cleanup_phase: "discover"
      })
      |> Repo.insert!()

    opts = cleanup_opts(list_fun: &one_upload_inventory/1)

    assert {:deferred, 1} = MultipartCleanup.process(request.id, [force_target], opts)

    assert %StorageCleanupMultipartUpload{storage_key: @key, upload_id: @upload_id} =
             Repo.get_by!(StorageCleanupMultipartUpload, cleanup_request_id: request.id)
  end

  test "durable handoff storage keys cannot be changed after insertion" do
    request = insert_cleanup_request!()

    assert_raise Postgrex.Error, ~r/cleanup request storage keys are immutable after handoff/, fn ->
      Repo.transaction(
        fn ->
          Repo.query!(
            "UPDATE storage_cleanup_requests SET storage_keys = $1 WHERE id = $2",
            [[@key <> ".changed"], request.id]
          )
        end,
        mode: :savepoint
      )
    end

    assert Repo.get!(StorageCleanupRequest, request.id).storage_keys == [@key]
  end

  test "durable handoff owner identity cannot be rebound after insertion" do
    request = insert_cleanup_request!()

    assert_raise Postgrex.Error, ~r/cleanup request owner identity is immutable after handoff/, fn ->
      Repo.transaction(
        fn ->
          Repo.query!(
            "UPDATE storage_cleanup_requests SET owner_kind = 'snapshot_lifecycle', owner_token = $1 WHERE id = $2",
            [Ecto.UUID.dump!(Ecto.UUID.generate()), request.id]
          )
        end,
        mode: :savepoint
      )
    end

    assert %StorageCleanupRequest{owner_kind: "storage_compensation", owner_token: nil} =
             Repo.get!(StorageCleanupRequest, request.id)
  end

  test "durable handoff provider namespace cannot be rebound after insertion" do
    request = insert_cleanup_request!()

    assert_raise Postgrex.Error, ~r/snapshot cleanup provider namespace is immutable/, fn ->
      Repo.transaction(
        fn ->
          Repo.query!(
            "UPDATE storage_cleanup_requests SET provider_namespace_fingerprint = $1 WHERE id = $2",
            [String.duplicate("b", 64), request.id]
          )
        end,
        mode: :savepoint
      )
    end

    assert Repo.get!(StorageCleanupRequest, request.id).provider_namespace_fingerprint == @fingerprint
  end

  test "an abort crash retains the exact reference and a retryable durable phase" do
    request = insert_cleanup_request!()
    private_body = "author@example.com/private-response-body"

    failing_opts =
      cleanup_opts(
        list_fun: &one_upload_inventory/1,
        abort_fun: fn @key, @upload_id -> raise private_body end
      )

    assert {:deferred, 1} = MultipartCleanup.process(request.id, [@key], failing_opts)
    assert {:error, [@key]} = MultipartCleanup.process(request.id, [@key], failing_opts)

    assert %StorageCleanupMultipartUpload{
             storage_key: @key,
             upload_id: @upload_id,
             last_aborted_generation: nil
           } = Repo.get_by!(StorageCleanupMultipartUpload, cleanup_request_id: request.id)

    failed_request = Repo.get!(StorageCleanupRequest, request.id)
    assert failed_request.multipart_cleanup_phase == "abort"
    assert failed_request.multipart_cleanup_claim_token == nil
    assert failed_request.multipart_cleanup_claim_expires_at == nil
    assert failed_request.multipart_cleanup_failure_count == 1
    assert failed_request.multipart_cleanup_next_attempt_at
    assert failed_request.multipart_cleanup_last_error_code == "multipart_abort_provider_error"

    make_due!(request.id)

    assert {:deferred, 1} =
             MultipartCleanup.process(
               request.id,
               [@key],
               cleanup_opts(list_fun: &one_upload_inventory/1, abort_fun: fn @key, @upload_id -> :ok end)
             )

    assert %StorageCleanupMultipartUpload{last_aborted_generation: 1} =
             Repo.get_by!(StorageCleanupMultipartUpload, cleanup_request_id: request.id)
  end

  test "an inventory crash releases the claim and keeps discovery retryable" do
    request = insert_cleanup_request!()
    private_body = "author@example.com/private-inventory-response"

    assert {:error, [@key]} =
             MultipartCleanup.process(
               request.id,
               [@key],
               cleanup_opts(list_fun: fn @key -> raise private_body end)
             )

    assert %StorageCleanupRequest{
             multipart_cleanup_phase: "discover",
             multipart_cleanup_generation: 0,
             multipart_cleanup_claim_token: nil,
             multipart_cleanup_claim_expires_at: nil,
             multipart_cleanup_failure_count: 1,
             multipart_cleanup_last_error_code: "multipart_inventory_provider_error",
             multipart_cleanup_next_attempt_at: %DateTime{}
           } = Repo.get!(StorageCleanupRequest, request.id)

    refute Repo.get_by(StorageCleanupMultipartUpload, cleanup_request_id: request.id)

    make_due!(request.id)

    assert {:deferred, seconds} =
             MultipartCleanup.process(
               request.id,
               [@key],
               cleanup_opts(list_fun: &empty_inventory/1)
             )

    assert seconds == 1
    assert Repo.get!(StorageCleanupRequest, request.id).multipart_cleanup_phase == "delete"

    assert {:deferred, quiet_seconds} =
             MultipartCleanup.process(
               request.id,
               [@key],
               cleanup_opts(list_fun: &empty_inventory/1)
             )

    assert quiet_seconds > 1
    assert Repo.get!(StorageCleanupRequest, request.id).multipart_cleanup_phase == "quiet"
  end

  test "operator replay clears only retryable scheduling state" do
    request = insert_cleanup_request!()

    assert {:error, [@key]} =
             MultipartCleanup.process(
               request.id,
               [@key],
               cleanup_opts(list_fun: fn @key -> {:error, :provider_unavailable} end)
             )

    assert %StorageCleanupRequest{
             multipart_cleanup_phase: "discover",
             multipart_cleanup_failure_count: 1,
             multipart_cleanup_next_attempt_at: %DateTime{},
             multipart_cleanup_last_error_code: "multipart_inventory_provider_error"
           } = Repo.get!(StorageCleanupRequest, request.id)

    assert :ok = MultipartCleanup.resume_for_replay(request.id)

    assert %StorageCleanupRequest{
             multipart_cleanup_phase: "discover",
             multipart_cleanup_failure_count: 0,
             multipart_cleanup_next_attempt_at: nil,
             multipart_cleanup_last_error_code: nil,
             multipart_cleanup_claim_token: nil,
             multipart_cleanup_claim_expires_at: nil
           } = Repo.get!(StorageCleanupRequest, request.id)
  end

  test "operator replay does not reopen a cleanup blocked for manual repair" do
    request = insert_cleanup_request!()

    request
    |> StorageCleanupRequest.multipart_cleanup_changeset(%{
      multipart_cleanup_phase: "blocked",
      multipart_cleanup_last_error_code: "multipart_reference_budget_exhausted"
    })
    |> Repo.update!()

    assert {:error, {:multipart_cleanup_manual_repair_required, "multipart_reference_budget_exhausted"}} =
             MultipartCleanup.resume_for_replay(request.id)

    assert %StorageCleanupRequest{
             multipart_cleanup_phase: "blocked",
             multipart_cleanup_last_error_code: "multipart_reference_budget_exhausted"
           } = Repo.get!(StorageCleanupRequest, request.id)
  end

  test "repeated incomplete pages with no new references exhaust a durable progress budget" do
    request = insert_cleanup_request!()

    %StorageCleanupMultipartUpload{}
    |> StorageCleanupMultipartUpload.create_changeset(request.id, @key, @upload_id)
    |> Repo.insert!()

    request
    |> StorageCleanupRequest.multipart_cleanup_changeset(%{multipart_cleanup_residue_count: 20})
    |> Repo.update!()

    opts =
      cleanup_opts(
        list_fun: fn @key ->
          {:ok,
           %{
             uploads: [%{key: @key, upload_id: @upload_id}],
             inventory_complete: false
           }}
        end
      )

    assert {:error, [@key]} = MultipartCleanup.process(request.id, [@key], opts)

    assert %StorageCleanupRequest{
             multipart_cleanup_phase: "blocked",
             multipart_cleanup_residue_count: 21,
             multipart_cleanup_last_error_code: "multipart_discovery_stalled",
             multipart_cleanup_claim_token: nil,
             multipart_cleanup_next_attempt_at: nil
           } = Repo.get!(StorageCleanupRequest, request.id)
  end

  test "absent_now evidence needs its own pass and a second pass after the quiet window" do
    request = insert_cleanup_request!()
    test_pid = self()

    opts =
      cleanup_opts(
        list_fun: &one_upload_inventory/1,
        abort_fun: fn @key, @upload_id -> :ok end,
        object_delete_fun: fn @key, _identity -> :ok end,
        state_fun: fn @key, @upload_id ->
          send(test_pid, :state_reported_absent_now)
          {:ok, :absent_now}
        end,
        stat_fun: fn @key -> {:error, :enoent} end
      )

    assert {:deferred, 1} = MultipartCleanup.process(request.id, [@key], opts)
    assert Repo.get!(StorageCleanupRequest, request.id).multipart_cleanup_phase == "abort"

    assert {:deferred, 1} = MultipartCleanup.process(request.id, [@key], opts)
    assert {:deferred, 1} = MultipartCleanup.process(request.id, [@key], opts)
    assert Repo.get!(StorageCleanupRequest, request.id).multipart_cleanup_phase == "delete"

    assert {:deferred, seconds} = MultipartCleanup.process(request.id, [@key], opts)
    assert seconds > 1

    quiet_request = Repo.get!(StorageCleanupRequest, request.id)
    assert quiet_request.multipart_cleanup_phase == "quiet"
    quiet_generation = quiet_request.multipart_cleanup_generation
    expire_quiet_window!(request.id)

    empty_inventory_opts = Keyword.put(opts, :list_fun, &empty_inventory/1)

    assert {:deferred, 1} = MultipartCleanup.process(request.id, [@key], empty_inventory_opts)
    assert Repo.get!(StorageCleanupRequest, request.id).multipart_cleanup_phase == "verify_inventory"

    assert {:deferred, 1} = MultipartCleanup.process(request.id, [@key], empty_inventory_opts)
    assert Repo.get!(StorageCleanupRequest, request.id).multipart_cleanup_phase == "verify_references"

    assert {:deferred, 1} = MultipartCleanup.process(request.id, [@key], empty_inventory_opts)

    assert_received :state_reported_absent_now
    assert Repo.get!(StorageCleanupRequest, request.id).multipart_cleanup_phase == "verify_references"

    assert %StorageCleanupMultipartUpload{last_absent_generation: ^quiet_generation} =
             Repo.get_by!(StorageCleanupMultipartUpload, cleanup_request_id: request.id)

    assert {:deferred, 1} = MultipartCleanup.process(request.id, [@key], empty_inventory_opts)
    assert Repo.get!(StorageCleanupRequest, request.id).multipart_cleanup_phase == "verify_objects"

    assert {:deferred, 1} = MultipartCleanup.process(request.id, [@key], empty_inventory_opts)
    assert Repo.get!(StorageCleanupRequest, request.id).multipart_cleanup_phase == "verify_final_inventory"

    assert :ok = MultipartCleanup.process(request.id, [@key], empty_inventory_opts)

    assert %StorageCleanupRequest{multipart_cleanup_phase: "confirmed"} =
             Repo.get!(StorageCleanupRequest, request.id)
  end

  test "confirmation residue durably reopens delete without mutating the provider in that delivery" do
    request = insert_cleanup_request!()
    test_pid = self()

    initial_opts =
      cleanup_opts(
        list_fun: &empty_inventory/1,
        stat_fun: fn @key ->
          {:ok, %{size: 1, content_type: "application/zip", identity: "initial-object-etag"}}
        end,
        object_delete_fun: fn @key, _identity ->
          send(test_pid, :initial_object_delete)
          :ok
        end
      )

    assert {:deferred, 1} = MultipartCleanup.process(request.id, [@key], initial_opts)

    assert {:deferred, seconds} = MultipartCleanup.process(request.id, [@key], initial_opts)
    assert seconds > 1
    assert_received :initial_object_delete
    expire_quiet_window!(request.id)

    assert {:deferred, 1} = MultipartCleanup.process(request.id, [@key], initial_opts)
    assert Repo.get!(StorageCleanupRequest, request.id).multipart_cleanup_phase == "verify_inventory"

    confirmation_opts =
      cleanup_opts(
        list_fun: &one_upload_inventory/1,
        abort_fun: fn @key, @upload_id ->
          send(test_pid, :unexpected_abort)
          :ok
        end,
        object_delete_fun: fn @key, _identity ->
          send(test_pid, :unexpected_object_delete)
          :ok
        end,
        state_fun: fn @key, @upload_id ->
          send(test_pid, :unexpected_state_probe)
          {:ok, :present}
        end
      )

    assert {:deferred, 1} = MultipartCleanup.process(request.id, [@key], confirmation_opts)
    refute_received :unexpected_abort
    refute_received :unexpected_object_delete
    refute_received :unexpected_state_probe

    assert %StorageCleanupRequest{multipart_cleanup_phase: "abort"} =
             Repo.get!(StorageCleanupRequest, request.id)

    assert %StorageCleanupMultipartUpload{
             storage_key: @key,
             upload_id: @upload_id,
             last_aborted_generation: nil
           } = Repo.get_by!(StorageCleanupMultipartUpload, cleanup_request_id: request.id)
  end

  test "two concurrent workers cannot execute provider I/O under the same claim" do
    request = insert_cleanup_request!()
    parent = self()

    first_opts =
      cleanup_opts(
        list_fun: fn @key ->
          send(parent, {:inventory_started, self()})

          receive do
            :release_inventory -> empty_inventory(@key)
          after
            2_000 -> raise "inventory test barrier timed out"
          end
        end,
        object_delete_fun: fn @key, _identity -> :ok end
      )

    first = Task.async(fn -> MultipartCleanup.process(request.id, [@key], first_opts) end)
    assert_receive {:inventory_started, first_pid}, 1_000

    second_opts =
      cleanup_opts(
        list_fun: fn @key ->
          send(parent, :second_worker_reached_provider)
          empty_inventory(@key)
        end
      )

    second = Task.async(fn -> MultipartCleanup.process(request.id, [@key], second_opts) end)
    assert {:deferred, seconds} = Task.await(second, 1_000)
    assert seconds > 1
    refute_received :second_worker_reached_provider

    send(first_pid, :release_inventory)
    assert {:deferred, 1} = Task.await(first, 1_000)
  end

  test "provider failures expose only bounded codes in logs and telemetry" do
    request = insert_cleanup_request!()
    private_body = "author@example.com/private-response-body"
    private_upload_id = "opaque-upload-secret"
    handler_id = "multipart-cleanup-failure-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        @failure_event,
        fn event, measurements, metadata, _config ->
          send(test_pid, {:failure_metric, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    opts =
      cleanup_opts(
        list_fun: fn @key ->
          {:ok,
           %{
             uploads: [%{key: @key, upload_id: private_upload_id}],
             inventory_complete: true
           }}
        end,
        abort_fun: fn @key, ^private_upload_id ->
          {:error, {:http_error, 500, %{body: private_body, key: @key}}}
        end
      )

    assert {:deferred, 1} = MultipartCleanup.process(request.id, [@key], opts)

    log =
      capture_log([level: :warning], fn ->
        assert {:error, [@key]} = MultipartCleanup.process(request.id, [@key], opts)
      end)

    assert log =~ "phase=abort"
    assert log =~ "code=multipart_abort_provider_error"
    refute log =~ @key
    refute log =~ private_upload_id
    refute log =~ private_body

    assert_received {:failure_metric, @failure_event, %{count: 1}, metadata}
    assert metadata == %{phase: "abort", error_code: "multipart_abort_provider_error"}
    refute inspect(metadata) =~ @key
    refute inspect(metadata) =~ private_upload_id
    refute inspect(metadata) =~ private_body
  end

  test "a confirmed generic receipt is consumed on retry without a new claim" do
    request = insert_cleanup_request!()

    request
    |> StorageCleanupRequest.multipart_cleanup_changeset(%{
      multipart_cleanup_phase: "confirmed",
      multipart_cleanup_inventory_complete: true
    })
    |> Repo.update!()

    assert :ok =
             MultipartCleanup.process(
               request.id,
               [@key],
               cleanup_opts(
                 consume?: true,
                 namespace_fun: fn -> flunk("confirmed consumption must not contact the provider") end
               )
             )

    refute Repo.get(StorageCleanupRequest, request.id)
  end

  test "a confirmed snapshot lifecycle receipt remains durable on retry" do
    request =
      %StorageCleanupRequest{}
      |> StorageCleanupRequest.changeset(%{
        storage_keys: [@key],
        owner_kind: "snapshot_lifecycle",
        owner_token: Ecto.UUID.generate(),
        provider_namespace_fingerprint: @fingerprint,
        multipart_cleanup_phase: "confirmed",
        multipart_cleanup_inventory_complete: true
      })
      |> Repo.insert!()

    assert :ok =
             MultipartCleanup.process(
               request.id,
               [@key],
               cleanup_opts(
                 consume?: true,
                 namespace_fun: fn -> flunk("confirmed snapshot retry must not contact the provider") end
               )
             )

    assert %StorageCleanupRequest{multipart_cleanup_phase: "confirmed"} =
             Repo.get!(StorageCleanupRequest, request.id)
  end

  test "reopen_confirmed rejects a request that has not reached confirmation" do
    request = insert_cleanup_request!()

    assert {:error, :multipart_cleanup_request_not_confirmed} =
             MultipartCleanup.reopen_confirmed(request.id)

    assert %StorageCleanupRequest{multipart_cleanup_phase: "discover"} =
             Repo.get!(StorageCleanupRequest, request.id)
  end

  test "an expired final claim consumes the durable budget and blocks before provider IO" do
    request = insert_cleanup_request!()
    expired_at = TimeHelpers.now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)

    request
    |> StorageCleanupRequest.multipart_cleanup_changeset(%{
      multipart_cleanup_claim_token: Ecto.UUID.generate(),
      multipart_cleanup_claim_expires_at: expired_at,
      multipart_cleanup_failure_count: 11
    })
    |> Repo.update!()

    opts =
      cleanup_opts(
        namespace_fun: fn -> flunk("expired claim must block before provider IO") end,
        list_fun: fn @key -> flunk("expired claim must block before provider IO") end
      )

    assert {:error, [@key]} = MultipartCleanup.process(request.id, [@key], opts)

    assert %StorageCleanupRequest{
             multipart_cleanup_phase: "blocked",
             multipart_cleanup_failure_count: 12,
             multipart_cleanup_last_error_code: "multipart_cleanup_claim_expired",
             multipart_cleanup_claim_token: nil,
             multipart_cleanup_claim_expires_at: nil,
             multipart_cleanup_next_attempt_at: nil
           } = Repo.get!(StorageCleanupRequest, request.id)
  end

  test "conditional object identity drift restarts discovery without deleting replacement bytes" do
    request = request_in_phase!("delete", multipart_cleanup_inventory_complete: true)
    test_pid = self()

    opts =
      cleanup_opts(
        stat_fun: fn @key ->
          {:ok, %{size: 10, content_type: "application/zip", identity: "observed-etag"}}
        end,
        object_delete_fun: fn @key, "observed-etag" ->
          send(test_pid, :conditional_delete_attempted)
          {:error, :object_changed}
        end
      )

    assert {:deferred, 1} = MultipartCleanup.process(request.id, [@key], opts)
    assert_received :conditional_delete_attempted

    assert %StorageCleanupRequest{
             multipart_cleanup_phase: "discover",
             multipart_cleanup_cursor: 0,
             multipart_cleanup_residue_count: 1
           } = Repo.get!(StorageCleanupRequest, request.id)
  end

  test "a retained object must still exist and malformed object metadata fails closed" do
    retained = request_in_phase!("delete", multipart_cleanup_inventory_complete: true)

    assert {:error, [@key]} =
             MultipartCleanup.process(
               retained.id,
               [@key],
               cleanup_opts(object_policy_fun: fn @key -> :retain end)
             )

    assert %StorageCleanupRequest{
             multipart_cleanup_failure_count: 1,
             multipart_cleanup_last_error_code: "retained_object_missing"
           } = Repo.get!(StorageCleanupRequest, retained.id)

    malformed = request_in_phase!("delete", multipart_cleanup_inventory_complete: true)

    assert {:error, [@key]} =
             MultipartCleanup.process(
               malformed.id,
               [@key],
               cleanup_opts(
                 stat_fun: fn @key ->
                   {:ok, %{size: 10, content_type: nil, identity: "opaque-identity"}}
                 end
               )
             )

    assert %StorageCleanupRequest{
             multipart_cleanup_failure_count: 1,
             multipart_cleanup_last_error_code: "invalid_multipart_object_stat_response"
           } = Repo.get!(StorageCleanupRequest, malformed.id)
  end

  test "retaining a present object records a distinct non-PII outcome" do
    request = request_in_phase!("delete", multipart_cleanup_inventory_complete: true)
    handler_id = "multipart-cleanup-retained-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :assets, :multipart_cleanup, :operation],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:operation_metric, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:deferred, seconds} =
             MultipartCleanup.process(
               request.id,
               [@key],
               cleanup_opts(
                 object_policy_fun: fn @key -> :retain end,
                 stat_fun: fn @key ->
                   {:ok, %{size: 10, content_type: "application/zip", identity: "opaque-identity"}}
                 end
               )
             )

    assert seconds > 1

    assert_received {:operation_metric, [:storyarn, :assets, :multipart_cleanup, :operation], %{count: 1},
                     %{phase: "delete", outcome: "object_retained"}}
  end

  defp insert_cleanup_request! do
    %StorageCleanupRequest{}
    |> StorageCleanupRequest.changeset(%{
      storage_keys: [@key],
      provider_namespace_fingerprint: @fingerprint,
      multipart_cleanup_phase: "discover"
    })
    |> Repo.insert!()
  end

  defp request_in_phase!(phase, attrs) do
    request = insert_cleanup_request!()

    attrs =
      attrs
      |> Map.new()
      |> Map.put(:multipart_cleanup_phase, phase)

    request
    |> StorageCleanupRequest.multipart_cleanup_changeset(attrs)
    |> Repo.update!()
  end

  defp cleanup_opts(overrides) do
    defaults = [
      namespace_fun: fn -> {:ok, @fingerprint} end,
      list_fun: &empty_inventory/1,
      abort_fun: fn _key, _upload_id -> :ok end,
      state_fun: fn _key, _upload_id -> {:ok, :absent_now} end,
      object_delete_fun: fn _key, _identity -> :ok end,
      stat_fun: fn _key -> {:error, :enoent} end,
      authorize_fun: fn [@key] -> :ok end
    ]

    Keyword.merge(defaults, overrides)
  end

  defp one_upload_inventory(@key) do
    {:ok,
     %{
       uploads: [%{key: @key, upload_id: @upload_id}],
       inventory_complete: true
     }}
  end

  defp empty_inventory(@key), do: {:ok, %{uploads: [], inventory_complete: true}}

  defp make_due!(request_id) do
    Repo.update_all(from(request in StorageCleanupRequest, where: request.id == ^request_id),
      set: [
        multipart_cleanup_claim_token: nil,
        multipart_cleanup_claim_expires_at: nil,
        multipart_cleanup_next_attempt_at: nil
      ]
    )
  end

  defp expire_quiet_window!(request_id) do
    now = DateTime.truncate(TimeHelpers.now(), :second)
    expired_at = DateTime.add(now, -1, :second)

    Repo.update_all(from(request in StorageCleanupRequest, where: request.id == ^request_id),
      set: [
        multipart_quiescence_started_at: DateTime.add(expired_at, -1, :second),
        multipart_quiescence_not_before: expired_at,
        multipart_cleanup_claim_token: nil,
        multipart_cleanup_claim_expires_at: nil,
        multipart_cleanup_next_attempt_at: nil
      ]
    )
  end
end
