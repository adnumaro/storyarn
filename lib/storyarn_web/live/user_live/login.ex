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
                {dgettext(
                  "identity",
                  "You need to reauthenticate to perform sensitive actions on your account."
                )}
              <% else %>
                {dgettext("identity", "Enter your email and we'll send you a login link.")}
              <% end %>
            </:subtitle>
          </.header>
        </div>

        <div :if={local_mail_adapter?()} class="alert alert-info">
          <.icon name="info" class="size-6 shrink-0" />
          <div>
            <p>{dgettext("identity", "You are running the local mail adapter.")}</p>
            <p>
              {dgettext("identity", "To see sent emails, visit")} <.link
                href="/dev/mailbox"
                class="underline"
              >{dgettext("identity", "the mailbox sheet")}</.link>.
            </p>
          </div>
        </div>

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

    {:ok, assign(socket, form: form)}
  end

  @impl true
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
          dgettext(
            "identity",
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
