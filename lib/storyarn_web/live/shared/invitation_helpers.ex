defmodule StoryarnWeb.Live.Shared.InvitationHelpers do
  @moduledoc """
  Shared response handling for public invitation acceptance flows.
  """

  alias Phoenix.LiveView
  alias Phoenix.LiveView.Socket

  @type acceptance_error ::
          {:error, :limit_reached, term()}
          | {:error, :invitation_unavailable}
          | {:error, term()}

  @spec handle_acceptance_error(Socket.t(), acceptance_error(), String.t(), String.t()) ::
          {:ok, Socket.t()}
  def handle_acceptance_error(socket, {:error, :limit_reached, _details}, limit_message, redirect_path) do
    {:ok,
     socket
     |> LiveView.put_flash(:error, limit_message)
     |> LiveView.redirect(to: redirect_path)}
  end

  def handle_acceptance_error(socket, {:error, :invitation_unavailable}, _limit_message, _redirect_path),
    do: {:ok, socket}

  def handle_acceptance_error(socket, {:error, _reason}, _limit_message, _redirect_path), do: {:ok, socket}
end
