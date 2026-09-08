defmodule Storyarn.Ideation.Recovery.TimerState do
  @moduledoc false

  @outcomes ~w(completed skipped_authorization skipped_configuration skipped_session)

  # Recovery never executes the source session's scheduled actions. This pure
  # transformation preserves stable generation matching and canonical digests;
  # resuming requires a new, authorized command with a new deadline.
  def restore(%{status: "running"} = row), do: %{row | status: "paused", deadline_at: nil, version: row.version + 1}

  def restore(row), do: row

  def valid?(row) do
    snapshot_valid?(row) and positive?(row["configuration_version"]) and row["configuration_version"] <= 2_147_483_647 and
      valid_time?(row["started_at"]) and timing_valid?(row)
  end

  def snapshot_valid?(row) when is_map(row) do
    positive?(row["version"]) and row["version"] < 9_223_372_036_854_775_807 and
      is_boolean(row["reveal_on_expiry"]) and is_boolean(row["close_contributions_on_expiry"]) and
      duration_valid?(row) and status_valid?(row)
  end

  def snapshot_valid?(_), do: false

  defp duration_valid?(row) do
    is_integer(row["duration_seconds"]) and row["duration_seconds"] in 15..86_400 and
      is_integer(row["remaining_seconds"]) and row["remaining_seconds"] >= 0 and
      row["remaining_seconds"] <= row["duration_seconds"]
  end

  defp status_valid?(%{"status" => status, "remaining_seconds" => remaining, "expiry_outcome" => nil})
       when status in ~w(running paused), do: remaining > 0

  defp status_valid?(%{"status" => "elapsed", "remaining_seconds" => 0, "expiry_outcome" => outcome}),
    do: outcome in @outcomes

  defp status_valid?(%{"status" => "cancelled", "remaining_seconds" => 0, "expiry_outcome" => nil}), do: true
  defp status_valid?(_), do: false

  defp timing_valid?(%{"status" => "running", "deadline_at" => deadline, "completed_at" => nil}),
    do: valid_time?(deadline)

  defp timing_valid?(%{"status" => "paused", "deadline_at" => nil, "completed_at" => nil}), do: true

  defp timing_valid?(%{"status" => status, "deadline_at" => nil, "started_at" => started, "completed_at" => completed})
       when status in ~w(elapsed cancelled) do
    with {:ok, first} <- parse_time(started),
         {:ok, last} <- parse_time(completed) do
      NaiveDateTime.compare(last, first) != :lt
    else
      _ -> false
    end
  end

  defp timing_valid?(_), do: false
  defp positive?(value), do: is_integer(value) and value > 0
  defp valid_time?(value), do: match?({:ok, _}, parse_time(value))
  defp parse_time(value) when is_binary(value), do: NaiveDateTime.from_iso8601(value)
  defp parse_time(_), do: :error
end
