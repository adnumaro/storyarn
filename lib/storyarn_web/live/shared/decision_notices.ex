defmodule StoryarnWeb.Live.Shared.DecisionNotices do
  @moduledoc false

  # The compact decision card a decision notification carries in the inbox. It
  # is read now, with the reader's current access: a decision they can no longer
  # see carries no card, and its notification keeps only its sentence. All the
  # decisions of a project are read together, one pass per session.

  use StoryarnWeb, :verified_routes

  alias Storyarn.Ideation
  alias Storyarn.NotificationInbox
  alias Storyarn.Projects
  alias StoryarnWeb.Live.Shared.IdeationDecisionData

  @pending ~w(not_applied partially_applied)

  @doc "The cards and applied declarations for the decision notifications given."
  def index(scope, notifications, projects) do
    notifications
    |> Enum.filter(&(&1.entity_type == "decision" and Map.has_key?(projects, &1.project_id)))
    |> Enum.group_by(& &1.project_id)
    |> Enum.reduce(%{cards: %{}, declarations: %{}}, fn {project_id, project_notifications}, index ->
      {cards, declarations} = project_index(scope, project_id, project_notifications, projects[project_id])
      %{cards: Map.merge(index.cards, cards), declarations: Map.merge(index.declarations, declarations)}
    end)
  end

  @doc "The attachment one notification carries, or nil."
  def attachment(%{entity_type: "decision", project_id: project_id, entity_id: id} = notification, index) do
    case index.cards[{project_id, id}] do
      nil ->
        nil

      card ->
        target = target(notification, card, index.declarations)

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

  def attachment(_notification, _index), do: nil

  defp project_index(scope, project_id, notifications, slugs) do
    ids = notifications |> Enum.map(& &1.entity_id) |> Enum.uniq()

    events =
      for %{kind: "decision_applied"} = n <- notifications, do: {n.entity_id, NotificationInbox.decision_event(n)}

    with {:ok, [_ | _] = decisions} <- Ideation.list_decisions_by_ids(scope, project_id, ids),
         {:ok, declared} <- Ideation.decision_event_declarations(scope, project_id, events),
         {:ok, members} <- Projects.list_comment_members(scope, project_id),
         sessions = decisions |> Enum.map(& &1.session_id) |> Enum.uniq(),
         {:ok, rounds} <- Ideation.list_session_rounds(scope, project_id, sessions) do
      cards =
        Map.new(decisions, fn decision ->
          board = %{members: members, rounds: Map.get(rounds, decision.session_id, []), href: &content_href(&1, slugs)}

          {{project_id, decision.id},
           %{view: decision, props: IdeationDecisionData.decision(decision, board), slugs: slugs}}
        end)

      {cards, Map.new(declared, fn {{id, event}, declaration} -> {{project_id, id, event}, declaration} end)}
    else
      _ -> {%{}, %{}}
    end
  end

  # A next action points at the first content still pending. An application
  # names the content its own declaration marked, when that declaration belongs
  # to the agreement shown; never whatever happens to be applied now.
  defp target(%{kind: "decision_next_action"}, card, _declarations) do
    card.view
    |> targets()
    |> Enum.find(&(state(&1) in @pending and &1.available))
  end

  defp target(%{kind: "decision_applied"} = notification, card, declarations) do
    event = NotificationInbox.decision_event(notification)

    case declarations[{notification.project_id, notification.entity_id, event}] do
      %{agreement: agreement, target_key: key} when agreement == card.view.accepted_version and is_binary(key) ->
        Enum.find(targets(card.view), &(&1.key == key))

      _ ->
        nil
    end
  end

  defp target(_notification, _card, _declarations), do: nil

  defp targets(%{application: %{targets: targets}}), do: targets
  defp targets(_decision), do: []

  defp state(%{application: %{state: state}}), do: state
  defp state(_target), do: "not_applied"

  # Go apply only where the reader can still declare; anything else opens the decision.
  defp action("decision_next_action", %{type: type, id: id}, %{view: %{can_declare: true}} = card)
       when is_integer(id) do
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
