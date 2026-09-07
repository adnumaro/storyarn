defmodule Storyarn.Ideation.Ideas.Execution.Publication do
  @moduledoc false
  import Ecto.Changeset

  alias Storyarn.Ideation.Ideas.Publication
  alias Storyarn.Ideation.Ideas.Reveal
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  def publish(operation, ideas, actor_id) do
    changed? =
      Enum.reduce(ideas, false, fn idea, changed? ->
        if idea.published_revision == idea.revision do
          changed?
        else
          Repo.insert!(%Publication{
            idea_id: idea.id,
            revision: idea.revision,
            operation_id: operation.id,
            actor_id: actor_id
          })

          idea |> change(published_revision: idea.revision) |> Repo.update!()
          true
        end
      end)

    completed = operation |> change(status: :completed, completed_at: TimeHelpers.now()) |> Repo.update!()
    {completed, changed?}
  end

  def publish_creation(idea, actor_id) do
    operation =
      Repo.insert!(%Reveal{
        session_id: idea.session_id,
        actor_id: actor_id,
        request_key: Ecto.UUID.generate(),
        selection: %{"mode" => "creation"},
        manifest: [%{"idea_id" => idea.id, "revision" => idea.revision}]
      })

    publish(operation, [idea], actor_id)
    %{idea | published_revision: idea.revision}
  end
end
