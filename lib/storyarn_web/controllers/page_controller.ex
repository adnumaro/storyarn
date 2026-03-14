defmodule StoryarnWeb.PageController do
  use StoryarnWeb, :controller

  alias Storyarn.Accounts
  alias Storyarn.RateLimiter
  alias Storyarn.Workspaces

  def home(conn, _params) do
    case conn.assigns do
      %{current_scope: %{user: %Storyarn.Accounts.User{} = user}} ->
        redirect_to_workspace(conn, user)

      _ ->
        render(conn, :home)
    end
  end

  def contact(conn, _params) do
    render(conn, :contact)
  end

  def join_waitlist(conn, %{"waitlist" => %{"email" => email}}) do
    case RateLimiter.check_waitlist(format_ip(conn)) do
      :ok ->
        do_join_waitlist(conn, email)

      {:error, :rate_limited} ->
        conn
        |> put_flash(:error, gettext("Too many requests. Please try again later."))
        |> redirect(to: ~p"/")
    end
  end

  defp do_join_waitlist(conn, email) do
    case Accounts.join_waitlist(%{"email" => email}) do
      {:ok, _entry} ->
        signup_info = %{
          locale: conn.assigns[:locale] || "en",
          accept_language: List.first(get_req_header(conn, "accept-language")) || "unknown",
          ip: format_ip(conn),
          country: List.first(get_req_header(conn, "fly-region")) || "unknown"
        }

        Accounts.notify_admin_waitlist_signup(email, signup_info)

        conn
        |> put_flash(
          :info,
          gettext("You're on the list! We'll reach out when your spot is ready.")
        )
        |> redirect(to: ~p"/")

      {:error, _changeset} ->
        conn
        |> put_flash(
          :info,
          gettext("You're on the list! We'll reach out when your spot is ready.")
        )
        |> redirect(to: ~p"/")
    end
  end

  defp format_ip(conn) do
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end

  defp redirect_to_workspace(conn, user) do
    case Workspaces.get_default_workspace(user) do
      %Workspaces.Workspace{slug: slug} ->
        redirect(conn, to: ~p"/workspaces/#{slug}")

      nil ->
        redirect(conn, to: ~p"/workspaces/new")
    end
  end
end
