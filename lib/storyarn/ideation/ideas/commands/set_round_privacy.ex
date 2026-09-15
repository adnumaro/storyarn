defmodule Storyarn.Ideation.Ideas.Commands.SetRoundPrivacy do
  @moduledoc false
  alias Storyarn.Ideation.Ideas.Execution.RoundPrivacy
  alias Storyarn.Ideation.Ideas.Execution.Transaction
  alias Storyarn.Ideation.Sessions
  alias Storyarn.Platform.Kernel.MapAccess

  # `private: false` on a private round is the reveal: it publishes the round's
  # consenting contributions atomically with the change.
  def run(scope, project_id, session_id, round_id, revision, attrs) when is_map(attrs) do
    result =
      Transaction.run(
        scope,
        project_id,
        session_id,
        &set_locked(&1, revision, round_id, MapAccess.stringify_keys(attrs))
      )

    Sessions.notify_round_privacy(result, project_id)
  end

  def run(_, _, _, _, _, _), do: {:error, :invalid_parameters}

  defp set_locked(access, revision, round_id, attrs) do
    with {:ok, result} <- RoundPrivacy.set_locked(access, revision, round_id, attrs) do
      audiences = if result.changed, do: [:shared, :comment_sources], else: []

      Transaction.success(
        %{
          id: access.session_id,
          round_id: result.id,
          private: result.round.private,
          reveal_on_expiry: result.round.reveal_on_expiry,
          revealed_at: result.round.revealed_at
        },
        audiences
      )
    end
  end
end
