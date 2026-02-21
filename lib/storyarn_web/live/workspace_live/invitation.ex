defmodule StoryarnWeb.WorkspaceLive.Invitation do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Workspaces

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} workspaces={@workspaces}>
      <div class="max-w-lg mx-auto text-center py-12">
        <%= if @invitation do %>
          <.icon name="mail-open" class="size-16 mx-auto text-primary mb-6" />
          <.header>
            {dgettext("workspaces", "You've been invited!")}
            <:subtitle>
              {dgettext("workspaces", "You've been invited to join a workspace on Storyarn")}
            </:subtitle>
          </.header>

          <div class="card bg-base-200 mt-8 p-6">
            <h3 class="text-xl font-bold mb-2">{@invitation.workspace.name}</h3>
            <p class="text-sm text-base-content/70 mb-4">
              {dgettext("workspaces", "Invited by")} {@inviter_name} {dgettext("workspaces", "as")}
              <span class="badge badge-secondary badge-sm ml-1">{@invitation.role}</span>
            </p>

            <div class="divider" />

            <%= if @current_scope do %>
              <%= if @email_matches do %>
                <div class="space-y-3">
                  <.button variant="primary" class="w-full" phx-click="accept">
                    {dgettext("workspaces", "Accept Invitation")}
                  </.button>
                  <.link navigate={~p"/workspaces"} class="btn btn-ghost w-full">
                    {dgettext("workspaces", "Decline")}
                  </.link>
                </div>
              <% else %>
                <div class="alert alert-warning">
                  <.icon name="triangle-alert" class="size-5" />
                  <span>
                    {dgettext("workspaces", "This invitation was sent to")} <strong>{@invitation.email}</strong>. {dgettext(
                      "workspaces",
                      "You're logged in as"
                    )} <strong>{@current_scope.user.email}</strong>.
                  </span>
                </div>
                <p class="mt-4 text-sm text-base-content/70">
                  {dgettext(
                    "workspaces",
                    "Please log in with the correct email address to accept this invitation."
                  )}
                </p>
              <% end %>
            <% else %>
              <p class="text-sm text-base-content/70 mb-4">
                {dgettext(
                  "workspaces",
                  "Please log in or create an account to accept this invitation."
                )}
              </p>
              <.link
                navigate={~p"/users/log-in?return_to=#{@return_path}"}
                class="btn btn-primary w-full"
              >
                {dgettext("workspaces", "Log in to accept")}
              </.link>
            <% end %>
          </div>
        <% else %>
          <.icon name="x-circle" class="size-16 mx-auto text-error mb-6" />
          <.header>
            {dgettext("workspaces", "Invalid Invitation")}
            <:subtitle>
              {dgettext("workspaces", "This invitation link is invalid or has expired.")}
            </:subtitle>
          </.header>
          <.link navigate={~p"/"} class="btn btn-primary mt-8">
            {dgettext("workspaces", "Go to Homepage")}
          </.link>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case Workspaces.get_invitation_by_token(token) do
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
          |> assign(:return_path, ~p"/workspaces/invitations/#{token}")

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

    case Workspaces.accept_invitation(invitation, user) do
      {:ok, _membership} ->
        socket =
          socket
          |> put_flash(:info, dgettext("workspaces", "Welcome to the workspace!"))
          |> push_navigate(to: ~p"/workspaces/#{invitation.workspace.slug}")

        {:noreply, socket}

      {:error, :email_mismatch} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("workspaces", "Your email doesn't match the invitation.")
         )}

      {:error, :already_member} ->
        socket =
          socket
          |> put_flash(
            :info,
            dgettext("workspaces", "You're already a member of this workspace.")
          )
          |> push_navigate(to: ~p"/workspaces/#{invitation.workspace.slug}")

        {:noreply, socket}

      {:error, :already_accepted} ->
        socket =
          socket
          |> put_flash(
            :info,
            dgettext("workspaces", "This invitation has already been accepted.")
          )
          |> push_navigate(to: ~p"/workspaces/#{invitation.workspace.slug}")

        {:noreply, socket}

      {:error, :expired} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("workspaces", "This invitation has expired. Please request a new one.")
         )}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("workspaces", "Failed to accept invitation. Please try again.")
         )}
    end
  end
end
