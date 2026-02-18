defmodule StoryarnWeb.UserLive.Login do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Accounts
  alias Storyarn.RateLimiter

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>
            <p>{dgettext("identity", "Log in")}</p>
            <:subtitle>
              <%= if @current_scope do %>
                {dgettext("identity", "You need to reauthenticate to perform sensitive actions on your account.")}
              <% else %>
                {dgettext("identity", "Don't have an account?")} <.link
                  navigate={~p"/users/register"}
                  class="font-semibold text-brand hover:underline"
                  phx-no-format
                >{dgettext("identity", "Sign up")}</.link> {dgettext("identity", "for an account now.")}
              <% end %>
            </:subtitle>
          </.header>
        </div>

        <div :if={local_mail_adapter?()} class="alert alert-info">
          <.icon name="info" class="size-6 shrink-0" />
          <div>
            <p>{dgettext("identity", "You are running the local mail adapter.")}</p>
            <p>
              {dgettext("identity", "To see sent emails, visit")} <.link href="/dev/mailbox" class="underline">{dgettext("identity", "the mailbox sheet")}</.link>.
            </p>
          </div>
        </div>

        <.oauth_buttons class="mb-4" />

        <div class="divider">{dgettext("identity", "or continue with email")}</div>

        <.form
          :let={f}
          for={@form}
          id="login_form_magic"
          action={~p"/users/log-in"}
          phx-submit="submit_magic"
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label={dgettext("identity", "Email")}
            autocomplete="email"
            required
            phx-mounted={JS.focus()}
          />
          <.button class="btn btn-primary w-full">
            {dgettext("identity", "Log in with email")} <span aria-hidden="true">→</span>
          </.button>
        </.form>

        <div class="divider">{dgettext("identity", "or")}</div>

        <.form
          :let={f}
          for={@form}
          id="login_form_password"
          action={~p"/users/log-in"}
          phx-submit="submit_password"
          phx-trigger-action={@trigger_submit}
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label={dgettext("identity", "Email")}
            autocomplete="email"
            required
          />
          <.input
            field={@form[:password]}
            type="password"
            label={dgettext("identity", "Password")}
            autocomplete="current-password"
          />
          <.button class="btn btn-primary w-full" name={@form[:remember_me].name} value="true">
            {dgettext("identity", "Log in and stay logged in")} <span aria-hidden="true">→</span>
          </.button>
          <.button class="btn btn-primary btn-soft w-full mt-2">
            {dgettext("identity", "Log in only this time")}
          </.button>
        </.form>
      </div>
    </Layouts.auth>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    case RateLimiter.check_magic_link(email) do
      :ok ->
        if user = Accounts.get_user_by_email(email) do
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )
        end

        info =
          dgettext("identity",
            "If your email is in our system, you will receive instructions for logging in shortly."
          )

        {:noreply,
         socket
         |> put_flash(:info, info)
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, :rate_limited} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("identity", "Too many requests. Please try again later."))
         |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  defp local_mail_adapter? do
    Application.get_env(:storyarn, Storyarn.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
