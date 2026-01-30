defmodule StoryarnWeb.ProjectLive.Invitation do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Projects

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} workspaces={@workspaces}>
      <div class="max-w-lg mx-auto text-center py-12">
        <%= if @invitation do %>
          <.icon name="hero-envelope-open" class="size-16 mx-auto text-primary mb-6" />
          <.header>
            {gettext("You've been invited!")}
            <:subtitle>
              {gettext("You've been invited to join a project on Storyarn")}
            </:subtitle>
          </.header>

          <div class="card bg-base-200 mt-8 p-6">
            <h3 class="text-xl font-bold mb-2">{@invitation.project.name}</h3>
            <p class="text-sm text-base-content/70 mb-4">
              {gettext("Invited by")} {@inviter_name} {gettext("as")}
              <span class="badge badge-secondary badge-sm ml-1">{@invitation.role}</span>
            </p>

            <div class="divider" />

            <%= if @current_scope do %>
              <%= if @email_matches do %>
                <div class="space-y-3">
                  <.button variant="primary" class="w-full" phx-click="accept">
                    {gettext("Accept Invitation")}
                  </.button>
                  <.link navigate={~p"/workspaces"} class="btn btn-ghost w-full">
                    {gettext("Decline")}
                  </.link>
                </div>
              <% else %>
                <div class="alert alert-warning">
                  <.icon name="hero-exclamation-triangle" class="size-5" />
                  <span>
                    {gettext("This invitation was sent to")} <strong>{@invitation.email}</strong>. {gettext(
                      "You're logged in as"
                    )} <strong>{@current_scope.user.email}</strong>.
                  </span>
                </div>
                <p class="mt-4 text-sm text-base-content/70">
                  {gettext("Please log in with the correct email address to accept this invitation.")}
                </p>
              <% end %>
            <% else %>
              <p class="text-sm text-base-content/70 mb-4">
                {gettext("Please log in or create an account to accept this invitation.")}
              </p>
              <.link
                navigate={~p"/users/log-in?return_to=#{@return_path}"}
                class="btn btn-primary w-full"
              >
                {gettext("Log in to accept")}
              </.link>
            <% end %>
          </div>
        <% else %>
          <.icon name="hero-x-circle" class="size-16 mx-auto text-error mb-6" />
          <.header>
            {gettext("Invalid Invitation")}
            <:subtitle>
              {gettext("This invitation link is invalid or has expired.")}
            </:subtitle>
          </.header>
          <.link navigate={~p"/"} class="btn btn-primary mt-8">
            {gettext("Go to Homepage")}
          </.link>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case Projects.get_invitation_by_token(token) do
      {:ok, invitation} ->
        inviter_name = invitation.invited_by.display_name || invitation.invited_by.email

        email_matches =
          if socket.assigns.current_scope do
            String.downcase(socket.assigns.current_scope.user.email) ==
              String.downcase(invitation.email)
          else
            false
          end

        socket =
          socket
          |> assign(:invitation, invitation)
          |> assign(:token, token)
          |> assign(:inviter_name, inviter_name)
          |> assign(:email_matches, email_matches)
          |> assign(:return_path, ~p"/projects/invitations/#{token}")

        {:ok, socket}

      {:error, :invalid_token} ->
        socket =
          socket
          |> assign(:invitation, nil)
          |> assign(:token, nil)
          |> assign(:inviter_name, nil)
          |> assign(:email_matches, false)
          |> assign(:return_path, nil)

        {:ok, socket}
    end
  end

  @impl true
  def handle_event("accept", _params, socket) do
    invitation = socket.assigns.invitation
    user = socket.assigns.current_scope.user

    case Projects.accept_invitation(invitation, user) do
      {:ok, _membership} ->
        socket =
          socket
          |> put_flash(:info, gettext("Welcome to the project!"))
          |> push_navigate(to: ~p"/projects/#{invitation.project_id}")

        {:noreply, socket}

      {:error, :email_mismatch} ->
        {:noreply, put_flash(socket, :error, gettext("Your email doesn't match the invitation."))}

      {:error, :already_member} ->
        socket =
          socket
          |> put_flash(:info, gettext("You're already a member of this project."))
          |> push_navigate(to: ~p"/projects/#{invitation.project_id}")

        {:noreply, socket}

      {:error, :already_accepted} ->
        socket =
          socket
          |> put_flash(:info, gettext("This invitation has already been accepted."))
          |> push_navigate(to: ~p"/projects/#{invitation.project_id}")

        {:noreply, socket}

      {:error, :expired} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("This invitation has expired. Please request a new one.")
         )}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, gettext("Failed to accept invitation. Please try again."))}
    end
  end
end
