defmodule StoryarnWeb.LocalizationLive.Helpers.LocalizationHelpers do
  @moduledoc """
  Pure helpers for the localization LiveView.

  Contains socket-level query helpers, label/class lookups, and
  render helpers (status_label, source_type_icon, etc.).
  """

  import Phoenix.Component, only: [assign: 3]
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Localization
  alias Storyarn.Localization.Languages
  alias Storyarn.Repo
  alias Storyarn.Screenplays.ContentUtils

  @spec load_texts(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def load_texts(socket) do
    locale = socket.assigns.selected_locale

    if locale do
      opts =
        [
          locale_code: locale,
          limit: socket.assigns.page_size,
          offset: (socket.assigns.page - 1) * socket.assigns.page_size
        ]
        |> maybe_add(:status, socket.assigns.filter_status)
        |> maybe_add(:source_type, socket.assigns.filter_source_type)
        |> maybe_add(:search, non_blank(socket.assigns.search))

      texts = Localization.list_texts(socket.assigns.project.id, opts)

      count_opts =
        [locale_code: locale]
        |> maybe_add(:status, socket.assigns.filter_status)
        |> maybe_add(:source_type, socket.assigns.filter_source_type)
        |> maybe_add(:search, non_blank(socket.assigns.search))

      total_count = Localization.count_texts(socket.assigns.project.id, count_opts)
      progress = Localization.get_progress(socket.assigns.project.id, locale)

      socket
      |> assign(:texts, texts)
      |> assign(:total_count, total_count)
      |> assign(:progress, progress)
    else
      socket
      |> assign(:texts, [])
      |> assign(:total_count, 0)
      |> assign(:progress, nil)
    end
  end

  @spec reload_languages(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
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
    existing_codes = Enum.map(assigns.languages, & &1.locale_code)
    Languages.options_for_select(exclude: existing_codes)
  end

  @spec has_active_provider?(any()) :: boolean()
  def has_active_provider?(project_id) do
    case Repo.get_by(Storyarn.Localization.ProviderConfig,
           project_id: project_id,
           provider: "deepl"
         ) do
      %{is_active: true, api_key_encrypted: key} when not is_nil(key) -> true
      _ -> false
    end
  end

  @spec maybe_add(keyword(), atom(), any()) :: keyword()
  def maybe_add(opts, _key, nil), do: opts
  def maybe_add(opts, key, value), do: Keyword.put(opts, key, value)

  @spec non_blank(String.t()) :: String.t() | nil
  def non_blank(""), do: nil
  def non_blank(s), do: s

  @spec strip_html(String.t() | nil) :: String.t()
  def strip_html(text), do: ContentUtils.strip_html(text)

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
  def source_type_label("sheet"), do: dgettext("localization", "Sheet")
  def source_type_label("flow"), do: dgettext("localization", "Flow")
  def source_type_label("screenplay"), do: dgettext("localization", "Screenplay")
  def source_type_label(other), do: other

  @spec source_type_icon(String.t()) :: String.t()
  def source_type_icon("flow_node"), do: "message-square"
  def source_type_icon("block"), do: "square"
  def source_type_icon("sheet"), do: "file-text"
  def source_type_icon("flow"), do: "git-branch"
  def source_type_icon("screenplay"), do: "clapperboard"
  def source_type_icon(_), do: "box"
end
