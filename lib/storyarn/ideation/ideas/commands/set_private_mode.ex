defmodule Storyarn.Ideation.Ideas.Commands.SetPrivateMode do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Ideas.Execution.Publication
  alias Storyarn.Ideation.Ideas.Execution.Transaction
  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Ideas.Reveal
  alias Storyarn.Ideation.Sessions
  alias Storyarn.Repo

  def run(scope, project_id, session_id, revision, enabled) when is_boolean(enabled) do
    result =
      Transaction.run(scope, project_id, session_id, &set_locked(&1, revision, enabled))

    Sessions.notify_canvas_mode(result, project_id)
  end

  def run(_, _, _, _, _), do: {:error, :invalid_parameters}

  defp set_locked(access, revision, enabled) do
    with {:ok, result} <- Sessions.set_canvas_mode_locked(access, revision, enabled) do
      if result.changed and not enabled, do: reveal_session(access)
      Transaction.success(%{id: access.session_id, private_mode: enabled}, [:shared])
    end
  end

  defp reveal_session(access) do
    # One session lock freezes the heads and mode change. Later saves follow the
    # new mode. Ending private work never broadens legacy consent or explicitly
    # selects discarded ideas for publication.
    ideas =
      Repo.all(
        from i in Idea,
          where:
            i.session_id == ^access.session_id and is_nil(i.deleted_at) and not is_nil(i.author_id) and
              i.publication_consent == :facilitator_assisted and i.state != :discarded and
              (is_nil(i.published_revision) or i.revision > i.published_revision)
      )

    Enum.each(Enum.chunk_every(ideas, 200), fn batch ->
      operation =
        Repo.insert!(%Reveal{
          session_id: access.session_id,
          actor_id: access.user_id,
          request_key: Ecto.UUID.generate(),
          selection: %{"mode" => "session"},
          manifest: Enum.map(batch, &%{"idea_id" => &1.id, "revision" => &1.revision})
        })

      Publication.publish(operation, batch, access.user_id)
    end)
  end
end
