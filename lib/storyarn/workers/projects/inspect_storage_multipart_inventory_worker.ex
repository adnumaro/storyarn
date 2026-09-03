defmodule Storyarn.Workers.InspectStorageMultipartInventoryWorker do
  @moduledoc """
  Periodically records bounded, read-only multipart inventory evidence.

  This worker never aborts uploads. Remediation remains behind exact-key,
  durable Project cleanup ownership.
  """

  use Oban.Worker,
    queue: :storage_inventory,
    priority: 3,
    max_attempts: 3,
    unique: [
      period: 29 * 60,
      fields: [:worker, :args],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Storyarn.Projects

  require Logger

  @timeout_ms to_timeout(minute: 10)
  @non_retryable_failures [:inventory_limit_exceeded, :unsupported, :invalid_response]

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    enabled? =
      :storyarn
      |> Application.fetch_env!(:operational_metrics)
      |> Keyword.fetch!(:enabled)

    perform_configured(job, enabled?, &Projects.inspect_storage_multipart_inventory/0)
  end

  @doc false
  def perform_configured(%Oban.Job{} = job, true, inspect_inventory) when is_function(inspect_inventory, 0),
    do: perform_inventory(job, inspect_inventory)

  def perform_configured(%Oban.Job{}, false, inspect_inventory) when is_function(inspect_inventory, 0), do: :ok

  @doc false
  def perform_inventory(%Oban.Job{}, inspect_inventory) when is_function(inspect_inventory, 0) do
    case safe_inspect(inspect_inventory) do
      :ok -> :ok
      {:error, failure} when failure in @non_retryable_failures -> :ok
      _failure -> {:error, :storage_multipart_inventory_failed}
    end
  end

  defp safe_inspect(inspect_inventory) do
    inspect_inventory.()
  rescue
    exception ->
      Logger.error(
        "Storage multipart inventory worker failed failure=exception " <>
          "exception_module=#{inspect(exception.__struct__)}"
      )

      {:error, :storage_multipart_inventory_failed}
  catch
    kind, _reason when kind in [:exit, :throw] ->
      Logger.error("Storage multipart inventory worker failed failure=#{kind}")
      {:error, :storage_multipart_inventory_failed}
  end

  @impl Oban.Worker
  def timeout(_job), do: @timeout_ms
end
