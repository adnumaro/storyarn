defmodule StoryarnWeb.UserLive.Confirmation do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm">
        <div class="text-center">
          <.header>{dgettext("identity", "Welcome %{email}", email: @user.email)}</.header>
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
            class="btn btn-primary w-full"
          >
            {dgettext("identity", "Confirm and stay logged in")}
          </.button>
          <.button
            phx-disable-with={dgettext("identity", "Confirming...")}
            class="btn btn-primary btn-soft w-full mt-2"
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
            <.button phx-disable-with={dgettext("identity", "Logging in...")} class="btn btn-primary w-full">
              {dgettext("identity", "Log in")}
            </.button>
          <% else %>
            <.button
              name={@form[:remember_me].name}
              value="true"
              phx-disable-with={dgettext("identity", "Logging in...")}
              class="btn btn-primary w-full"
            >
              {dgettext("identity", "Keep me logged in on this device")}
            </.button>
            <.button
              phx-disable-with={dgettext("identity", "Logging in...")}
              class="btn btn-primary btn-soft w-full mt-2"
            >
              {dgettext("identity", "Log me in only this time")}
            </.button>
          <% end %>
        </.form>

        <p :if={!@user.confirmed_at} class="alert alert-outline mt-8">
          {dgettext("identity", "Tip: If you prefer passwords, you can enable them in the user settings.")}
        </p>
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
