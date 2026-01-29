defmodule StoryarnWeb.Plugs.Locale do
  @moduledoc """
  Plug for handling locale detection and switching.

  Checks locale in this order:
  1. URL parameter (?locale=es)
  2. Session value
  3. Accept-Language header
  4. Default locale (en)
  """
  import Plug.Conn

  @locales Gettext.known_locales(StoryarnWeb.Gettext)
  @default_locale "en"

  def init(opts), do: opts

  def call(conn, _opts) do
    locale =
      get_locale_from_params(conn) ||
        get_locale_from_session(conn) ||
        get_locale_from_header(conn) ||
        @default_locale

    Gettext.put_locale(StoryarnWeb.Gettext, locale)

    conn
    |> put_session(:locale, locale)
    |> assign(:locale, locale)
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
