defmodule Storyarn.Ideation.Decisions.Queries.Catalog do
  @moduledoc false
  import Ecto.Query
  import Storyarn.Ideation.Decisions.Rules.Input, only: [valid_id: 1]

  alias Storyarn.Ideation.Decisions.Decision
  alias Storyarn.Ideation.Decisions.Queries.Access
  alias Storyarn.Ideation.Decisions.Queries.Sources
  alias Storyarn.Ideation.Decisions.Revision
  alias Storyarn.Ideation.Decisions.Rules.Input
  alias Storyarn.Ideation.Decisions.View
  alias Storyarn.Repo

  def list(scope, project_id, session_id, opts) do
    with {:ok, _} <- Access.read(scope, project_id, session_id),
         {:ok, page} <- Input.page(opts) do
      query = from d in Decision, where: d.session_id == ^session_id
      query = if page.before_id, do: where(query, [d], d.id < ^page.before_id), else: query
      rows = Repo.all(from d in query, order_by: [desc: d.id], limit: ^(page.limit + 1))
      selected = Enum.take(rows, page.limit)
      revisions = current_revisions(selected)
      sources = Sources.current(session_id, source_items(revisions))

      with {:ok, access} <- Access.read(scope, project_id, session_id) do
        {:ok,
         %{
           decisions: Enum.map(selected, &project(&1, revisions, access, sources)),
           next_cursor: if(length(rows) > page.limit, do: List.last(selected).id)
         }}
      end
    end
  end

  def get(scope, project_id, session_id, id) when valid_id(id) do
    with {:ok, _} <- Access.read(scope, project_id, session_id),
         %Decision{} = decision <- Repo.get_by(Decision, id: id, session_id: session_id) do
      revisions = current_revisions([decision])
      sources = Sources.current(session_id, source_items(revisions))

      with {:ok, access} <- Access.read(scope, project_id, session_id) do
        {:ok, project(decision, revisions, access, sources)}
      end
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def get(_, _, _, _), do: {:error, :not_found}

  def history(scope, project_id, session_id, id, opts) when valid_id(id) do
    with {:ok, _} <- Access.read(scope, project_id, session_id),
         %Decision{} <- Repo.get_by(Decision, id: id, session_id: session_id),
         {:ok, page} <- Input.page(opts) do
      query = from r in Revision, where: r.decision_id == ^id and r.session_id == ^session_id
      query = if page.before_id, do: where(query, [r], r.number < ^page.before_id), else: query
      rows = Repo.all(from r in query, order_by: [desc: r.number], limit: ^(page.limit + 1))
      selected = Enum.take(rows, page.limit)
      sources = Sources.current(session_id, source_items(selected))

      with {:ok, _} <- Access.read(scope, project_id, session_id) do
        {:ok,
         %{
           revisions: Enum.map(selected, &View.revision(&1, sources)),
           next_cursor: if(length(rows) > page.limit, do: List.last(selected).number)
         }}
      end
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def history(_, _, _, _, _), do: {:error, :not_found}

  defp current_revisions(decisions) do
    # Keep the head and agreement from the same read. A concurrent revision may
    # advance the live decision after its row was selected.
    selected =
      Enum.reduce(decisions, dynamic(false), fn decision, query ->
        versions = Enum.reject([decision.version, decision.accepted_version], &is_nil/1)
        dynamic([r], ^query or (r.decision_id == ^decision.id and r.number in ^versions))
      end)

    Repo.all(from r in Revision, where: ^selected)
  end

  defp project(decision, revisions, access, sources) do
    proposal = Enum.find(revisions, &(&1.decision_id == decision.id and &1.number == decision.version))
    accepted = Enum.find(revisions, &(&1.decision_id == decision.id and &1.number == decision.accepted_version))
    View.decision(decision, proposal, accepted, access, sources)
  end

  defp source_items(revisions), do: Enum.flat_map(revisions, & &1.sources["items"])
end
