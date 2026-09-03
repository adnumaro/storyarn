defmodule Storyarn.Projects.Assets.StorageMultipartInventory do
  @moduledoc """
  Emits bounded, read-only operational evidence for incomplete multipart uploads.

  The provider mechanism returns only aggregate inventory. This Project-owned
  operation scans the complete configured provider namespace and emits no
  storage keys, upload identifiers, bucket names, filenames, or provider
  errors.
  """

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Assets.Storage

  require Logger

  @event [:storyarn, :storage, :multipart_inventory, :snapshot]
  @max_uploads 10_000

  @type failure ::
          :inventory_limit_exceeded
          | :unsupported
          | :invalid_response
          | :provider_error
          | :exception
          | :exit
          | :throw

  @doc false
  @spec inspect() :: :ok | {:error, failure()}
  def inspect do
    inspect_with(Storage, TimeHelpers.now())
  end

  @doc false
  @spec inspect_with(module(), DateTime.t()) :: :ok | {:error, failure()}
  def inspect_with(storage, %DateTime{} = now) when is_atom(storage) do
    storage
    |> safe_summary()
    |> normalize_summary(now)
    |> emit(DateTime.to_unix(now))
  end

  defp safe_summary(storage) do
    storage.incomplete_multipart_upload_summary(:all, max_uploads: @max_uploads)
  rescue
    exception ->
      Logger.error(
        "Storage multipart inventory failed failure=exception " <>
          "exception_module=#{inspect(exception.__struct__)}"
      )

      {:failure, :exception}
  catch
    kind, _reason when kind in [:exit, :throw] ->
      Logger.error("Storage multipart inventory failed failure=#{kind}")
      {:failure, kind}
  end

  defp normalize_summary({:ok, %{count: count, oldest_initiated_at: oldest, inventory_complete: inventory_complete}}, now)
       when is_integer(count) and count >= 0 and is_boolean(inventory_complete) do
    case validate_oldest(count, oldest) do
      :ok ->
        result = %{
          count: count,
          oldest_age_seconds: oldest_age_seconds(oldest, now),
          inventory_complete: boolean_measurement(inventory_complete)
        }

        if inventory_complete,
          do: {:ok, result},
          else: {:failure, :inventory_limit_exceeded, result}

      :error ->
        {:failure, :invalid_response}
    end
  end

  defp normalize_summary({:error, :multipart_inventory_not_supported}, _now), do: {:failure, :unsupported}

  defp normalize_summary({:error, reason}, _now)
       when reason in [
              :invalid_multipart_cleanup_response,
              :invalid_multipart_cleanup_cursor,
              :invalid_multipart_cleanup_limit,
              :invalid_multipart_inventory_limit,
              :invalid_multipart_inventory_request,
              :invalid_multipart_inventory_response
            ], do: {:failure, :invalid_response}

  defp normalize_summary({:failure, failure}, _now) when failure in [:exception, :exit, :throw], do: {:failure, failure}

  defp normalize_summary(_provider_result, _now), do: {:failure, :provider_error}

  defp validate_oldest(0, nil), do: :ok
  defp validate_oldest(count, %DateTime{}) when count > 0, do: :ok
  defp validate_oldest(_count, _oldest), do: :error

  defp oldest_age_seconds(nil, _now), do: 0
  defp oldest_age_seconds(oldest, now), do: max(DateTime.diff(now, oldest, :second), 0)

  defp boolean_measurement(true), do: 1
  defp boolean_measurement(false), do: 0

  defp emit({:ok, result}, observed_at) do
    :telemetry.execute(
      @event,
      result
      |> Map.put(:failure_count, 0)
      |> Map.put(:observed_at_unix_seconds, observed_at),
      %{failure: :none}
    )

    :ok
  end

  defp emit({:failure, failure, result}, observed_at) do
    :telemetry.execute(
      @event,
      result
      |> Map.put(:failure_count, 1)
      |> Map.put(:observed_at_unix_seconds, observed_at),
      %{failure: failure}
    )

    {:error, failure}
  end

  defp emit({:failure, failure}, observed_at) do
    :telemetry.execute(
      @event,
      %{
        count: 0,
        oldest_age_seconds: 0,
        inventory_complete: 0,
        failure_count: 1,
        observed_at_unix_seconds: observed_at
      },
      %{failure: failure}
    )

    {:error, failure}
  end
end
