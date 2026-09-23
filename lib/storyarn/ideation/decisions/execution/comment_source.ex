defmodule Storyarn.Ideation.Decisions.Execution.CommentSource do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Decisions.Decision
  alias Storyarn.Ideation.Sessions
  alias Storyarn.Repo

  defguardp valid_id?(id) when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807

  def get(%{user: %{id: _}} = scope, project_id, session_id, decision_id, opts)
      when valid_id?(project_id) and valid_id?(session_id) and valid_id?(decision_id) do
    case Sessions.comment_source(scope, project_id, session_id, opts) do
      {:ok, _session} -> source(session_id, decision_id, opts)
      _ -> {:error, :not_found}
    end
  end

  def get(_, _, _, _, _), do: {:error, :not_found}

  # A decision is never deleted and every project reader sees it, so its
  # discussion lives as long as its session.
  defp source(session_id, decision_id, opts) do
    query = from(d in Decision, where: d.id == ^decision_id and d.session_id == ^session_id)
    query = if opts[:lock] == :share, do: from(d in query, lock: "FOR SHARE"), else: query

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      decision ->
        {:ok,
         %{
           id: decision.id,
           name: "Decision ##{decision.id}",
           recovery_identity: decision.recovery_identity,
           inserted_at: DateTime.truncate(decision.inserted_at, :second)
         }}
    end
  end
end
