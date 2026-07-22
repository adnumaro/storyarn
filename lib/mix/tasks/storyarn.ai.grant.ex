defmodule Mix.Tasks.Storyarn.Ai.Grant do
  @shortdoc "Issues an idempotent promotional Storyarn AI allowance grant"
  @moduledoc """
  Issues an internal beta allowance grant. This task does not create a payment,
  commercial balance, invoice, subscription, or top-up.

      mix storyarn.ai.grant --workspace-id 123 --actor-id 456 --units 100 \
        --key invited-beta-2026-07 --kind one_time --expires-at 2026-08-31T23:59:59Z
  """

  use Mix.Task

  alias Storyarn.AI.Allowance

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, positional} =
      OptionParser.parse!(args,
        strict: [
          workspace_id: :integer,
          actor_id: :integer,
          units: :integer,
          key: :string,
          kind: :string,
          expires_at: :string
        ]
      )

    if positional != [], do: usage!()

    workspace_id = required!(opts, :workspace_id)
    actor_id = required!(opts, :actor_id)
    units = required!(opts, :units)
    grant_key = required!(opts, :key)
    kind = Keyword.get(opts, :kind, "one_time")
    expires_at = parse_datetime(Keyword.get(opts, :expires_at))

    case Allowance.grant(workspace_id, actor_id, %{
           grant_key: grant_key,
           kind: kind,
           units: units,
           expires_at: expires_at,
           metadata: %{"source" => "operator_mix_task"}
         }) do
      {:ok, grant} ->
        Mix.shell().info(
          "Grant ##{grant.id} is active for workspace ##{workspace_id}: #{grant.remaining_units} allowance units"
        )

      {:error, reason} ->
        Mix.raise("Could not issue Storyarn AI allowance: #{inspect(reason)}")
    end
  end

  defp required!(opts, key), do: Keyword.get(opts, key) || usage!()

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _invalid -> Mix.raise("--expires-at must be an ISO 8601 UTC datetime")
    end
  end

  defp usage! do
    Mix.raise(
      "Usage: mix storyarn.ai.grant --workspace-id ID --actor-id ID --units N --key KEY [--kind one_time|periodic|adjustment] [--expires-at ISO8601]"
    )
  end
end
