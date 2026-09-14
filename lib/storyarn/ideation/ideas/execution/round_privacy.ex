defmodule Storyarn.Ideation.Ideas.Execution.RoundPrivacy do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Ideas.Execution.Publication
  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Ideas.Reveal
  alias Storyarn.Ideation.Sessions
  alias Storyarn.Repo

  # Sessions flips the round; when that ends its private mask, the round's
  # consenting contributions are published here, under the same lock.
  def set_locked(access, revision, round_id, attrs) do
    with {:ok, result} <- Sessions.set_round_privacy_locked(access, revision, round_id, attrs) do
      if result.revealed, do: reveal_round(access, round_id)
      {:ok, result}
    end
  end

  defp reveal_round(access, round_id) do
    # The manual control and a scheduled expiry share exactly this publication
    # policy. The caller owns the session lock, transaction and postcommit signal.
    ideas =
      Repo.all(
        from i in Idea,
          where:
            i.session_id == ^access.session_id and i.round_id == ^round_id and is_nil(i.deleted_at) and
              not is_nil(i.author_id) and i.publication_consent == :facilitator_assisted and
              i.state != :discarded and (is_nil(i.published_revision) or i.revision > i.published_revision)
      )

    Enum.each(Enum.chunk_every(ideas, 200), fn batch ->
      operation =
        Repo.insert!(%Reveal{
          session_id: access.session_id,
          actor_id: access.user_id,
          request_key: Ecto.UUID.generate(),
          selection: %{"mode" => "round", "round_id" => round_id},
          manifest: Enum.map(batch, &%{"idea_id" => &1.id, "revision" => &1.revision})
        })

      Publication.publish(operation, batch, access.user_id)
    end)
  end
end
