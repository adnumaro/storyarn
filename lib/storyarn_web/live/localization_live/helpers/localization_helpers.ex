defmodule StoryarnWeb.LocalizationLive.Helpers.LocalizationHelpers do
  @moduledoc """
  Pure helpers for the localization LiveViews.

  Contains socket-level query helpers, the closed filter vocabularies of the
  workbench, and label lookups (status, content role, voice-over state).
  """

  use StoryarnWeb, :verified_routes
  use Gettext, backend: Storyarn.Gettext

  import Phoenix.Component, only: [assign: 3]

  alias Phoenix.LiveView.Socket
  alias Storyarn.Localization

  @statuses ~w(pending draft in_progress review final)
  @source_types ~w(flow_node block sheet)
  @vo_statuses ~w(none needed recorded approved)

  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  @spec source_types() :: [String.t()]
  def source_types, do: @source_types

  @spec vo_statuses() :: [String.t()]
  def vo_statuses, do: @vo_statuses

  @doc """
  Loads the workbench rows for the selected locale.

  `:replace` reloads every page loaded so far (pages 1..`page`) so a refresh
  after a save keeps the rows the translator scrolled to; `:append` fetches
  only the current page and appends it to the loaded rows.
  """
  @spec load_texts(Socket.t(), :replace | :append) :: Socket.t()
  def load_texts(socket, mode \\ :replace) do
    locale = socket.assigns.selected_locale

    if locale do
      project_id = socket.assigns.project.id
      filter_opts = text_filter_opts(socket.assigns)
      page = socket.assigns.page
      page_size = socket.assigns.page_size

      {limit, offset} =
        case mode do
          :append -> {page_size, (page - 1) * page_size}
          :replace -> {page * page_size, 0}
        end

      texts =
        Localization.list_texts(
          project_id,
          filter_opts ++ [limit: limit, offset: offset, preload: [:speaker_sheet]]
        )

      texts = if mode == :append, do: (socket.assigns[:texts] || []) ++ texts, else: texts

      socket
      |> assign(:texts, texts)
      |> assign(:total_count, Localization.count_texts(project_id, filter_opts))
      |> assign(:progress, Localization.get_progress(project_id, locale))
    else
      socket
      |> assign(:texts, [])
      |> assign(:total_count, 0)
      |> assign(:progress, nil)
    end
  end

  @doc "Builds the `Localization.list_texts/2` filter options from the workbench filter assigns."
  @spec text_filter_opts(map()) :: keyword()
  def text_filter_opts(assigns) do
    [locale_code: assigns.selected_locale]
    |> maybe_add(:status, assigns[:filter_status])
    |> maybe_add(:source_type, assigns[:filter_source_type])
    |> maybe_add(:vo_status, assigns[:filter_vo_status])
    |> maybe_add(:speaker_sheet_id, assigns[:filter_speaker])
    |> maybe_add(:stale, if(assigns[:filter_stale], do: true))
    |> maybe_add(:search, non_blank(assigns[:search] || ""))
  end

  @spec reload_languages(Socket.t()) :: Socket.t()
  def reload_languages(socket) do
    project_id = socket.assigns.project.id
    languages = Localization.list_languages(project_id)
    target_languages = Localization.get_target_languages(project_id)
    source_language = Localization.get_source_language(project_id)

    current_locale = socket.assigns[:selected_locale]
    locale_codes = Enum.map(target_languages, & &1.locale_code)

    selected_locale =
      cond do
        current_locale in locale_codes -> current_locale
        match?([_ | _], target_languages) -> hd(target_languages).locale_code
        true -> nil
      end

    page = if selected_locale == current_locale, do: socket.assigns[:page] || 1, else: 1

    socket
    |> assign(:languages, languages)
    |> assign(:target_languages, target_languages)
    |> assign(:source_language, source_language)
    |> assign(:selected_locale, selected_locale)
    |> assign(:page, page)
    |> load_texts()
  end

  @spec language_picker_options(map()) :: list()
  def language_picker_options(assigns) do
    existing_codes =
      assigns.languages
      |> Enum.map(& &1.locale_code)
      |> maybe_add_source_locale(assigns[:source_language])
      |> Enum.uniq()

    Localization.language_options_for_select(exclude: existing_codes)
  end

  @spec has_active_provider?(any()) :: boolean()
  def has_active_provider?(project_id) do
    Localization.has_active_provider?(project_id)
  end

  @spec maybe_add(keyword(), atom(), any()) :: keyword()
  def maybe_add(opts, _key, nil), do: opts
  def maybe_add(opts, key, value), do: Keyword.put(opts, key, value)

  @spec non_blank(String.t()) :: String.t() | nil
  def non_blank(""), do: nil
  def non_blank(s), do: s

  defp maybe_add_source_locale(codes, %{locale_code: locale_code}) when is_binary(locale_code), do: [locale_code | codes]

  defp maybe_add_source_locale(codes, _source_language), do: codes

  @spec strip_html(String.t() | nil) :: String.t()
  def strip_html(text), do: Storyarn.Platform.Shared.HtmlUtils.strip_html(text)

  @spec status_label(String.t()) :: String.t()
  def status_label("pending"), do: dgettext("localization", "Pending")
  def status_label("draft"), do: dgettext("localization", "Draft")
  def status_label("in_progress"), do: dgettext("localization", "In Progress")
  def status_label("review"), do: dgettext("localization", "Review")
  def status_label("final"), do: dgettext("localization", "Final")
  def status_label(other), do: other

  @spec status_class(String.t()) :: String.t()
  def status_class("pending"), do: "badge-ghost"
  def status_class("draft"), do: "badge-warning"
  def status_class("in_progress"), do: "badge-info"
  def status_class("review"), do: "badge-secondary"
  def status_class("final"), do: "badge-success"
  def status_class(_), do: "badge-ghost"

  @spec source_type_label(String.t()) :: String.t()
  def source_type_label("flow_node"), do: dgettext("localization", "Node")
  def source_type_label("block"), do: dgettext("localization", "Block")
  def source_type_label("sheet"), do: dgettext("localization", "Sheet name")
  def source_type_label(other), do: other

  @spec source_type_icon(String.t()) :: String.t()
  def source_type_icon("flow_node"), do: "message-square"
  def source_type_icon("block"), do: "square"
  def source_type_icon("sheet"), do: "user-round"
  def source_type_icon(_), do: "box"

  @doc "Names a string by what it is in the game, not by the entity it was extracted from."
  @spec content_role_label(String.t() | nil) :: String.t()
  def content_role_label("dialogue"), do: dgettext("localization", "Dialogue")
  def content_role_label("response"), do: dgettext("localization", "Response")
  def content_role_label("stage_direction"), do: dgettext("localization", "Stage direction")
  def content_role_label("menu"), do: dgettext("localization", "Menu")
  def content_role_label("exit"), do: dgettext("localization", "Exit")
  def content_role_label("runtime_value"), do: dgettext("localization", "Variable")
  def content_role_label("speaker_name"), do: dgettext("localization", "Speaker name")
  def content_role_label(other) when is_binary(other), do: other
  def content_role_label(_other), do: dgettext("localization", "Variable")

  @spec vo_status_label(String.t() | nil) :: String.t()
  def vo_status_label("needed"), do: dgettext("localization", "Needed")
  def vo_status_label("recorded"), do: dgettext("localization", "Recorded")
  def vo_status_label("approved"), do: dgettext("localization", "Approved")
  def vo_status_label(_other), do: dgettext("localization", "Not required")
end
