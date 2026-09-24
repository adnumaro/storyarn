defmodule Storyarn.Ideation.Decisions.Queries.Catalog do
  @moduledoc false
  import Ecto.Query
  import Storyarn.Ideation.Decisions.Rules.Input, only: [valid_id: 1]

  alias Storyarn.Ideation.Decisions.Application
  alias Storyarn.Ideation.Decisions.Decision
  alias Storyarn.Ideation.Decisions.Queries.Access
  alias Storyarn.Ideation.Decisions.Queries.Sources
  alias Storyarn.Ideation.Decisions.Queries.Targets
  alias Storyarn.Ideation.Decisions.Revision
  alias Storyarn.Ideation.Decisions.View
  alias Storyarn.Repo

  # A session holds at most 100 decisions, so the list is read whole: its order
  # depends on who is reading and what is still to apply, never on a page.
  def list(scope, project_id, session_id) do
    with {:ok, _} <- Access.read(scope, project_id, session_id) do
      decisions = Repo.all(from d in Decision, where: d.session_id == ^session_id, order_by: [desc: d.id], limit: 100)

      with {:ok, context} <- context(scope, project_id, session_id, decisions),
           {:ok, access} <- Access.read(scope, project_id, session_id) do
        {:ok, Enum.map(decisions, &View.decision(&1, context, access))}
      end
    end
  end

  def get(scope, project_id, session_id, id) when valid_id(id) do
    with {:ok, _} <- Access.read(scope, project_id, session_id),
         %Decision{} = decision <- Repo.get_by(Decision, id: id, session_id: session_id),
         {:ok, context} <- context(scope, project_id, session_id, [decision]),
         {:ok, access} <- Access.read(scope, project_id, session_id) do
      {:ok, View.decision(decision, context, access)}
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def get(_, _, _, _), do: {:error, :not_found}

  def history(scope, project_id, session_id, id) when valid_id(id) do
    with {:ok, _} <- Access.read(scope, project_id, session_id),
         %Decision{} <- Repo.get_by(Decision, id: id, session_id: session_id) do
      revisions = Repo.all(from r in Revision, where: r.decision_id == ^id, order_by: [desc: r.number])
      applications = Repo.all(from a in Application, where: a.decision_id == ^id, order_by: [desc: a.id])

      with {:ok, context} <- revision_context(scope, project_id, session_id, revisions),
           {:ok, _} <- Access.read(scope, project_id, session_id) do
        views = Map.new(revisions, &{&1.number, View.revision(&1, context)})

        {:ok,
         %{
           revisions: Enum.map(revisions, &views[&1.number]),
           applications: Enum.map(applications, &View.declaration(&1, views[&1.agreement]))
         }}
      end
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def history(_, _, _, _), do: {:error, :not_found}

  defp context(scope, project_id, session_id, decisions) do
    revisions = current_revisions(decisions)

    with {:ok, context} <- revision_context(scope, project_id, session_id, revisions) do
      {:ok,
       Map.merge(context, %{
         revisions: Map.new(revisions, &{{&1.decision_id, &1.number}, &1}),
         applications: applications(decisions),
         related: related(session_id, revisions)
       })}
    end
  end

  defp revision_context(scope, project_id, session_id, revisions) do
    with {:ok, targets} <- Targets.live(scope, project_id, Targets.pairs(revisions)) do
      {:ok, %{sources: Sources.current(session_id, source_items(revisions)), targets: targets}}
    end
  end

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

  defp applications(decisions) do
    agreements = for %{accepted_version: n} = d <- decisions, not is_nil(n), do: {d.id, n}

    selected =
      Enum.reduce(agreements, dynamic(false), fn {id, agreement}, query ->
        dynamic([a], ^query or (a.decision_id == ^id and a.agreement == ^agreement))
      end)

    from(a in Application, where: ^selected, order_by: [asc: a.id])
    |> Repo.all()
    |> Enum.group_by(&{&1.decision_id, &1.agreement})
    |> Map.new(fn {key, declarations} ->
      {key, Map.new(declarations, &{&1.target_key, Map.take(&1, [:state, :note, :actor_id, :inserted_at])})}
    end)
  end

  # The decisions a proposal replaces, or that replaced it, named by the
  # content they currently hold.
  defp related(session_id, revisions) do
    ids =
      revisions
      |> Enum.flat_map(&[&1.replaces_id, &1.superseded_by_id])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    decisions = Repo.all(from d in Decision, where: d.session_id == ^session_id and d.id in ^ids)

    heads =
      Map.new(current_revisions(decisions), &{{&1.decision_id, &1.number}, &1})

    Map.new(decisions, fn decision ->
      current = heads[{decision.id, decision.accepted_version || decision.version}]

      {decision.id,
       %{
         id: decision.id,
         title: current.title,
         status: decision.status,
         replaceable: decision.status in [:accepted, :proposed] and not is_nil(decision.accepted_version),
         superseded_by_id: heads[{decision.id, decision.version}].superseded_by_id
       }}
    end)
  end

  defp source_items(revisions), do: Enum.flat_map(revisions, & &1.sources["items"])
end
