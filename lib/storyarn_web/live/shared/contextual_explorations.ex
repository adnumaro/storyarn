defmodule StoryarnWeb.Live.Shared.ContextualExplorations do
  @moduledoc "Presentation coordinator for contextual entry from the three authoring tools."
  use StoryarnWeb, :verified_routes

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, push_navigate: 2]

  alias Storyarn.Ideation
  alias Storyarn.Projects
  alias Storyarn.Workspaces
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.Live.Shared.IdeationReferenceData, as: ReferenceData

  @access_events ~w(project_membership_changed project_ownership_transferred workspace_membership_changed workspace_ownership_transferred)a

  def init(socket, type) when type in [:sheet, :flow, :scene] do
    if connected?(socket) do
      Projects.subscribe_project_membership_changes(socket.assigns.project.id)
      Projects.subscribe_project_ownership_changes(socket.assigns.project.id)
      Workspaces.subscribe_workspace_membership_changes(socket.assigns.workspace.id)
      Workspaces.subscribe_workspace_ownership_changes(socket.assigns.workspace.id)
      Ideation.subscribe_sessions(socket.assigns.current_scope, socket.assigns.project.id)
    end

    socket
    |> assign(:exploration_type, type)
    |> reset()
    |> attach_hook(:contextual_explorations, :handle_info, &handle_info/2)
  end

  def source_changed(socket) do
    if source_key(socket) == socket.assigns.exploration_source and not socket.assigns.compact,
      do: socket,
      else: reset(socket)
  end

  def handle(action, params, socket) do
    with false <- socket.assigns.compact,
         key when is_binary(key) <- source_key(socket),
         true <- params["source_key"] == key,
         true <-
           action == "open" or
             (socket.assigns.explorations.open and
                params["exploration_context"] == socket.assigns.explorations.context) do
      dispatch(action, params, socket)
    else
      _ -> failure(socket, :stale_context, false)
    end
  end

  defp dispatch("open", _params, socket) do
    socket = socket |> reset() |> put(%{open: true}) |> load()
    reply(socket)
  end

  defp dispatch("close", _params, socket), do: {:reply, %{status: "ok"}, reset(socket)}

  defp dispatch("search", %{"search" => search}, socket) when is_binary(search) and byte_size(search) <= 500 do
    socket = socket |> assign(exploration_search: search, exploration_available_cursor: nil) |> load()
    reply(socket)
  end

  defp dispatch("load_more", %{"list" => list, "cursor" => cursor}, socket) when list in ["linked", "available"] do
    state = socket.assigns.explorations
    next = if list == "linked", do: state.linkedNext, else: state.availableNext

    with {:ok, id} <- positive_id(cursor),
         true <- id == next do
      key = if list == "linked", do: :exploration_linked_cursor, else: :exploration_available_cursor
      socket |> assign(key, id) |> load() |> reply()
    else
      _ -> failure(socket, :invalid_parameters, false)
    end
  end

  defp dispatch(action, params, socket) when action in ["create", "link"] do
    Authorize.with_authorization(socket, :edit_content, &mutate(action, params, &1), fn current, reason ->
      failure(current, reason)
    end)
  end

  defp dispatch("resume", params, socket) do
    %{current_scope: scope, project: project, exploration_type: type} = socket.assigns

    with {:ok, session_id} <- positive_id(params["session_id"]),
         {:ok, result} <-
           Ideation.resume_contextual_session(scope, project.id, Atom.to_string(type), source_id(socket), session_id) do
      navigate(socket, result)
    else
      {:error, reason} -> failure(socket, reason)
    end
  end

  defp dispatch(_, _, socket), do: failure(socket, :invalid_parameters, false)

  defp mutate(action, params, socket) do
    %{current_scope: scope, project: project, exploration_target: target} = socket.assigns

    if target do
      attrs =
        params
        |> Map.take(~w(title objective request_key))
        |> Map.merge(%{
          "target_type" => target.type,
          "target_id" => target.id,
          "target_identity" => target.identity,
          "target_fingerprint" => target.fingerprint
        })

      case run_mutation(action, scope, project.id, params, attrs) do
        {:ok, value} -> navigate(socket, value)
        {:error, reason} -> failure(socket, reason)
      end
    else
      failure(socket, :not_found)
    end
  end

  defp run_mutation("create", scope, project_id, _params, attrs),
    do: Ideation.create_contextual_session(scope, project_id, attrs)

  defp run_mutation("link", scope, project_id, params, attrs) do
    with {:ok, id} <- positive_id(params["session_id"]),
         do: Ideation.link_contextual_session(scope, project_id, id, attrs)
  end

  defp navigate(socket, %{session: session, reference: reference}) do
    %{workspace: workspace, project: project} = socket.assigns

    {:reply, %{status: "ok"},
     push_navigate(socket,
       to:
         ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/brainstorming/#{session.id}?#{%{context_reference: reference.id}}"
     )}
  end

  defp load(socket) do
    %{current_scope: scope, project: project, exploration_type: type} = socket.assigns

    options = [
      search: socket.assigns.exploration_search,
      linked_before_id: socket.assigns.exploration_linked_cursor,
      available_before_id: socket.assigns.exploration_available_cursor
    ]

    case Ideation.get_contextual_brainstorming(scope, project.id, Atom.to_string(type), source_id(socket), options) do
      {:ok, result} ->
        previous = socket.assigns.exploration_target

        changed =
          previous != nil and
            {previous.identity, previous.fingerprint} !=
              {result.target.identity, result.target.fingerprint}

        socket
        |> assign(:exploration_target, result.target)
        |> put(%{
          target: ReferenceData.target(result.target, socket),
          linked: Enum.map(result.linked_sessions, &session/1),
          available: Enum.map(result.available_sessions, &session/1),
          linkedNext: result.linked_next_cursor,
          availableNext: result.available_next_cursor,
          canEdit: match?({:ok, _, _}, Projects.authorize(scope, project.id, :edit_content)),
          context: if(changed, do: Ecto.UUID.generate(), else: socket.assigns.explorations.context),
          error: if(changed, do: "stale_context")
        })

      {:error, reason} ->
        socket
        |> assign(:exploration_target, nil)
        |> put(%{
          target: nil,
          linked: [],
          available: [],
          linkedNext: nil,
          availableNext: nil,
          canEdit: false,
          error: error_code(reason)
        })
    end
  end

  defp session(row) do
    %{
      id: row.id,
      title: row.title,
      status: to_string(row.status),
      contextStatus: if(row[:reference], do: row.reference.status)
    }
  end

  defp reset(socket) do
    assign(socket,
      exploration_source: source_key(socket),
      exploration_target: nil,
      exploration_search: "",
      exploration_linked_cursor: nil,
      exploration_available_cursor: nil,
      explorations: %{
        open: false,
        context: Ecto.UUID.generate(),
        target: nil,
        linked: [],
        available: [],
        linkedNext: nil,
        availableNext: nil,
        canEdit: socket.assigns.can_edit,
        error: nil
      }
    )
  end

  defp handle_info({event, _}, socket) when event in @access_events, do: {:halt, refresh_open(socket)}

  defp handle_info({:ideation_sessions_changed, _}, socket), do: {:halt, refresh_open(socket)}

  defp handle_info({:entities_deleted, _, _}, socket), do: {:cont, refresh_open(socket)}
  defp handle_info({:tree_changed, _}, socket), do: {:cont, refresh_open(socket)}
  defp handle_info(_, socket), do: {:cont, socket}

  defp refresh_open(%{assigns: %{explorations: %{open: true}}} = socket), do: load(socket)
  defp refresh_open(socket), do: socket

  defp source_id(socket) do
    case socket.assigns[socket.assigns.exploration_type] do
      %{id: id} -> id
      _ -> nil
    end
  end

  defp source_key(socket) do
    if id = source_id(socket), do: "#{socket.assigns.exploration_type}:#{id}"
  end

  defp put(socket, attrs), do: assign(socket, :explorations, Map.merge(socket.assigns.explorations, attrs))

  defp reply(%{assigns: %{explorations: %{error: nil}}} = socket), do: {:reply, %{status: "ok"}, socket}
  defp reply(socket), do: {:reply, %{status: "error", code: socket.assigns.explorations.error}, socket}

  defp failure(socket, reason, reload? \\ true) do
    socket = if reload?, do: load(socket), else: socket
    error = %{status: "error", code: error_code(reason)}
    {:reply, error, put(socket, %{error: error.code})}
  end

  defp positive_id(id) when is_integer(id) and id > 0 and id <= 9_007_199_254_740_991, do: {:ok, id}

  defp positive_id(id) when is_binary(id) and byte_size(id) <= 16 do
    case Integer.parse(id) do
      {value, ""} -> positive_id(value)
      _ -> {:error, :invalid_parameters}
    end
  end

  defp positive_id(_), do: {:error, :invalid_parameters}

  defp error_code(%Ecto.Changeset{}), do: "validation"
  defp error_code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_code(_), do: "unavailable"
end
