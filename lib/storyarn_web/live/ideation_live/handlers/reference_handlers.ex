defmodule StoryarnWeb.IdeationLive.Handlers.ReferenceHandlers do
  @moduledoc false
  use StoryarnWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]

  alias Storyarn.Ideation
  alias Storyarn.Projects
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.IdeationLive.Handlers.CommentHandlers
  alias StoryarnWeb.IdeationLive.Helpers.Params
  alias StoryarnWeb.IdeationLive.Helpers.Replies

  @overview_fields ~w(shortcut description color is_main width height filename content_type size locale_code source_type source_field source_text translated_text status)

  def init(socket) do
    assign(socket, :references, %{
      open: false,
      context: Ecto.UUID.generate(),
      ideaId: nil,
      items: [],
      nextCursor: nil,
      results: [],
      searched: false,
      historyReferenceId: nil,
      history: [],
      canEdit: false,
      error: nil
    })
  end

  def handle(action, params, socket) do
    with true <- socket.assigns.session_id != nil,
         true <- params["epoch"] == socket.assigns.epoch,
         {:ok, id} <- Params.positive(params["session_id"]),
         true <- id == socket.assigns.session_id,
         true <-
           action == "open" or
             (socket.assigns.references.open and params["reference_context"] == socket.assigns.references.context) do
      dispatch(action, params, socket)
    else
      _ -> failure(socket, :stale_board)
    end
  end

  def refresh(%{assigns: %{references: %{open: false}}} = socket), do: socket

  def refresh(socket) do
    # Do not keep target names, previews or history across an access transition.
    socket
    |> put(%{results: [], searched: false, historyReferenceId: nil, history: []})
    |> load()
  end

  defp dispatch("open", params, socket) do
    case Params.optional_id(params["idea_id"]) do
      {:ok, idea_id} ->
        socket = socket |> init() |> put(%{open: true, ideaId: idea_id}) |> refresh()

        if socket.assigns.references.open,
          do: {:reply, %{status: "ok"}, CommentHandlers.init(socket)},
          else: failure(socket, :not_found)

      {:error, reason} ->
        failure(socket, reason)
    end
  end

  defp dispatch(action, params, socket) when action in ~w(add refresh remove) do
    Authorize.with_authorization(socket, :edit_content, &mutate(action, params, &1), fn current, reason ->
      failure(refresh(current), reason)
    end)
  end

  defp dispatch("close", _, socket), do: {:reply, %{status: "ok"}, init(socket)}
  defp dispatch("reload", _, socket), do: {:reply, %{status: "ok"}, refresh(socket)}

  defp dispatch("load_more", _, socket) do
    {:reply, %{status: "ok"}, load(socket, socket.assigns.references.nextCursor)}
  end

  defp dispatch("search", params, socket) do
    %{current_scope: scope, project: project, session_id: id, references: state} = socket.assigns

    case Ideation.search_reference_targets(scope, project.id, id, state.ideaId,
           type: params["type"],
           search: params["search"]
         ) do
      {:ok, targets} ->
        {:reply, %{status: "ok"},
         put(socket, %{results: Enum.map(targets, &target(&1, socket)), searched: true, error: nil})}

      {:error, reason} ->
        failure(refresh(socket), reason)
    end
  end

  defp dispatch("history", params, socket) do
    %{current_scope: scope, project: project, session_id: id, references: state} = socket.assigns

    with {:ok, reference_id} <- Params.positive(params["reference_id"]),
         {:ok, rows} <- Ideation.reference_history(scope, project.id, id, state.ideaId, reference_id) do
      history =
        Enum.map(rows, fn row ->
          %{
            number: row.number,
            operation: row.operation,
            insertedAt: row.inserted_at,
            context: base(row.context)
          }
        end)

      {:reply, %{status: "ok"}, put(socket, %{historyReferenceId: reference_id, history: history, error: nil})}
    else
      {:error, reason} -> failure(refresh(socket), reason)
    end
  end

  defp dispatch(_, _, socket), do: failure(socket, :invalid_parameters)

  defp mutate("add", params, socket) do
    %{current_scope: scope, project: project, session_id: id, references: state} = socket.assigns

    case Params.positive(params["target_id"]) do
      {:ok, target_id} ->
        attrs = params |> Map.take(~w(target_type relation request_key)) |> Map.put("target_id", target_id)
        result(Ideation.add_reference(scope, project.id, id, state.ideaId, attrs), socket)

      {:error, reason} ->
        failure(socket, reason)
    end
  end

  defp mutate(action, params, socket) do
    %{current_scope: scope, project: project, session_id: id, references: state} = socket.assigns

    with {:ok, reference_id} <- Params.positive(params["reference_id"]),
         {:ok, version} <- Params.positive(params["version"]) do
      response =
        if action == "refresh",
          do:
            Ideation.refresh_reference(
              scope,
              project.id,
              id,
              state.ideaId,
              reference_id,
              version,
              params["request_key"]
            ),
          else:
            Ideation.remove_reference(
              scope,
              project.id,
              id,
              state.ideaId,
              reference_id,
              version,
              params["request_key"]
            )

      result(response, socket)
    else
      {:error, reason} -> failure(socket, reason)
    end
  end

  defp result({:ok, _}, socket), do: {:reply, %{status: "ok"}, refresh(socket)}
  defp result({:error, reason}, socket), do: failure(refresh(socket), reason)

  defp load(socket, cursor \\ nil) do
    %{current_scope: scope, project: project, session_id: id, references: state} = socket.assigns

    case Ideation.list_references(scope, project.id, id, state.ideaId, before_id: cursor) do
      {:ok, %{references: references, next_cursor: next}} ->
        items = Enum.map(references, &reference(&1, socket))

        put(socket, %{
          items: items,
          nextCursor: next,
          historyReferenceId: nil,
          history: [],
          canEdit:
            socket.assigns.board.session != nil and socket.assigns.board.session.status == :open and
              match?({:ok, _, _}, Projects.authorize(scope, project.id, :edit_content)),
          error: nil
        })

      {:error, _} ->
        init(socket)
    end
  end

  defp reference(row, socket) do
    %{
      id: row.id,
      version: row.version,
      relation: row.relation,
      targetType: row.target_type,
      targetId: row.target_id,
      status: row.status,
      base: base(row.base),
      current: if(row.current, do: target(row.current, socket)),
      capturedAt: row.captured_at
    }
  end

  defp base(nil), do: nil

  defp base(context) do
    %{name: context["name"], fields: fields(context["overview"] || %{}), capturedAt: context["captured_at"]}
  end

  defp target(target, socket) do
    %{
      id: target.id,
      type: target.type,
      name: target.name,
      fields: fields(target.context),
      href: destination(target.locator, socket)
    }
  end

  defp fields(context) do
    for key <- @overview_fields,
        value <- [context[key]],
        not is_nil(value) and value != "" do
      %{key: key, value: to_string(value), truncated: context[key <> "_truncated"] == true}
    end
  end

  defp destination(%{type: "sheet", id: id}, %{assigns: assigns}),
    do: ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/sheets/#{id}"

  defp destination(%{type: "flow", id: id}, %{assigns: assigns}),
    do: ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/flows/#{id}"

  defp destination(%{type: "scene", id: id}, %{assigns: assigns}),
    do: ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/scenes/#{id}"

  defp destination(%{type: "asset", id: id}, %{assigns: assigns}),
    do: ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/assets?#{%{asset: id}}"

  defp destination(%{type: "localization", id: id}, %{assigns: assigns}),
    do: ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/localization/text/#{id}"

  defp destination(_, _), do: nil

  defp put(socket, attrs), do: assign(socket, :references, Map.merge(socket.assigns.references, attrs))
  defp failure(socket, reason), do: {:reply, Replies.error(reason), put(socket, %{error: error_code(reason)})}
  defp error_code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_code(_), do: "unavailable"
end
