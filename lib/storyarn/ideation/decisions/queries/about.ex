defmodule Storyarn.Ideation.Decisions.Queries.About do
  @moduledoc false
  import Ecto.Query
  import Storyarn.Ideation.Decisions.Rules.Input, only: [valid_id: 1]

  alias Storyarn.Ideation.Decisions.Decision
  alias Storyarn.Ideation.Decisions.Queries.Catalog
  alias Storyarn.Ideation.Decisions.Queries.Targets
  alias Storyarn.Ideation.Decisions.Revision
  alias Storyarn.Ideation.References
  alias Storyarn.Ideation.Sessions
  alias Storyarn.Repo

  @types ~w(sheet flow scene)
  @session_limit 30

  @doc """
  Decisions about a Sheet, Flow or Scene: those whose head or agreement names it
  in Affects, plus every decision of the sessions that explore it. Each session
  is read through its own catalog, so access and source visibility match the
  panel, and a target is matched by its pinned identity, never by a recycled ID.
  """
  def list(scope, project_id, type, id, opts \\ [])

  def list(scope, project_id, type, id, opts) when type in @types and valid_id(id) do
    with {:ok, live} <- Targets.live(scope, project_id, [{type, id}]),
         %{identity: identity} <- live[{type, id}],
         {:ok, explored} <- explored(scope, project_id, type, id, Keyword.get(opts, :explored, true)) do
      named = named(type, id, identity)
      sessions = named |> Map.keys() |> Enum.concat(explored) |> Enum.uniq() |> Enum.take(@session_limit)
      {:ok, Enum.flat_map(sessions, &session_decisions(scope, project_id, &1, named, explored, {type, id}))}
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def list(_, _, _, _, _), do: {:error, :not_found}

  # Only decisions that name the content, for quick lookups such as the palette.
  defp explored(_scope, _project_id, _type, _id, false), do: {:ok, []}

  defp explored(scope, project_id, type, id, true) do
    with {:ok, context} <- References.contextual(scope, project_id, type, id, limit: @session_limit),
         do: {:ok, Enum.map(context.linked_sessions, & &1.id)}
  end

  defp session_decisions(scope, project_id, session_id, named, explored, target) do
    with {:ok, session} <- Sessions.get_session(scope, project_id, session_id),
         {:ok, decisions} <- Catalog.list(scope, project_id, session_id) do
      wanted = Map.get(named, session_id, [])

      for decision <- decisions, session_id in explored or decision.id in wanted do
        %{
          decision: decision,
          session: %{id: session.id, title: session.title, status: session.status},
          target_key: target_key(decision, target)
        }
      end
    else
      {:error, _} -> []
    end
  end

  # Head and agreement revisions that pin this target, grouped by session.
  defp named(type, id, identity) do
    pinned = %{"items" => [%{"type" => type, "id" => id, "identity" => identity}]}

    from(r in Revision,
      join: d in Decision,
      on: d.id == r.decision_id and (r.number == d.version or r.number == d.accepted_version),
      where: fragment("? @> ?", r.targets, ^pinned),
      distinct: true,
      select: {d.session_id, d.id}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  # The key of this content in the decision as shown: its agreement when one is
  # in force, otherwise its proposal.
  defp target_key(decision, {type, id}) do
    revision = decision.accepted || decision.proposal

    Enum.find_value(revision.targets, fn target ->
      if target.type == type and target.id == id and target.available, do: target.key
    end)
  end
end
