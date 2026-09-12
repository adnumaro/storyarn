defmodule StoryarnWeb.IdeationLive.Handlers.ExplorationContextHandlers do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [push_navigate: 2]

  alias Storyarn.Ideation
  alias StoryarnWeb.IdeationLive.Helpers.Params
  alias StoryarnWeb.IdeationLive.Helpers.Replies
  alias StoryarnWeb.Live.Shared.IdeationReferenceData, as: ReferenceData

  def init(socket), do: assign(socket, context_reference_id: nil, exploration_reference: nil)

  def linked(socket, params) do
    case Params.optional_id(params["context_reference"]) do
      {:ok, id} -> socket |> assign(context_reference_id: id, exploration_reference: nil) |> refresh()
      {:error, _} -> init(socket)
    end
  end

  def refresh(%{assigns: %{context_reference_id: nil}} = socket), do: socket

  def refresh(socket) do
    case reference(socket) do
      {:ok, row} -> assign(socket, exploration_reference: ReferenceData.reference(row, socket))
      {:error, _} -> assign(socket, exploration_reference: nil)
    end
  end

  def return_to_source(params, socket) do
    with true <- params["epoch"] == socket.assigns.epoch,
         {:ok, session_id} <- Params.positive(params["session_id"]),
         true <- session_id == socket.assigns.session_id,
         {:ok, reference_id} <- Params.positive(params["reference_id"]),
         true <- reference_id == socket.assigns.context_reference_id,
         {:ok, %{current: target}} when not is_nil(target) <- reference(socket),
         path when is_binary(path) <- ReferenceData.destination(target.locator, socket) do
      {:reply, %{status: "ok"}, push_navigate(socket, to: path)}
    else
      _ -> {:reply, Replies.error(:not_found), refresh(socket)}
    end
  end

  defp reference(socket) do
    %{current_scope: scope, project: project, session_id: session_id, context_reference_id: id} = socket.assigns
    Ideation.get_reference(scope, project.id, session_id, nil, id)
  end
end
