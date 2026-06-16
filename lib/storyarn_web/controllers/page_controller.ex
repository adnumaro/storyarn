defmodule StoryarnWeb.PageController do
  use StoryarnWeb, :controller

  alias Storyarn.Accounts
  alias Storyarn.RateLimiter

  def join_waitlist(conn, %{"waitlist" => waitlist_params}) do
    case RateLimiter.check_waitlist(format_ip(conn)) do
      :ok ->
        do_join_waitlist(conn, waitlist_params)

      {:error, :rate_limited} ->
        conn
        |> put_flash(:error, gettext("Too many requests. Please try again in about 1 hour."))
        |> redirect(to: ~p"/")
    end
  end

  defp do_join_waitlist(conn, waitlist_params) do
    case Accounts.join_waitlist(waitlist_params) do
      {:ok, entry} ->
        signup_info = %{
          locale: conn.assigns[:locale] || "en",
          accept_language: List.first(get_req_header(conn, "accept-language")) || "unknown",
          ip: format_ip(conn),
          country: List.first(get_req_header(conn, "fly-region")) || "unknown",
          profession: entry.profession,
          primary_interest: entry.primary_interest,
          discovery_source: entry.discovery_source,
          current_tool: entry.current_tool,
          current_tool_other: entry.current_tool_other
        }

        Accounts.notify_admin_waitlist_signup_async(entry.email, signup_info)

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
