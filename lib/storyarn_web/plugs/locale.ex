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
  @direct_match_rank 0
  @fallback_match_rank 1
  @wildcard_match_rank 2
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
    do_negotiate_accept_language(header, @normalized_locales, @default_locale)
  end

  @doc false
  def negotiate_accept_language(header, locales, default_locale)
      when is_binary(header) and is_list(locales) and is_binary(default_locale) do
    normalized_locales =
      Enum.map(locales, fn locale ->
        {locale, normalize_language_tag(locale)}
      end)

    do_negotiate_accept_language(header, normalized_locales, default_locale)
  end

  defp do_negotiate_accept_language("", _normalized_locales, _default_locale), do: nil

  defp do_negotiate_accept_language(header, normalized_locales, default_locale) do
    preferences =
      header
      |> String.split(",")
      |> Enum.with_index()
      |> Enum.map(&parse_language_preference/1)
      |> Enum.reject(&is_nil/1)

    wildcard_preference =
      preferences
      |> Enum.filter(fn {language_range, _quality, _index} -> language_range == "*" end)
      |> best_preference()
      |> tag_preference(:wildcard, nil)

    normalized_locales
    |> Enum.with_index()
    |> Enum.map(fn {{locale, normalized_locale}, locale_index} ->
      explicit_preference = preference_for_locale(preferences, normalized_locale)

      case explicit_preference || wildcard_preference do
        {_language_range, quality, index, match_rank, match_distance} when quality > 0 ->
          {locale, quality, match_rank, match_distance, index, locale_index}

        _other ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(fn {locale, quality, match_rank, match_distance, index, locale_index} ->
      default_rank = if locale == default_locale, do: 0, else: 1
      {-quality, match_rank, match_distance, index, default_rank, locale_index}
    end)
    |> List.first()
    |> case do
      {locale, _quality, _match_rank, _match_distance, _index, _locale_index} -> locale
      nil -> nil
    end
  end

  defp preference_for_locale(preferences, normalized_locale) do
    direct_preference =
      preferences
      |> Enum.filter(fn {language_range, _quality, _index} ->
        language_range != "*" and
          direct_language_range_matches_locale?(language_range, normalized_locale)
      end)
      |> best_preference()

    case direct_preference do
      nil ->
        preferences
        |> Enum.filter(fn {language_range, _quality, _index} ->
          language_range != "*" and
            fallback_language_range_matches_locale?(language_range, normalized_locale)
        end)
        |> best_fallback_preference()
        |> tag_preference(:fallback, normalized_locale)

      preference ->
        tag_preference(preference, :direct, normalized_locale)
    end
  end

  defp tag_preference(nil, _match_type, _normalized_locale), do: nil

  defp tag_preference({language_range, quality, index}, :fallback, normalized_locale) do
    distance =
      language_range_specificity(language_range) -
        language_range_specificity(normalized_locale)

    {language_range, quality, index, @fallback_match_rank, distance}
  end

  defp tag_preference({language_range, quality, index}, :direct, _normalized_locale) do
    {language_range, quality, index, @direct_match_rank, 0}
  end

  defp tag_preference({language_range, quality, index}, :wildcard, _normalized_locale) do
    {language_range, quality, index, @wildcard_match_rank, 0}
  end

  defp best_preference(preferences) do
    preferences
    |> Enum.sort_by(fn {language_range, quality, index} ->
      {-language_range_specificity(language_range), -quality, index}
    end)
    |> List.first()
  end

  defp best_fallback_preference(preferences) do
    preferences
    |> Enum.sort_by(fn {language_range, quality, index} ->
      {-quality, index, -language_range_specificity(language_range)}
    end)
    |> List.first()
  end

  defp language_range_specificity("*"), do: 0

  defp language_range_specificity(language_range) do
    language_range
    |> String.split("-")
    |> length()
  end

  defp parse_language_preference({preference, index}) do
    case String.split(preference, ";", trim: true) do
      [language_range | parameters] ->
        with language_range when language_range != "" <- normalize_language_tag(language_range),
             {:ok, quality} <- parse_quality(parameters) do
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

  defp direct_language_range_matches_locale?(language_range, normalized_locale) do
    language_range == normalized_locale or
      String.starts_with?(normalized_locale, language_range <> "-")
  end

  defp fallback_language_range_matches_locale?(language_range, normalized_locale) do
    String.starts_with?(language_range, normalized_locale <> "-")
  end

  defp normalize_language_tag(language_tag) do
    language_tag
    |> String.trim()
    |> String.replace("_", "-")
    |> String.downcase()
  end
end
