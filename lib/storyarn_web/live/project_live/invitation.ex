defmodule StoryarnWeb.ProjectLive.Invitation do
  @moduledoc """
  Accepts a project invitation on mount.

  Users with passwords are added as members immediately. New or passwordless
  users are routed through password setup before the invitation is accepted.
  """

  use StoryarnWeb, :live_view

  alias Storyarn.Accounts
  alias Storyarn.Projects
  alias StoryarnWeb.PublicURLs

  @impl true
  def render(assigns) do
    assigns =
      assign(
        assigns,
        :seo_metadata,
        assigns |> Map.put(:seo_robots, "noindex, follow") |> Layouts.live_seo_metadata()
      )

    ~H"""
    <StoryarnWeb.Components.PublicLayout.public
      flash={@flash}
      socket={@socket}
      seo_metadata={@seo_metadata}
      current_scope={@current_scope}
    >
      <.vue
        v-component="live/project/invitation/ProjectInvitationResponse"
        v-socket={@socket}
        id="project-invitation"
        homepage-url={PublicURLs.home_path(@locale)}
      />
    </StoryarnWeb.Components.PublicLayout.public>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case Projects.get_invitation_by_token(token) do
      {:ok, invitation} ->
        accept_and_redirect(socket, invitation, token)

      {:error, :invalid_token} ->
        {:ok, socket}
    end
  end

  defp accept_and_redirect(socket, invitation, token) do
    case Accounts.prepare_invitation_user(invitation.email) do
      {:ok, {:ready, user}} ->
        accept_ready_user(socket, invitation, user)

      {:ok, {:registration_required, registration_token}} ->
        redirect_to_registration(socket, invitation, token, registration_token)

      {:error, _reason} ->
        {:ok, socket}
    end
  end

  defp accept_ready_user(socket, invitation, user) do
    case Projects.accept_invitation(invitation, user) do
      {:ok, _membership} ->
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

  defp redirect_to_registration(socket, invitation, token, registration_token) do
    invitation_path = ~p"/projects/invitations/#{token}"
    registration_path = ~p"/users/register/#{registration_token}?#{[return_to: invitation_path]}"

    {:ok,
     socket
     |> put_flash(
       :info,
       dgettext(
         "projects",
         "Create a password for %{email} to accept your invitation.",
         email: invitation.email
       )
     )
     |> redirect(to: registration_path)}
  end
end
