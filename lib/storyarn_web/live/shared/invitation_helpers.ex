defmodule StoryarnWeb.Live.Shared.InvitationHelpers do
  @moduledoc """
  Shared response handling for public invitation acceptance flows.
  """

  use Gettext, backend: Storyarn.Gettext

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

  def handle_acceptance_error(socket, {:error, :read_only}, _limit_message, redirect_path) do
    {:ok,
     socket
     |> LiveView.put_flash(
       :error,
       gettext(
         "This workspace is read-only, so its invitations cannot be accepted right now. Ask its owner, then try this invitation again."
       )
     )
     |> LiveView.redirect(to: redirect_path)}
  end

  def handle_acceptance_error(socket, {:error, :invitation_unavailable}, _limit_message, _redirect_path),
    do: {:ok, socket}

  def handle_acceptance_error(socket, {:error, _reason}, _limit_message, _redirect_path), do: {:ok, socket}

  @doc """
  Whether the browser accepting the invitation is already signed in as the
  invited user, as it is right after that user sets a password.
  """
  @spec signed_in_as?(Socket.t(), %{id: term()}) :: boolean()
  def signed_in_as?(%Socket{assigns: %{current_scope: %{user: %{id: user_id}}}}, %{id: user_id}), do: true
  def signed_in_as?(_socket, _user), do: false
end
