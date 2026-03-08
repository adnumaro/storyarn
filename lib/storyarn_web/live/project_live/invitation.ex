defmodule StoryarnWeb.ProjectLive.Invitation do
  @moduledoc """
  Accepts a project invitation on mount.

  Creates the user account (if needed), adds the membership, marks the
  invitation as accepted, and redirects to login.
  """

  use StoryarnWeb, :live_view

  alias Storyarn.Projects

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.public flash={@flash}>
      <div class="max-w-lg mx-auto text-center py-12">
        <.icon name="x-circle" class="size-16 mx-auto text-error mb-6" />
        <.header>
          {dgettext("projects", "Invalid Invitation")}
          <:subtitle>
            {dgettext("projects", "This invitation link is invalid or has expired.")}
          </:subtitle>
        </.header>
        <.link navigate={~p"/"} class="btn btn-primary mt-8">
          {dgettext("projects", "Go to Homepage")}
        </.link>
      </div>
    </Layouts.public>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case Projects.get_invitation_by_token(token) do
      {:ok, invitation} ->
        accept_and_redirect(socket, invitation)

      {:error, :invalid_token} ->
        {:ok, socket}
    end
  end

  defp accept_and_redirect(socket, invitation) do
    with {:ok, user} <- Storyarn.Accounts.find_or_register_confirmed_user(invitation.email),
         {:ok, _membership} <- Projects.accept_invitation(invitation, user) do
      {:ok,
       socket
       |> put_flash(
         :info,
         dgettext(
           "projects",
           "Invitation accepted! Log in with %{email} to get started.",
           email: invitation.email
         )
       )
       |> redirect(to: ~p"/users/log-in")}
    else
      {:error, :already_accepted} ->
        {:ok,
         socket
         |> put_flash(:info, dgettext("projects", "This invitation has already been accepted."))
         |> redirect(to: ~p"/users/log-in")}

      {:error, :already_member} ->
        {:ok,
         socket
         |> put_flash(:info, dgettext("projects", "You're already a member of this project."))
         |> redirect(to: ~p"/users/log-in")}

      {:error, _reason} ->
        {:ok, socket}
    end
  end
end
