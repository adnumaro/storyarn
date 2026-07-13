defmodule StoryarnWeb.LocalizationLive.Handlers.LocalizationHandlers do
  @moduledoc """
  Event handlers for the localization LiveView.

  Handles language management (add/remove), text sync, and AI translation.
  All public functions receive `(params, socket)` and return `{:noreply, socket}`.
  """

  use Gettext, backend: Storyarn.Gettext

  import Phoenix.LiveView, only: [put_flash: 3]
  import StoryarnWeb.LocalizationLive.Helpers.LocalizationHelpers

  alias Phoenix.LiveView.Socket
  alias Storyarn.Localization

  @spec handle_add_target_language(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_add_target_language(%{"locale_code" => code}, socket) do
    do_add_target_language(socket, code)
  end

  @spec handle_change_source_language(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_change_source_language(%{"locale_code" => code}, socket) do
    case Localization.change_source_language(socket.assigns.project, code) do
      {:ok, _language} ->
        socket =
          socket
          |> reload_languages()
          |> put_flash(:info, dgettext("localization", "Source language updated."))

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("localization", "Could not update the source language.")
         )}
    end
  end

  @spec handle_remove_language(map(), Socket.t()) ::
          {:noreply, Socket.t()}
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
      {:noreply, put_flash(socket, :error, dgettext("localization", "Cannot remove the source language."))}
    end
  end

  @spec handle_sync_texts(map(), Socket.t()) ::
          {:noreply, Socket.t()}
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

  @spec handle_translate_single(map(), Socket.t()) ::
          {:noreply, Socket.t()}
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
    name = Localization.language_name(code)

    case Localization.add_language(socket.assigns.project, %{
           "locale_code" => code,
           "name" => name,
           "is_source" => false
         }) do
      {:ok, _lang} ->
        socket = reload_languages(socket)
        {:noreply, put_flash(socket, :info, dgettext("localization", "Language added."))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, dgettext("localization", "Failed to add language."))}
    end
  end
end
