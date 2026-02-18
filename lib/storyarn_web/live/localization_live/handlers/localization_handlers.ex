defmodule StoryarnWeb.LocalizationLive.Handlers.LocalizationHandlers do
  @moduledoc """
  Event handlers for the localization LiveView.

  Handles language management (add/remove), text sync, and AI translation.
  All public functions receive `(params, socket)` and return `{:noreply, socket}`.
  """

  import Phoenix.LiveView, only: [put_flash: 3]

  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Localization
  alias Storyarn.Localization.Languages

  import StoryarnWeb.LocalizationLive.Helpers.LocalizationHelpers

  @spec handle_add_target_language(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_add_target_language(%{"locale_code" => code}, socket) do
    do_add_target_language(socket, code)
  end

  @spec handle_remove_language(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_remove_language(%{"id" => id}, socket) do
    lang = Localization.get_language(socket.assigns.project.id, id)

    if lang && !lang.is_source do
      case Localization.remove_language(lang) do
        {:ok, _} ->
          socket = reload_languages(socket)
          {:noreply, put_flash(socket, :info, dgettext("localization", "Language removed."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("localization", "Could not remove language."))}
      end
    else
      {:noreply,
       put_flash(socket, :error, dgettext("localization", "Cannot remove the source language."))}
    end
  end

  @spec handle_sync_texts(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_sync_texts(_params, socket) do
    case Localization.extract_all(socket.assigns.project.id) do
      {:ok, count} ->
        socket =
          socket
          |> reload_languages()
          |> put_flash(
            :info,
            dngettext(
              "localization",
              "Synced %{count} text entry.",
              "Synced %{count} text entries.",
              count,
              count: count
            )
          )

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("localization", "Sync failed."))}
    end
  end

  @spec handle_translate_batch(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_translate_batch(_params, socket) do
    locale = socket.assigns.selected_locale

    case Localization.translate_batch(socket.assigns.project.id, locale) do
      {:ok, %{translated: count}} ->
        socket =
          socket
          |> load_texts()
          |> put_flash(
            :info,
            dngettext(
              "localization",
              "Translated %{count} string.",
              "Translated %{count} strings.",
              count,
              count: count
            )
          )

        {:noreply, socket}

      {:error, :rate_limited} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("localization", "Rate limited by DeepL. Try again later.")
         )}

      {:error, :quota_exceeded} ->
        {:noreply,
         put_flash(socket, :error, dgettext("localization", "DeepL quota exceeded."))}

      {:error, reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("localization", "Translation failed: %{reason}", reason: inspect(reason))
         )}
    end
  end

  @spec handle_translate_single(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_translate_single(%{"id" => id}, socket) do
    case Integer.parse(id) do
      {text_id, ""} ->
        do_translate_single(socket, text_id)

      _ ->
        {:noreply, put_flash(socket, :error, dgettext("localization", "Invalid text ID."))}
    end
  end

  defp do_translate_single(socket, text_id) do
    case Localization.translate_single(socket.assigns.project.id, text_id) do
      {:ok, _text} ->
        socket =
          socket
          |> load_texts()
          |> put_flash(:info, dgettext("localization", "Translation complete."))

        {:noreply, socket}

      {:error, reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("localization", "Translation failed: %{reason}", reason: inspect(reason))
         )}
    end
  end

  # Private

  defp do_add_target_language(socket, code) do
    name = Languages.name(code)

    case Localization.add_language(socket.assigns.project, %{
           "locale_code" => code,
           "name" => name,
           "is_source" => false
         }) do
      {:ok, _lang} ->
        count =
          case Localization.extract_all(socket.assigns.project.id) do
            {:ok, c} -> c
            {:error, _} -> 0
          end

        socket = reload_languages(socket)

        msg =
          if count > 0,
            do:
              dngettext(
                "localization",
                "Language added. Extracted %{count} text.",
                "Language added. Extracted %{count} texts.",
                count,
                count: count
              ),
            else: dgettext("localization", "Language added.")

        {:noreply, put_flash(socket, :info, msg)}

      {:error, _changeset} ->
        {:noreply,
         put_flash(socket, :error, dgettext("localization", "Failed to add language."))}
    end
  end
end
