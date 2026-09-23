defmodule StoryarnWeb.Live.Shared.ContextualDecisions do
  @moduledoc """
  Decisions about the content open in an authoring tool: the lightbulb count,
  the Explorations section and the banner that arrives with "Go apply". Marking
  is a statement about this content; nothing is ever applied automatically.
  """
  use StoryarnWeb, :verified_routes

  import Phoenix.Component, only: [assign: 2, assign: 3]

  alias Storyarn.Ideation
  alias Storyarn.Projects
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.Live.Shared.IdeationDecisionData
  alias StoryarnWeb.Live.Shared.IdeationReferenceData

  @pending ~w(not_applied partially_applied)
  @marks ~w(applied partially_applied no_change_needed)

  def init(socket),
    do: assign(socket, decision_link: nil, decision_source: nil, decision_items: [], decision_banner: nil)

  # A "Go apply" link names the decision and its session; other navigation
  # within the editor leaves an open banner alone.
  def linked(params, socket) do
    case {positive(params["session"]), positive(params["decision"])} do
      {{:ok, session_id}, {:ok, decision_id}} -> assign(socket, :decision_link, {session_id, decision_id})
      _ -> socket
    end
  end

  @doc "Reads the decisions about a new source, then opens the linked decision in the banner."
  def refresh(socket, source) do
    socket
    |> then(&if(&1.assigns.decision_source == source, do: &1, else: load(&1, source)))
    |> open_link()
  end

  @doc "Rereads the decisions about the current source, keeping the banner's decision current."
  def reload(%{assigns: %{decision_source: nil}} = socket), do: socket

  def reload(socket) do
    socket = load(socket, socket.assigns.decision_source)

    case socket.assigns.decision_banner do
      %{session_id: session_id, decision_id: decision_id} = banner ->
        show(socket, session_id, decision_id, Map.take(banner, [:marked]))

      nil ->
        socket
    end
  end

  def summary(socket) do
    items = socket.assigns.decision_items
    %{total: length(items), toApply: Enum.count(items, &to_apply?/1), name: source_name(socket)}
  end

  defp source_name(%{assigns: %{decision_source: {type, _id}} = assigns}) do
    case assigns[type] do
      %{name: name} -> name
      _ -> nil
    end
  end

  defp source_name(_socket), do: nil

  # Still to apply here, then proposals, then what is applied or needs no change.
  def about(socket) do
    socket.assigns.decision_items
    |> Enum.sort_by(&{rank(&1), -&1.decision.id})
    |> Enum.map(&item_props(&1, socket))
  end

  def banner(%{assigns: %{decision_banner: nil}}), do: nil

  def banner(socket) do
    banner = socket.assigns.decision_banner

    %{
      decision: banner.decision,
      targetKey: banner.target_key,
      sessionTitle: banner.session_title,
      sessionUrl: banner.session_url,
      marked: banner.marked && %{state: banner.marked.state},
      error: banner.error
    }
  end

  def handle("apply", params, socket) do
    with {:ok, session_id} <- positive(params["session_id"]),
         {:ok, decision_id} <- positive(params["decision_id"]) do
      socket = show(socket, session_id, decision_id)
      if socket.assigns.decision_banner, do: {:ok, socket}, else: {:error, :not_found, socket}
    else
      _ -> {:error, :invalid_parameters, socket}
    end
  end

  def handle("dismiss", _params, socket), do: {:ok, assign(socket, :decision_banner, nil)}

  def handle(action, params, socket) when action in ~w(declare undo) do
    Authorize.with_authorization(socket, :edit_content, &declare(action, params, &1), fn current, reason ->
      {:error, reason, current}
    end)
  end

  def handle(_action, _params, socket), do: {:error, :invalid_parameters, socket}

  defp declare("declare", params, socket) do
    with {:ok, session_id} <- positive(params["session_id"]),
         {:ok, decision_id} <- positive(params["decision_id"]),
         %{} = item <- find(socket, session_id, decision_id),
         key when is_binary(key) <- params["target_key"],
         true <- key == item.target_key,
         state when state in @marks <- params["state"],
         {:ok, _} <- submit(socket, item.decision, key, state, params["note"], params["request_key"]) do
      socket = reload(socket)
      {:ok, mark_banner(socket, decision_id, state, state_of(item))}
    else
      {:error, reason} -> {:error, reason, reload(socket)}
      _ -> {:error, :invalid_parameters, socket}
    end
  end

  # Undo states the target's previous application again; the history keeps both.
  defp declare("undo", params, socket) do
    with %{marked: %{previous: previous}} = banner <- socket.assigns.decision_banner,
         %{} = item <- find(socket, banner.session_id, banner.decision_id),
         {:ok, _} <- submit(socket, item.decision, banner.target_key, previous, nil, params["request_key"]) do
      {:ok, socket |> reload() |> clear_mark()}
    else
      {:error, reason} -> {:error, reason, reload(socket)}
      _ -> {:error, :invalid_parameters, socket}
    end
  end

  defp submit(socket, decision, key, state, note, request_key) do
    %{current_scope: scope, project: project} = socket.assigns

    Ideation.declare_decision_application(
      scope,
      project.id,
      decision.session_id,
      decision.id,
      decision.accepted_version,
      %{
        "target_key" => key,
        "state" => state,
        "note" => note,
        "request_key" => request_key
      }
    )
  end

  defp mark_banner(%{assigns: %{decision_banner: %{decision_id: id} = banner}} = socket, id, state, previous),
    do: assign(socket, :decision_banner, %{banner | marked: %{state: state, previous: previous}, error: nil})

  defp mark_banner(socket, _id, _state, _previous), do: socket

  defp clear_mark(%{assigns: %{decision_banner: %{} = banner}} = socket),
    do: assign(socket, :decision_banner, %{banner | marked: nil})

  defp clear_mark(socket), do: socket

  defp load(socket, {type, id} = source) do
    %{current_scope: scope, project: project} = socket.assigns

    items =
      with {:ok, items} <- Ideation.list_decisions_about(scope, project.id, Atom.to_string(type), id),
           {:ok, context} <- context(socket, items) do
        Enum.map(items, &Map.put(&1, :props, IdeationDecisionData.decision(&1.decision, context.(&1.session.id))))
      else
        _ -> []
      end

    assign(socket, decision_source: source, decision_items: items)
  end

  defp context(_socket, []), do: {:ok, fn _ -> %{rounds: [], members: []} end}

  defp context(socket, items) do
    %{current_scope: scope, project: project} = socket.assigns
    ids = items |> Enum.map(& &1.session.id) |> Enum.uniq()

    with {:ok, members} <- Projects.list_comment_members(scope, project.id),
         {:ok, rounds} <- Ideation.list_session_rounds(scope, project.id, ids) do
      href = &IdeationReferenceData.destination(&1, socket)
      {:ok, fn session_id -> %{members: members, rounds: Map.get(rounds, session_id, []), href: href} end}
    end
  end

  defp open_link(%{assigns: %{decision_link: {session_id, decision_id}}} = socket),
    do: socket |> assign(:decision_link, nil) |> show(session_id, decision_id)

  defp open_link(socket), do: socket

  # The banner only shows an accepted decision that names this content.
  defp show(socket, session_id, decision_id, keep \\ %{}) do
    case find(socket, session_id, decision_id) do
      %{target_key: key, decision: %{accepted_version: agreement}} = item
      when is_binary(key) and not is_nil(agreement) ->
        assign(
          socket,
          :decision_banner,
          Map.merge(
            %{
              session_id: session_id,
              decision_id: decision_id,
              target_key: key,
              decision: item.props,
              session_title: item.session.title,
              session_url: session_url(socket, session_id, decision_id),
              marked: nil,
              error: nil
            },
            keep
          )
        )

      _ ->
        assign(socket, :decision_banner, nil)
    end
  end

  defp find(socket, session_id, decision_id),
    do: Enum.find(socket.assigns.decision_items, &(&1.session.id == session_id and &1.decision.id == decision_id))

  defp item_props(item, socket) do
    %{
      decision: item.props,
      targetKey: item.target_key,
      sessionId: item.session.id,
      sessionTitle: item.session.title,
      sessionUrl: session_url(socket, item.session.id, item.decision.id),
      toApply: to_apply?(item)
    }
  end

  defp rank(item) do
    cond do
      to_apply?(item) -> 0
      item.decision.status == :proposed -> 1
      item.decision.status == :accepted -> 2
      true -> 3
    end
  end

  defp to_apply?(%{decision: %{status: :accepted}} = item), do: state_of(item) in @pending
  defp to_apply?(_item), do: false

  defp state_of(%{target_key: key, decision: %{application: %{targets: targets}}}) when is_binary(key) do
    case Enum.find(targets, &(&1.key == key)) do
      %{application: %{state: state}} -> state
      %{} -> "not_applied"
      nil -> nil
    end
  end

  defp state_of(_item), do: nil

  defp session_url(socket, session_id, decision_id) do
    %{workspace: workspace, project: project} = socket.assigns
    ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/brainstorming/#{session_id}?#{%{decision: decision_id}}"
  end

  defp positive(value) when is_integer(value) and value > 0 and value <= 9_007_199_254_740_991, do: {:ok, value}

  defp positive(value) when is_binary(value) and byte_size(value) <= 16 do
    case Integer.parse(value) do
      {id, ""} -> positive(id)
      _ -> :error
    end
  end

  defp positive(_value), do: :error
end
