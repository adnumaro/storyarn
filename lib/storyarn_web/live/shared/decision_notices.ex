defmodule StoryarnWeb.Live.Shared.DecisionNotices do
  @moduledoc false

  # The compact decision card a decision notification carries in the inbox. It
  # is read now, with the reader's current access: a decision they can no longer
  # see carries no card, and its notification keeps only its sentence.

  use StoryarnWeb, :verified_routes

  alias Storyarn.Ideation
  alias Storyarn.Projects
  alias StoryarnWeb.Live.Shared.IdeationDecisionData

  @pending ~w(not_applied partially_applied)

  @doc "Cards keyed by project and decision, for the decision notifications given."
  def cards(scope, notifications, projects) do
    notifications
    |> Enum.filter(&(&1.entity_type == "decision" and Map.has_key?(projects, &1.project_id)))
    |> Enum.group_by(& &1.project_id, & &1.entity_id)
    |> Enum.flat_map(fn {project_id, ids} ->
      project_cards(scope, project_id, Enum.uniq(ids), projects[project_id])
    end)
    |> Map.new()
  end

  @doc "The attachment one notification carries, or nil."
  def attachment(%{entity_type: "decision", project_id: project_id, entity_id: id} = notification, cards) do
    case cards[{project_id, id}] do
      nil ->
        nil

      card ->
        target = target(notification, card)

        %{
          type: "decision",
          data: %{
            decision: card.props,
            target: target && target.name,
            action: action(notification.kind, target, card),
            sessionName: notification.entity_name
          }
        }
    end
  end

  def attachment(_notification, _cards), do: nil

  defp project_cards(scope, project_id, ids, slugs) do
    decisions =
      for id <- ids,
          {:ok, session_id} <- [Ideation.get_decision_session_id(scope, project_id, id)],
          {:ok, decision} <- [Ideation.get_decision(scope, project_id, session_id, id)],
          do: decision

    sessions = decisions |> Enum.map(& &1.session_id) |> Enum.uniq()

    with [_ | _] <- decisions,
         {:ok, members} <- Projects.list_comment_members(scope, project_id),
         {:ok, rounds} <- Ideation.list_session_rounds(scope, project_id, sessions) do
      Enum.map(decisions, fn decision ->
        board = %{members: members, rounds: Map.get(rounds, decision.session_id, []), href: &content_href(&1, slugs)}

        {{project_id, decision.id},
         %{view: decision, props: IdeationDecisionData.decision(decision, board), slugs: slugs}}
      end)
    else
      _ -> []
    end
  end

  # The content a next action asks to apply is the first one still pending; the
  # content an application names is the one its actor marked applied, when
  # there is exactly one.
  defp target(%{kind: "decision_next_action"}, card) do
    card.view
    |> targets()
    |> Enum.find(&(state(&1) in @pending and &1.available))
  end

  defp target(%{kind: "decision_applied", actor_id: actor_id}, card) when is_integer(actor_id) do
    case Enum.filter(targets(card.view), &(state(&1) == "applied" and &1.application.actor_id == actor_id)) do
      [target] -> target
      _ -> nil
    end
  end

  defp target(_notification, _card), do: nil

  defp targets(%{application: %{targets: targets}}), do: targets
  defp targets(_decision), do: []

  defp state(%{application: %{state: state}}), do: state
  defp state(_target), do: "not_applied"

  defp action("decision_next_action", %{type: type, id: id}, card) when is_integer(id) do
    query = [decision: card.view.id, session: card.view.session_id]
    %{kind: "apply", href: content_href(%{type: type, id: id}, card.slugs) <> "?" <> URI.encode_query(query)}
  end

  defp action(_kind, _target, card) do
    %{workspace_slug: workspace, project_slug: project} = card.slugs
    session = card.view.session_id

    %{
      kind: "open",
      href: ~p"/workspaces/#{workspace}/projects/#{project}/brainstorming/#{session}?#{%{decision: card.view.id}}"
    }
  end

  defp content_href(%{type: "sheet", id: id}, %{workspace_slug: workspace, project_slug: project}),
    do: ~p"/workspaces/#{workspace}/projects/#{project}/sheets/#{id}"

  defp content_href(%{type: "flow", id: id}, %{workspace_slug: workspace, project_slug: project}),
    do: ~p"/workspaces/#{workspace}/projects/#{project}/flows/#{id}"

  defp content_href(%{type: "scene", id: id}, %{workspace_slug: workspace, project_slug: project}),
    do: ~p"/workspaces/#{workspace}/projects/#{project}/scenes/#{id}"
end
