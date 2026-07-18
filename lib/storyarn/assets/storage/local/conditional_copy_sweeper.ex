defmodule Storyarn.Assets.Storage.Local.ConditionalCopySweeper do
  @moduledoc false

  use GenServer

  alias Storyarn.Assets.Storage.Local

  require Logger

  @default_interval_ms to_timeout(minute: 15)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    interval_ms =
      opts
      |> Keyword.get(:interval_ms, configured_interval_ms())
      |> normalize_interval()

    send(self(), :sweep)
    {:ok, interval_ms}
  end

  @impl true
  def handle_info(:sweep, interval_ms) do
    if local_storage?() do
      case Local.cleanup_stale_conditional_copies() do
        :ok ->
          :ok

        {:error, failures} ->
          Logger.warning("Could not remove stale local conditional-copy files failed_count=#{length(failures)}")
      end
    end

    Process.send_after(self(), :sweep, interval_ms)
    {:noreply, interval_ms}
  end

  defp local_storage? do
    :storyarn
    |> Application.get_env(:storage, [])
    |> Keyword.get(:adapter, :local)
    |> Kernel.==(:local)
  end

  defp configured_interval_ms do
    :storyarn
    |> Application.get_env(:storage, [])
    |> Keyword.get(:conditional_copy_sweep_interval_ms, @default_interval_ms)
  end

  defp normalize_interval(interval_ms) when is_integer(interval_ms) and interval_ms > 0, do: interval_ms

  defp normalize_interval(_interval_ms), do: @default_interval_ms
end
