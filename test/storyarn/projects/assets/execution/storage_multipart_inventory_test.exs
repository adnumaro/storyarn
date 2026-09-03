defmodule Storyarn.Projects.Assets.StorageMultipartInventoryTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Storyarn.MultipartInventoryStorageSpy
  alias Storyarn.Projects.Assets.StorageMultipartInventory

  @event [:storyarn, :storage, :multipart_inventory, :snapshot]
  @now ~U[2026-09-02 12:00:00Z]

  setup do
    test_pid = self()
    handler_id = "storage-multipart-inventory-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        @event,
        fn event, measurements, metadata, _config ->
          send(test_pid, {:multipart_inventory_metric, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  test "emits one complete low-cardinality inventory for the provider namespace" do
    put_summary(
      :all,
      {:ok,
       %{
         count: 2,
         oldest_initiated_at: ~U[2026-09-01 12:00:00Z],
         inventory_complete: true
       }}
    )

    assert :ok = StorageMultipartInventory.inspect_with(MultipartInventoryStorageSpy, @now)

    assert_received {:multipart_summary_requested, :all, [max_uploads: 10_000]}

    assert_received {:multipart_inventory_metric, @event,
                     %{
                       count: 2,
                       oldest_age_seconds: 86_400,
                       inventory_complete: 1,
                       failure_count: 0,
                       observed_at_unix_seconds: 1_788_350_400
                     }, %{failure: :none}}
  end

  test "reports bounded incompleteness without exposing provider object identity" do
    put_summary(
      :all,
      {:ok,
       %{
         count: 10_000,
         oldest_initiated_at: ~U[2026-08-01 12:00:00Z],
         inventory_complete: false
       }}
    )

    assert {:error, :inventory_limit_exceeded} =
             StorageMultipartInventory.inspect_with(MultipartInventoryStorageSpy, @now)

    assert_received {:multipart_inventory_metric, @event,
                     %{
                       count: 10_000,
                       oldest_age_seconds: 2_764_800,
                       inventory_complete: 0,
                       failure_count: 1,
                       observed_at_unix_seconds: 1_788_350_400
                     }, %{failure: :inventory_limit_exceeded}}
  end

  test "collapses provider errors and exceptions before metrics or return values" do
    private_value = "author@example.com/private/object.zip?signature=secret"
    put_summary(:all, {:raise, RuntimeError.exception(private_value)})

    {result, log} =
      with_log(fn -> StorageMultipartInventory.inspect_with(MultipartInventoryStorageSpy, @now) end)

    assert result == {:error, :exception}
    refute inspect(result) =~ private_value
    assert log =~ "failure=exception"
    assert log =~ "exception_module=RuntimeError"
    refute log =~ private_value

    assert_received {:multipart_inventory_metric, @event, measurements, %{failure: :exception}}

    assert measurements == %{
             count: 0,
             oldest_age_seconds: 0,
             inventory_complete: 0,
             failure_count: 1,
             observed_at_unix_seconds: 1_788_350_400
           }

    refute inspect(measurements) =~ private_value
  end

  test "collapses returned provider details into a fixed failure classification" do
    private_value = "author@example.com/private/object.zip?signature=secret"
    put_summary(:all, {:error, {:http_error, 500, %{body: private_value}}})

    {result, log} =
      with_log(fn -> StorageMultipartInventory.inspect_with(MultipartInventoryStorageSpy, @now) end)

    assert result == {:error, :provider_error}
    refute inspect(result) =~ private_value
    refute log =~ private_value

    assert_received {:multipart_inventory_metric, @event, measurements, %{failure: :provider_error}}
    assert measurements.failure_count == 1
    assert measurements.inventory_complete == 0
    refute inspect(measurements) =~ private_value
  end

  defp put_summary(prefix, result) do
    Process.put({MultipartInventoryStorageSpy, prefix}, result)
  end
end
