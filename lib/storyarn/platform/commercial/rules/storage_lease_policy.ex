defmodule Storyarn.Platform.Billing.StorageLeasePolicy do
  @moduledoc """
  Runtime policy for capacity reservations and snapshot storage leases.

  Platform owns the reservation lifecycle. Projects consumes these values when
  it grants downloads or heartbeats snapshot publication, so both sides share
  one public policy without Platform depending on Project internals.
  """

  @default_download_signed_url_ttl_seconds 5 * 60
  @max_download_signed_url_ttl_seconds 5 * 60
  @default_download_max_transfer_seconds 60 * 60
  @default_download_lease_safety_seconds 60
  @default_build_heartbeat_interval_seconds 60
  @default_build_lease_ttl_seconds 5 * 60
  @default_export_lease_retention_seconds 7 * 24 * 60 * 60

  @spec download_signed_url_ttl_seconds() :: pos_integer()
  def download_signed_url_ttl_seconds do
    :download_signed_url_ttl_seconds
    |> positive_config(@default_download_signed_url_ttl_seconds)
    |> validate_download_signed_url_ttl!()
  end

  @spec download_max_transfer_seconds() :: pos_integer()
  def download_max_transfer_seconds do
    positive_config(:download_max_transfer_seconds, @default_download_max_transfer_seconds)
  end

  @spec download_export_lease_ttl_seconds() :: pos_integer()
  def download_export_lease_ttl_seconds do
    download_signed_url_ttl_seconds() + download_max_transfer_seconds() +
      positive_config(:download_lease_safety_seconds, @default_download_lease_safety_seconds)
  end

  @spec build_heartbeat_interval_ms() :: pos_integer()
  def build_heartbeat_interval_ms do
    positive_config(:build_heartbeat_interval_seconds, @default_build_heartbeat_interval_seconds) * 1_000
  end

  @spec build_lease_ttl_seconds() :: pos_integer()
  def build_lease_ttl_seconds do
    heartbeat_seconds = div(build_heartbeat_interval_ms(), 1_000)

    :build_lease_ttl_seconds
    |> positive_config(@default_build_lease_ttl_seconds)
    |> validate_build_lease_ttl!(heartbeat_seconds)
  end

  @spec export_lease_retention_seconds() :: pos_integer()
  def export_lease_retention_seconds do
    positive_config(:export_lease_retention_seconds, @default_export_lease_retention_seconds)
  end

  defp positive_config(key, default) do
    case Keyword.get(config(), key, default) do
      value when is_integer(value) and value > 0 ->
        value

      invalid ->
        raise ArgumentError, "invalid storage lease policy #{key}: #{inspect(invalid)}"
    end
  end

  defp validate_build_lease_ttl!(ttl_seconds, heartbeat_seconds) when ttl_seconds >= 3 * heartbeat_seconds,
    do: ttl_seconds

  defp validate_build_lease_ttl!(ttl_seconds, heartbeat_seconds) do
    raise ArgumentError,
          "snapshot build lease TTL must cover at least three heartbeat intervals, " <>
            "got ttl=#{ttl_seconds}s heartbeat=#{heartbeat_seconds}s"
  end

  defp validate_download_signed_url_ttl!(ttl_seconds) when ttl_seconds <= @max_download_signed_url_ttl_seconds,
    do: ttl_seconds

  defp validate_download_signed_url_ttl!(ttl_seconds) do
    raise ArgumentError,
          "snapshot signed URL TTL must be at most " <>
            "#{@max_download_signed_url_ttl_seconds}s, got #{ttl_seconds}s"
  end

  defp config do
    case Application.get_env(:storyarn, __MODULE__, []) do
      configured when is_list(configured) -> configured
      invalid -> raise ArgumentError, "invalid storage lease policy: #{inspect(invalid)}"
    end
  end
end
