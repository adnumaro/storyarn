defmodule StoryarnWeb.UserLive.Confirmation do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash} current_scope={@current_scope}>
      <%!-- Confirmation uses phx-trigger-action for native form submission,
           which requires HEEx forms. The Vue component handles display only. --%>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <h1 class="text-2xl font-bold tracking-tight">
            {dgettext("identity", "Welcome %{email}", email: @user.email)}
          </h1>
        </div>

        <.form
          :if={!@user.confirmed_at}
          for={@form}
          id="confirmation_form"
          phx-mounted={JS.focus_first()}
          phx-submit="submit"
          action={~p"/users/log-in?_action=confirmed"}
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
          <.button
            name={@form[:remember_me].name}
            value="true"
            phx-disable-with={dgettext("identity", "Confirming...")}
            class="w-full"
          >
            {dgettext("identity", "Confirm and stay logged in")}
          </.button>
          <.button
            phx-disable-with={dgettext("identity", "Confirming...")}
            class="inline-flex items-center justify-center px-4 py-2 text-sm font-medium rounded-md bg-primary text-primary-foreground hover:bg-primary/90 transition-colors btn-soft btn-sm w-full mt-2"
          >
            {dgettext("identity", "Confirm and log in only this time")}
          </.button>
        </.form>

        <.form
          :if={@user.confirmed_at}
          for={@form}
          id="login_form"
          phx-submit="submit"
          phx-mounted={JS.focus_first()}
          action={~p"/users/log-in"}
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
          <%= if @current_scope do %>
            <.button
              phx-disable-with={dgettext("identity", "Logging in...")}
              class="w-full"
            >
              {dgettext("identity", "Log in")}
            </.button>
          <% else %>
            <.button
              name={@form[:remember_me].name}
              value="true"
              phx-disable-with={dgettext("identity", "Logging in...")}
              class="w-full"
            >
              {dgettext("identity", "Keep me logged in on this device")}
            </.button>
            <.button
              phx-disable-with={dgettext("identity", "Logging in...")}
              class="inline-flex items-center justify-center px-4 py-2 text-sm font-medium rounded-md bg-primary text-primary-foreground hover:bg-primary/90 transition-colors btn-soft btn-sm w-full mt-2"
            >
              {dgettext("identity", "Log me in only this time")}
            </.button>
          <% end %>
        </.form>

        <div
          :if={!@user.confirmed_at}
          class="rounded-lg border border-border bg-muted/30 p-3 text-sm text-muted-foreground mt-8"
        >
          {dgettext(
            "identity",
            "Tip: If you prefer passwords, you can enable them in the user settings."
          )}
        </div>
      </div>
    </Layouts.auth>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Accounts.get_user_by_magic_link_token(token) do
      form = to_form(%{"token" => token}, as: "user")

      {:ok, assign(socket, user: user, form: form, trigger_submit: false),
       temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(:error, dgettext("identity", "Magic link is invalid or it has expired."))
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
