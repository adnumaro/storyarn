defmodule StoryarnWeb.Plugs.Locale do
  @moduledoc """
  Plug for handling locale detection and switching.

  Checks locale in this order:
  1. URL parameter (?locale=es)
  2. User's saved locale preference (from DB)
  3. Session value
  4. Accept-Language header
  5. Default locale (en)
  """
  import Plug.Conn

  @locales Gettext.known_locales(Storyarn.Gettext)
  @default_locale "en"

  def init(opts), do: opts

  def call(conn, _opts) do
    param_locale = get_locale_from_params(conn)
    user_locale = get_locale_from_user(conn)

    locale =
      param_locale ||
        user_locale ||
        get_locale_from_session(conn) ||
        get_locale_from_header(conn) ||
        @default_locale

    Gettext.put_locale(Storyarn.Gettext, locale)

    conn =
      cond do
        # URL param: persist in session for this browsing session
        param_locale -> put_session(conn, :locale, locale)
        # DB preference set: DB is source of truth, clear stale session value
        user_locale -> delete_session(conn, :locale)
        # No DB preference: don't persist, let it re-detect each time
        true -> conn
      end

    assign(conn, :locale, locale)
  end

  defp get_locale_from_user(conn) do
    case conn.assigns do
      %{current_scope: %{user: %{locale: locale}}} when is_binary(locale) ->
        validate_locale(locale)

      _ ->
        nil
    end
  end

  defp get_locale_from_params(conn) do
    conn.params["locale"] |> validate_locale()
  end

  defp get_locale_from_session(conn) do
    get_session(conn, :locale) |> validate_locale()
  end

  defp get_locale_from_header(conn) do
    conn
    |> get_req_header("accept-language")
    |> List.first()
    |> parse_accept_language()
    |> validate_locale()
  end

  defp validate_locale(locale) when locale in @locales, do: locale
  defp validate_locale(_), do: nil

  defp parse_accept_language(nil), do: nil

  defp parse_accept_language(header) do
    header
    |> String.split(",")
    |> List.first()
    |> String.split("-")
    |> List.first()
    |> String.downcase()
  end
end
