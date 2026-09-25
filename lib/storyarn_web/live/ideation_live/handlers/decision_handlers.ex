defmodule StoryarnWeb.IdeationLive.Handlers.DecisionHandlers do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2, assign: 3]

  alias Storyarn.Ideation
  alias Storyarn.Projects
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.IdeationLive.Handlers.CommentHandlers
  alias StoryarnWeb.IdeationLive.Handlers.ReferenceHandlers
  alias StoryarnWeb.IdeationLive.Helpers.Params
  alias StoryarnWeb.IdeationLive.Helpers.Replies
  alias StoryarnWeb.Live.Shared.IdeationDecisionData
  alias StoryarnWeb.Live.Shared.IdeationReferenceData

  @target_types ~w(sheet flow scene)

  def init(socket) do
    assign(socket,
      decision_source_query: nil,
      decisions: %{
        open: false,
        context: Ecto.UUID.generate(),
        mode: "list",
        items: [],
        selected: nil,
        history: [],
        sources: [],
        sourceResults: [],
        sourceNextCursor: nil,
        searched: false,
        targetSuggestions: [],
        targetResults: [],
        prefill: nil,
        members: [],
        defaultOwnerId: nil,
        viewerId: nil,
        rounds: [],
        canPropose: false,
        error: nil
      }
    )
  end

  def handle(action, params, socket) do
    with true <- socket.assigns.session_id != nil,
         true <- params["epoch"] == socket.assigns.epoch,
         {:ok, id} <- Params.positive(params["session_id"]),
         true <- id == socket.assigns.session_id,
         true <-
           action in ~w(open new add_sources) or
             (socket.assigns.decisions.open and params["decision_context"] == socket.assigns.decisions.context) do
      dispatch(action, params, socket)
    else
      _ -> failure(socket, :stale_board)
    end
  end

  def refresh(%{assigns: %{decisions: %{open: false}}} = socket), do: socket

  def refresh(socket) do
    %{current_scope: scope, project: project, session_id: id} = socket.assigns

    with {:ok, session} <- Ideation.get_session(scope, project.id, id),
         {:ok, _, membership} <- Projects.authorize(scope, project.id, :view),
         {:ok, members} <- Projects.list_editor_candidates(scope, project.id),
         {:ok, decisions} <- Ideation.list_decisions(scope, project.id, id) do
      can_propose = session.status == :open and Projects.can?(membership.role, :edit_content)

      socket
      |> put(%{
        items: Enum.map(decisions, &IdeationDecisionData.decision(&1, board(socket))),
        members: members,
        defaultOwnerId: if(Enum.any?(members, &(&1.id == session.decision_owner_id)), do: session.decision_owner_id),
        viewerId: scope.user.id,
        rounds: Enum.map(board(socket).rounds, &%{number: &1.number, prompt: &1.prompt}),
        canPropose: can_propose,
        error: nil
      })
      |> refresh_selected()
      |> refresh_sources()
      |> refresh_search()
    else
      _ -> init(socket)
    end
  end

  def preserve_editor(socket), do: failure(socket, :proposal_in_progress)

  # The board draws every decision in its band's lane, whether or not the panel
  # is open. Reads recheck access and source visibility like the panel's.
  def load_canvas(%{assigns: %{session_id: nil}} = socket), do: assign(socket, :canvas_decisions, [])

  def load_canvas(socket) do
    %{current_scope: scope, project: project, session_id: id} = socket.assigns

    case Ideation.list_decisions(scope, project.id, id) do
      {:ok, decisions} ->
        assign(socket, :canvas_decisions, Enum.map(decisions, &IdeationDecisionData.decision(&1, board(socket))))

      {:error, _} ->
        assign(socket, :canvas_decisions, [])
    end
  end

  def focused(%{mode: "detail", selected: %{id: id}}), do: id
  def focused(_state), do: nil

  # A link to a decision's discussion opens the panel on that decision.
  def discussed(%{assigns: %{comments: %{decisionId: id}}} = socket) when is_integer(id), do: show(socket, id)
  def discussed(socket), do: socket

  # A link to a decision (from content, the inbox or the dashboard) opens it too.
  def linked(socket, %{"decision" => id}) do
    case Params.positive(id) do
      {:ok, id} -> show(socket, id)
      _ -> socket
    end
  end

  def linked(socket, _params), do: socket

  defp show(socket, id), do: socket |> init() |> put(%{open: true, mode: "detail", selected: %{id: id}}) |> refresh()

  defp dispatch("open", %{"from_header" => true}, %{assigns: %{decisions: %{open: true}}} = socket), do: ok(socket)

  defp dispatch("new", _, %{assigns: %{decisions: %{open: true, mode: mode}}} = socket) when mode in ~w(create revise),
    do: preserve_editor(socket)

  # A lane card on the board opens the panel on its decision.
  defp dispatch("open", %{"decision_id" => decision_id}, socket) do
    case Params.positive(decision_id) do
      {:ok, id} ->
        socket
        |> init()
        |> put(%{open: true, mode: "detail", selected: %{id: id}})
        |> refresh()
        |> close_other_panels()
        |> opened()

      {:error, reason} ->
        failure(socket, reason)
    end
  end

  defp dispatch("open", _params, socket) do
    socket = socket |> init() |> put(%{open: true}) |> refresh() |> close_other_panels()
    opened(socket)
  end

  defp dispatch("new", params, socket) do
    socket = socket |> init() |> put(%{open: true, mode: "create"}) |> refresh() |> close_other_panels()

    with true <- socket.assigns.decisions.open and socket.assigns.decisions.canPropose,
         {:ok, selection} <- initial_selection(params) do
      socket = suggest_targets(socket)
      if selection == [], do: ok(socket), else: selection |> preview(socket) |> prefill(params)
    else
      false -> failure(socket, :unauthorized)
      {:error, reason} -> failure(socket, reason)
    end
  end

  # Selecting notes on the board while a proposal is open adds them to its sources.
  defp dispatch("add_sources", params, %{assigns: %{decisions: %{open: true, mode: mode}}} = socket)
       when mode in ~w(create revise) do
    with %{"idea_ids" => _} <- params,
         {:ok, selection} <- initial_selection(params) do
      sources = Enum.uniq_by(socket.assigns.decisions.sources ++ selection, &{field(&1, :type), field(&1, :id)})
      preview(sources, socket)
    else
      _ -> failure(socket, :invalid_parameters)
    end
  end

  defp dispatch("add_sources", _, socket), do: failure(socket, :stale_board)

  defp dispatch("close", _, socket), do: ok(init(socket))
  defp dispatch("reload", _, socket), do: ok(refresh(socket))

  defp dispatch("select", params, socket) do
    case Params.positive(params["decision_id"]) do
      {:ok, id} ->
        socket
        |> put(%{
          mode: "detail",
          selected: %{id: id},
          sources: [],
          history: [],
          prefill: nil,
          context: Ecto.UUID.generate(),
          error: nil
        })
        |> refresh()
        |> opened()

      {:error, reason} ->
        failure(socket, reason)
    end
  end

  defp dispatch("begin_revision", params, socket) do
    %{current_scope: scope, project: project, session_id: id} = socket.assigns

    with {:ok, decision_id} <- Params.positive(params["decision_id"]),
         {:ok, version} <- Params.positive(params["revision"]),
         {:ok, decision} <- Ideation.get_decision(scope, project.id, id, decision_id),
         true <- decision.version == version,
         true <- decision.can_revise do
      selected = IdeationDecisionData.decision(decision, board(socket))

      socket
      |> put(%{
        mode: "revise",
        selected: selected,
        sources: revision_basis(selected).sources,
        sourceResults: [],
        sourceNextCursor: nil,
        searched: false,
        history: [],
        prefill: nil,
        context: Ecto.UUID.generate(),
        error: nil
      })
      |> assign(decision_source_query: nil)
      |> suggest_targets()
      |> ok()
    else
      {:error, reason} -> failure(refresh(socket), reason)
      _ -> failure(refresh(socket), :stale_decision)
    end
  end

  defp dispatch("search_sources", params, socket) do
    %{current_scope: scope, project: project, session_id: id} = socket.assigns

    with {:ok, before_id} <- Params.optional_id(params["before_id"]),
         {:ok, page} <-
           Ideation.search_decision_sources(scope, project.id, id,
             type: params["type"],
             search: params["search"] || "",
             before_id: before_id
           ) do
      socket
      |> assign(:decision_source_query, %{type: params["type"], search: params["search"] || "", before_id: before_id})
      |> put(%{
        sourceResults: Enum.map(page.sources, &IdeationDecisionData.source(&1, board(socket))),
        sourceNextCursor: page.next_cursor,
        searched: true,
        error: nil
      })
      |> ok()
    else
      {:error, reason} -> failure(refresh(socket), reason)
    end
  end

  defp dispatch("preview_sources", %{"sources" => sources}, socket), do: preview(sources, socket)

  defp dispatch("refresh_sources", _, socket) do
    preview(socket.assigns.decisions.sources, socket, true)
  end

  defp dispatch("search_targets", %{"search" => search}, socket) when is_binary(search) and byte_size(search) <= 500 do
    %{current_scope: scope, project: project, session_id: id} = socket.assigns

    results =
      Enum.flat_map(@target_types, fn type ->
        case Ideation.search_reference_targets(scope, project.id, id, nil, type: type, search: search) do
          {:ok, targets} -> targets |> Enum.take(8) |> Enum.map(&%{type: type, id: &1.id, name: &1.name})
          {:error, _} -> []
        end
      end)

    socket |> put(%{targetResults: results, error: nil}) |> ok()
  end

  defp dispatch("history", params, socket) do
    %{current_scope: scope, project: project, session_id: id, decisions: state} = socket.assigns

    with {:ok, decision_id} <- Params.positive(params["decision_id"]),
         true <- state.selected != nil and state.selected.id == decision_id,
         {:ok, history} <- Ideation.decision_history(scope, project.id, id, decision_id) do
      socket |> put(%{history: IdeationDecisionData.history(history, board(socket)), error: nil}) |> ok()
    else
      {:error, reason} -> failure(refresh(socket), reason)
      _ -> failure(socket, :invalid_parameters)
    end
  end

  defp dispatch(action, params, socket)
       when action in ~w(create revise accept withdraw declare link_task edit_task unlink_task) do
    Authorize.with_authorization(socket, :edit_content, &mutate(action, params, &1), fn current, reason ->
      failure(refresh(current), reason)
    end)
  end

  defp dispatch(_, _, socket), do: failure(socket, :invalid_parameters)

  defp mutate("create", params, socket) do
    %{current_scope: scope, project: project, session_id: id} = socket.assigns
    result(Ideation.propose_decision(scope, project.id, id, proposal_attrs(params)), socket)
  end

  # A declaration keeps the reader where they are: the detail refreshes in place.
  defp mutate("declare", params, socket) do
    %{current_scope: scope, project: project, session_id: id} = socket.assigns

    with {:ok, decision_id} <- Params.positive(params["decision_id"]),
         {:ok, agreement} <- Params.positive(params["agreement"]),
         attrs = Map.take(params, ~w(target_key state note request_key)),
         {:ok, _decision} <- Ideation.declare_decision_application(scope, project.id, id, decision_id, agreement, attrs) do
      socket |> refresh() |> ok()
    else
      {:error, reason} -> failure(refresh(socket), reason)
    end
  end

  # Linking a task, like declaring, keeps the reader on the detail.
  defp mutate(action, params, socket) when action in ~w(link_task edit_task unlink_task) do
    %{current_scope: scope, project: project, session_id: id} = socket.assigns

    with {:ok, decision_id} <- Params.positive(params["decision_id"]),
         {:ok, _decision} <- task_change(action, {scope, project.id, id, decision_id}, params) do
      socket |> refresh() |> ok()
    else
      {:error, reason} -> failure(refresh(socket), reason)
    end
  end

  defp mutate(action, params, socket) do
    %{current_scope: scope, project: project, session_id: id} = socket.assigns

    with {:ok, decision_id} <- Params.positive(params["decision_id"]),
         {:ok, version} <- Params.positive(params["revision"]) do
      key = params["request_key"]

      response =
        case action do
          "accept" -> Ideation.accept_decision(scope, project.id, id, decision_id, version, key)
          "withdraw" -> Ideation.withdraw_decision(scope, project.id, id, decision_id, version, key)
          "revise" -> Ideation.revise_decision(scope, project.id, id, decision_id, version, proposal_attrs(params))
        end

      result(response, socket)
    else
      {:error, reason} -> failure(socket, reason)
    end
  end

  defp task_change("link_task", {scope, project_id, id, decision_id}, params),
    do: Ideation.link_decision_task(scope, project_id, id, decision_id, Map.take(params, ~w(url title request_key)))

  defp task_change("edit_task", {scope, project_id, id, decision_id}, params) do
    attrs = Map.take(params, ~w(url title request_key))
    Ideation.edit_decision_task(scope, project_id, id, decision_id, params["link_key"], attrs)
  end

  defp task_change("unlink_task", {scope, project_id, id, decision_id}, params),
    do: Ideation.unlink_decision_task(scope, project_id, id, decision_id, params["link_key"], params["request_key"])

  defp proposal_attrs(params) do
    params
    |> Map.take(
      ~w(title conclusion reason verb targets next_action next_action_owner_id replaces_id register sources request_key)
    )
    |> Map.put("responsible_id", params["owner_id"])
  end

  defp result({:ok, decision}, socket) do
    socket
    |> put(%{
      selected: %{id: decision.id},
      mode: "detail",
      sources: [],
      history: [],
      prefill: nil,
      context: Ecto.UUID.generate(),
      error: nil
    })
    |> refresh()
    |> ok()
  end

  defp result({:error, reason}, socket), do: failure(refresh(socket), reason)

  defp preview(selection, socket, replace \\ false)
  defp preview([], socket, _replace), do: socket |> put(%{sources: [], error: nil}) |> ok()

  defp preview(selection, socket, replace) when is_list(selection) and length(selection) <= 20 do
    socket = refresh_selected(socket)
    %{current_scope: scope, project: project, session_id: id} = socket.assigns
    ids = Enum.map(selection, &source_identity/1)

    case Ideation.preview_decision_sources(scope, project.id, id, ids) do
      {:ok, sources} ->
        previous = if replace, do: [], else: socket.assigns.decisions.sources

        updated = Enum.map(sources, &preview_source(&1, previous, socket))

        # A recycled numeric ID cannot silently replace a previously selected source.
        changed_identity? =
          Enum.any?(selection, fn source ->
            identity = field(source, :identity)
            identity && not Enum.any?(sources, &(&1.identity == identity))
          end)

        if changed_identity?,
          do: failure(refresh(socket), :sources_unavailable),
          else: socket |> put(%{sources: updated, error: nil}) |> ok()

      {:error, reason} ->
        failure(refresh(socket), reason)
    end
  end

  defp preview(_, socket, _replace), do: failure(socket, :invalid_parameters)

  defp preview_source(current, previous, socket) do
    case Enum.find(previous, &(&1.identity == current.identity)) do
      nil -> IdeationDecisionData.source(current, board(socket))
      saved -> restore_source(saved, current, socket)
    end
  end

  defp refresh_selected(%{assigns: %{decisions: %{selected: nil}}} = socket), do: socket

  defp refresh_selected(socket) do
    %{current_scope: scope, project: project, session_id: id, decisions: state} = socket.assigns

    case Ideation.get_decision(scope, project.id, id, state.selected.id) do
      {:ok, decision} ->
        socket
        |> put(%{selected: IdeationDecisionData.decision(decision, board(socket))})
        |> refresh_history()

      {:error, _} ->
        init(socket)
    end
  end

  defp refresh_history(%{assigns: %{decisions: %{history: []}}} = socket), do: socket

  defp refresh_history(socket) do
    %{current_scope: scope, project: project, session_id: id, decisions: state} = socket.assigns

    case Ideation.decision_history(scope, project.id, id, state.selected.id) do
      {:ok, history} -> put(socket, %{history: IdeationDecisionData.history(history, board(socket))})
      {:error, _} -> init(socket)
    end
  end

  defp refresh_search(%{assigns: %{decisions: %{open: false}}} = socket), do: socket
  defp refresh_search(%{assigns: %{decision_source_query: nil}} = socket), do: socket

  defp refresh_search(socket) do
    %{current_scope: scope, project: project, session_id: id, decision_source_query: query} = socket.assigns

    case Ideation.search_decision_sources(scope, project.id, id, Map.to_list(query)) do
      {:ok, page} ->
        put(socket, %{
          sourceResults: Enum.map(page.sources, &IdeationDecisionData.source(&1, board(socket))),
          sourceNextCursor: page.next_cursor,
          searched: true
        })

      {:error, _} ->
        put(socket, %{sourceResults: [], sourceNextCursor: nil, searched: false})
    end
  end

  defp refresh_sources(%{assigns: %{decisions: %{open: false}}} = socket), do: socket

  defp refresh_sources(socket) do
    %{current_scope: scope, project: project, session_id: id, decisions: state} = socket.assigns

    sources =
      Enum.map(state.sources, fn source ->
        candidate = pinned_source(state, source) || source

        case Ideation.preview_decision_sources(scope, project.id, id, [Map.take(candidate, [:type, :id])]) do
          {:ok, [current]} when current.identity == source.identity ->
            restore_source(source, current, socket)

          _ ->
            %{source | available: false, title: "", preview: "", changed: false, currentVersion: nil}
        end
      end)

    put(socket, %{sources: sources})
  end

  defp restore_source(source, current, socket) do
    state = socket.assigns.decisions
    pinned = pinned_source(state, source)

    base =
      cond do
        source.available -> source
        current.version == source.version -> IdeationDecisionData.source(current, board(socket))
        pinned != nil -> pinned
        true -> nil
      end

    source
    |> Map.merge(if(base, do: Map.take(base, [:title, :preview]), else: %{title: "", preview: ""}))
    |> Map.merge(%{
      id: current.id,
      available: base != nil,
      changed: current.version != source.version,
      currentVersion: current.version
    })
  end

  defp pinned_source(%{mode: "revise", selected: %{} = selected}, source) do
    Enum.find(revision_basis(selected).sources, fn pinned ->
      pinned.available and pinned.type == source.type and pinned.identity == source.identity and
        pinned.version == source.version
    end)
  end

  defp pinned_source(_, _), do: nil

  # A revision starts from the agreement in force unless one is already pending;
  # a withdrawn revision's sources never come back.
  defp revision_basis(%{status: :accepted, accepted: %{} = agreement}), do: agreement
  defp revision_basis(selected), do: selected.proposal

  # The session's origin and references come first in the Affects picker; the
  # project search covers anything else.
  defp suggest_targets(socket) do
    %{current_scope: scope, project: project, session_id: id} = socket.assigns

    suggestions =
      case Ideation.list_references(scope, project.id, id, nil, limit: 50) do
        {:ok, %{references: references}} ->
          references
          |> Enum.filter(&(&1.target_type in @target_types and &1.current != nil))
          |> Enum.sort_by(&if(&1.relation == "origin", do: 0, else: 1))
          |> Enum.uniq_by(&{&1.target_type, &1.target_id})
          |> Enum.map(&%{type: &1.target_type, id: &1.target_id, name: &1.current.name, relation: &1.relation})

        {:error, _} ->
          []
      end

    put(socket, %{targetSuggestions: suggestions, targetResults: []})
  end

  # "Turn into decision" starts from the group's own words: its synthesis is the
  # conclusion and its title names the decision.
  defp prefill({:reply, %{status: "ok"} = reply, socket}, %{"group_id" => _}) do
    case socket.assigns.decisions.sources do
      [%{type: "group", title: title, preview: synthesis}] ->
        {:reply, reply, put(socket, %{prefill: %{title: title, conclusion: synthesis, fromGroup: title}})}

      _ ->
        {:reply, reply, socket}
    end
  end

  defp prefill(reply, _params), do: reply

  defp initial_selection(%{"group_id" => id}) do
    with {:ok, id} <- Params.positive(id), do: {:ok, [%{type: "group", id: id}]}
  end

  defp initial_selection(%{"idea_ids" => ids}) when is_list(ids) and length(ids) in 1..20 do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, selected} ->
      case Params.positive(id) do
        {:ok, id} -> {:cont, {:ok, selected ++ [%{type: "idea", id: id}]}}
        error -> {:halt, error}
      end
    end)
  end

  defp initial_selection(params) do
    if Map.has_key?(params, "idea_ids"), do: {:error, :invalid_parameters}, else: {:ok, []}
  end

  defp source_identity(source), do: %{type: field(source, :type), id: field(source, :id)}
  defp field(source, key) when is_map(source), do: Map.get(source, key, Map.get(source, Atom.to_string(key)))
  defp field(_, _), do: nil

  defp close_other_panels(socket), do: socket |> CommentHandlers.close() |> ReferenceHandlers.init()
  defp board(socket), do: Map.put(socket.assigns.board, :href, &IdeationReferenceData.destination(&1, socket))
  defp opened(%{assigns: %{decisions: %{open: true}}} = socket), do: ok(socket)
  defp opened(socket), do: failure(socket, :not_found)
  defp ok(socket), do: {:reply, %{status: "ok"}, socket}
  defp put(socket, attrs), do: assign(socket, :decisions, Map.merge(socket.assigns.decisions, attrs))
  defp failure(socket, reason), do: {:reply, Replies.error(reason), put(socket, %{error: code(reason)})}
  defp code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp code(_), do: "unavailable"
end
