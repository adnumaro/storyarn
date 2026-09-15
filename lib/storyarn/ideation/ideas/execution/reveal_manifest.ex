defmodule Storyarn.Ideation.Ideas.Execution.RevealManifest do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Ideas.Rules.Policy
  alias Storyarn.Ideation.Sessions
  alias Storyarn.Repo

  def capture(%{"mode" => "eligible"} = selection, access) do
    if Policy.manager?(access) do
      states = Map.get(selection, "states", ~w(active parked discarded))
      ideas = Repo.all(eligible(access.session_id, states))

      if length(ideas) > 200,
        do: {:error, :selection_too_large},
        else: {:ok, Enum.map(ideas, &%{"idea_id" => &1.id, "revision" => &1.revision})}
    else
      {:error, :unauthorized}
    end
  end

  def capture(%{"mode" => "selected", "targets" => targets}, access) do
    with {:ok, _ideas} <- validate(targets, access), do: {:ok, targets}
  end

  # Consenting notes with something unpublished, outside any round still private.
  defp eligible(session_id, states) do
    from i in Idea,
      left_join: mask in subquery(Sessions.round_mask_query()),
      on: mask.id == i.round_id,
      where:
        i.session_id == ^session_id and is_nil(i.deleted_at) and i.state in ^states and
          not fragment("COALESCE(?, false)", mask.private) and
          not is_nil(i.author_id) and
          i.publication_consent == :facilitator_assisted and
          (is_nil(i.published_revision) or i.revision > i.published_revision),
      order_by: [asc: i.id],
      limit: 201
  end

  def validate(manifest, access) do
    ids = Enum.map(manifest, & &1["idea_id"])

    ideas =
      Repo.all(
        from i in Idea,
          left_join: mask in subquery(Sessions.round_mask_query()),
          on: mask.id == i.round_id,
          where:
            i.session_id == ^access.session_id and is_nil(i.deleted_at) and i.id in ^ids and
              not fragment("COALESCE(?, false)", mask.private),
          order_by: [asc: i.id]
      )

    by_id = Map.new(ideas, &{&1.id, &1})

    Enum.reduce_while(manifest, {:ok, []}, fn target, {:ok, accepted} ->
      case Map.get(by_id, target["idea_id"]) do
        nil -> {:halt, {:error, :not_found}}
        idea -> validate_target(idea, target, access, accepted)
      end
    end)
  end

  defp validate_target(idea, target, access, accepted) do
    cond do
      not Policy.can_publish?(idea, access) -> {:halt, {:error, :not_found}}
      idea.revision != target["revision"] -> {:halt, {:error, :stale_reveal}}
      true -> {:cont, {:ok, [idea | accepted]}}
    end
  end
end
