defmodule StoryarnWeb.PageController do
  use StoryarnWeb, :controller

  alias Storyarn.Accounts
  alias Storyarn.RateLimiter

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

        Accounts.notify_admin_waitlist_signup_async(email, signup_info)

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
end
