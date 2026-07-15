defmodule StoryarnWeb.Plugs.Locale do
  @moduledoc """
  Plug for handling locale detection and switching.

  Checks locale in this order:
  1. Canonical public URL for that response (unprefixed is English, `/es/...` is Spanish)
  2. URL parameter (?locale=es)
  3. User's saved locale preference (from DB)
  4. Session value
  5. Accept-Language header
  6. Default locale (en)
  """
  import Plug.Conn

  alias Storyarn.Publication.Locales, as: PublicLocales
  alias StoryarnWeb.PublicURLs

  @locales Gettext.known_locales(Storyarn.Gettext)
  @default_locale PublicLocales.default_locale()
  @normalized_locales Enum.map(@locales, fn locale ->
                        normalized =
                          locale
                          |> String.replace("_", "-")
                          |> String.downcase()

                        {locale, normalized}
                      end)

  def init(opts), do: opts

  def call(conn, _opts) do
    path_locale = PublicURLs.locale_from_path(conn.request_path)
    param_locale = get_locale_from_params(conn)
    user_locale = get_locale_from_user(conn)
    session_locale = get_locale_from_session(conn)
    header_locale = get_locale_from_header(conn)

    preferred_locale =
      param_locale || user_locale || session_locale || header_locale || @default_locale

    locale = path_locale || preferred_locale

    Gettext.put_locale(Storyarn.Gettext, locale)

    conn
    |> persist_preferred_locale(param_locale, user_locale, session_locale, preferred_locale)
    |> assign(:locale, locale)
  end

  # A localized public URL changes only that content response, not the global preference.
  defp persist_preferred_locale(conn, param_locale, _user_locale, _session_locale, _preferred_locale)
       when is_binary(param_locale), do: put_session(conn, :locale, param_locale)

  # The DB preference is the source of truth, so discard any stale session value.
  defp persist_preferred_locale(conn, _param_locale, user_locale, _session_locale, _preferred_locale)
       when is_binary(user_locale), do: delete_session(conn, :locale)

  defp persist_preferred_locale(conn, _param_locale, _user_locale, session_locale, _preferred_locale)
       when is_binary(session_locale), do: conn

  # Persist header detection so the LiveView WebSocket can read the same preference.
  defp persist_preferred_locale(conn, _param_locale, _user_locale, _session_locale, preferred_locale),
    do: put_session(conn, :locale, preferred_locale)

  defp get_locale_from_user(conn) do
    case conn.assigns do
      %{current_scope: %{user: %{locale: locale}}} when is_binary(locale) ->
        validate_locale(locale)

      _ ->
        nil
    end
  end

  defp get_locale_from_params(conn) do
    conn = fetch_query_params(conn)
    validate_locale(conn.query_params["locale"])
  end

  defp get_locale_from_session(conn) do
    conn |> get_session(:locale) |> validate_locale()
  end

  defp get_locale_from_header(conn) do
    conn
    |> get_req_header("accept-language")
    |> Enum.join(",")
    |> parse_accept_language()
  end

  defp validate_locale(locale) when locale in @locales, do: locale
  defp validate_locale(_), do: nil

  defp parse_accept_language(""), do: nil

  defp parse_accept_language(header) do
    header
    |> String.split(",")
    |> Enum.with_index()
    |> Enum.map(&parse_language_preference/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(fn {_language_range, quality, index} -> {-quality, index} end)
    |> Enum.find_value(fn {language_range, _quality, _index} ->
      match_known_locale(language_range)
    end)
  end

  defp parse_language_preference({preference, index}) do
    case String.split(preference, ";", trim: true) do
      [language_range | parameters] ->
        with language_range when language_range != "" <- normalize_language_tag(language_range),
             {:ok, quality} <- parse_quality(parameters),
             true <- quality > 0 do
          {language_range, quality, index}
        else
          _ -> nil
        end

      [] ->
        nil
    end
  end

  defp parse_quality(parameters) do
    case Enum.find_value(parameters, &quality_parameter/1) do
      nil -> {:ok, 1.0}
      result -> result
    end
  end

  defp quality_parameter(parameter) do
    case String.split(parameter, "=", parts: 2) do
      [name, value] ->
        if String.downcase(String.trim(name)) == "q" do
          parse_quality_value(String.trim(value))
        end

      _ ->
        nil
    end
  end

  defp parse_quality_value(value) do
    case Float.parse(value) do
      {quality, ""} when quality >= 0 and quality <= 1 -> {:ok, quality}
      _ -> :error
    end
  end

  defp match_known_locale("*"), do: @default_locale

  defp match_known_locale(language_range) do
    exact_locale(language_range) || base_locale(language_range)
  end

  defp exact_locale(language_range) do
    Enum.find_value(@normalized_locales, fn
      {locale, ^language_range} -> locale
      _ -> nil
    end)
  end

  defp base_locale(language_range) do
    base_language = language_range |> String.split("-", parts: 2) |> List.first()

    Enum.find_value(@normalized_locales, fn
      {locale, ^base_language} -> locale
      _ -> nil
    end) ||
      Enum.find_value(@normalized_locales, fn {locale, normalized_locale} ->
        if String.starts_with?(normalized_locale, base_language <> "-"), do: locale
      end)
  end

  defp normalize_language_tag(language_tag) do
    language_tag
    |> String.trim()
    |> String.replace("_", "-")
    |> String.downcase()
  end
end
