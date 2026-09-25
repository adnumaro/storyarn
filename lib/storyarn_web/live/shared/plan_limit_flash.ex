defmodule StoryarnWeb.Live.Shared.PlanLimitFlash do
  @moduledoc """
  Toasts for a plan limit the actor has just hit.

  The notice lives under its own `:limit` flash key so the toaster can link to
  the workspace's Plan & usage page. Only actors who can open that page get
  the link, decided by the same authorization the page runs on mount.

  The project sidebars are sticky nested LiveViews: their flash never reaches
  the toaster and they have no parent pid, since they outlive the page. They
  `forward/2` the notice on a topic for their browser tab, keyed like the
  ideation sidebar's navigation, and the page that renders the toaster picks
  it up through the `:receive_forwarded` hook.
  """

  use StoryarnWeb, :verified_routes

  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, put_flash: 3]

  alias Phoenix.LiveView.Socket
  alias Storyarn.Workspaces

  @spec put(Socket.t(), pos_integer() | nil, String.t()) :: Socket.t()
  def put(%Socket{} = socket, workspace_id, message) when is_binary(message) do
    put_flash(socket, :limit, %{
      "message" => message,
      "planPath" => plan_path(socket.assigns.current_scope, workspace_id)
    })
  end

  @spec forward(Socket.t(), String.t()) :: Socket.t()
  def forward(%Socket{} = socket, message) when is_binary(message) do
    Phoenix.PubSub.broadcast(Storyarn.PubSub, tab_topic(socket), {__MODULE__, :forwarded, message})
    socket
  end

  def on_mount(:receive_forwarded, _params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Storyarn.PubSub, tab_topic(socket))

    {:cont, attach_hook(socket, :plan_limit_flash, :handle_info, &receive_forwarded/2)}
  end

  defp tab_topic(socket) do
    "plan-limit-flash:#{node(socket.transport_pid)}:#{inspect(socket.transport_pid)}"
  end

  defp receive_forwarded({__MODULE__, :forwarded, message}, socket) do
    {:halt, put(socket, workspace_id(socket.assigns), message)}
  end

  defp receive_forwarded(_message, socket), do: {:cont, socket}

  defp workspace_id(%{workspace: %{id: id}}), do: id
  defp workspace_id(_assigns), do: nil

  defp plan_path(scope, workspace_id) when is_integer(workspace_id) do
    case Workspaces.authorize(scope, workspace_id, :access_workspace_settings) do
      {:ok, workspace, _membership} -> ~p"/users/settings/workspaces/#{workspace.slug}/plan"
      {:error, _reason} -> nil
    end
  end

  defp plan_path(_scope, _workspace_id), do: nil
end
