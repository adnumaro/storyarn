defmodule StoryarnWeb.PublicLocale do
  @moduledoc """
  Makes the URL authoritative for locale-aware public LiveViews.

  The hook is safe to install on the shared `:current_user` live session:
  authentication, invitation, and other non-public routes retain the user's
  existing language preference.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, get_connect_info: 2]

  alias Storyarn.Publication.Locales, as: PublicLocales
  alias StoryarnWeb.PublicURLs

  @known_locales Gettext.known_locales(Storyarn.Gettext)

  @doc false
  def session(conn) do
    case conn.private[:public_locale] do
      locale when is_binary(locale) -> %{"public_locale" => locale}
      _other -> %{}
    end
  end

  def on_mount(:set_locale, params, session, socket) do
    preferred_locale = socket.assigns[:locale] || session["locale"] || PublicLocales.default_locale()
    initial_locale = public_locale_from_mount(socket, session) || locale_from_params(params) || preferred_locale

    {:cont, install(socket, initial_locale, preferred_locale)}
  end

  def on_mount({:set_locale, locale}, _params, _session, socket) do
    preferred_locale = socket.assigns[:locale] || PublicLocales.default_locale()
    {:cont, install(socket, locale, preferred_locale)}
  end

  defp public_locale_from_mount(socket, session) do
    case get_connect_info(socket, :uri) do
      %URI{} = uri -> PublicURLs.locale_from_uri(uri)
      uri when is_binary(uri) -> PublicURLs.locale_from_uri(uri)
      _other -> session_locale(session)
    end
  end

  defp session_locale(%{"public_locale" => locale}) when is_binary(locale), do: locale
  defp session_locale(_session), do: nil

  defp install(socket, locale, preferred_locale) do
    socket
    |> put_locale(locale)
    |> attach_hook(:public_locale, :handle_params, fn params, uri, socket ->
      locale = PublicURLs.locale_from_uri(uri) || locale_from_params(params) || preferred_locale
      {:cont, put_locale(socket, locale)}
    end)
  end

  defp locale_from_params(%{"locale" => locale}) when locale in @known_locales, do: locale
  defp locale_from_params(_params), do: nil

  defp put_locale(socket, locale) do
    Gettext.put_locale(Storyarn.Gettext, locale)
    assign(socket, :locale, locale)
  end
end
