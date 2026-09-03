defmodule Storyarn.Workers.InspectStorageMultipartInventoryWorkerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Oban.Plugins.Cron
  alias Storyarn.Workers.InspectStorageMultipartInventoryWorker

  test "runs the read-only inspection through the Projects facade callback" do
    assert :ok =
             InspectStorageMultipartInventoryWorker.perform_inventory(
               %Oban.Job{},
               fn -> :ok end
             )
  end

  test "does not call provider inventory when operational metrics are disabled" do
    test_pid = self()

    assert :ok =
             InspectStorageMultipartInventoryWorker.perform_configured(
               %Oban.Job{},
               false,
               fn -> send(test_pid, :provider_called) end
             )

    refute_receive :provider_called
  end

  test "calls provider inventory only after the operational metrics opt-in" do
    test_pid = self()

    assert :ok =
             InspectStorageMultipartInventoryWorker.perform_configured(
               %Oban.Job{},
               true,
               fn ->
                 send(test_pid, :provider_called)
                 :ok
               end
             )

    assert_receive :provider_called
  end

  test "collapses failures before returning them to Oban" do
    private_value = "author@example.com/private/object.zip?signature=secret"

    {result, log} =
      with_log(fn ->
        InspectStorageMultipartInventoryWorker.perform_inventory(
          %Oban.Job{},
          fn -> raise private_value end
        )
      end)

    assert result == {:error, :storage_multipart_inventory_failed}
    refute inspect(result) =~ private_value
    assert log =~ "failure=exception"
    assert log =~ "exception_module=RuntimeError"
    refute log =~ private_value
  end

  test "does not retry deterministic inventory observations" do
    for failure <- [:inventory_limit_exceeded, :unsupported, :invalid_response] do
      assert :ok =
               InspectStorageMultipartInventoryWorker.perform_inventory(
                 %Oban.Job{},
                 fn -> {:error, failure} end
               )
    end
  end

  test "retries only aggregate-safe transient inventory failures" do
    for failure <- [:provider_error, :exception, :exit, :throw] do
      assert {:error, :storage_multipart_inventory_failed} =
               InspectStorageMultipartInventoryWorker.perform_inventory(
                 %Oban.Job{},
                 fn -> {:error, failure} end
               )
    end
  end

  test "is scheduled at the bounded thirty-minute operational cadence" do
    crontab =
      :storyarn
      |> Application.fetch_env!(Oban)
      |> Keyword.fetch!(:plugins)
      |> Enum.find_value(fn
        {Cron, opts} -> Keyword.fetch!(opts, :crontab)
        _other -> nil
      end)

    assert {"*/30 * * * *", InspectStorageMultipartInventoryWorker} in crontab
  end

  test "runs on a dedicated single-capacity queue" do
    queues =
      :storyarn
      |> Application.fetch_env!(Oban)
      |> Keyword.fetch!(:queues)

    assert Keyword.fetch!(queues, :storage_inventory) == 1
    assert Keyword.fetch!(InspectStorageMultipartInventoryWorker.__opts__(), :queue) == :storage_inventory
  end

  test "bounds each dedicated inventory execution" do
    assert InspectStorageMultipartInventoryWorker.timeout(%Oban.Job{}) == to_timeout(minute: 10)
  end
end
