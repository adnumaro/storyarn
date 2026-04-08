defmodule StoryarnWeb.LocalizationLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view
  alias StoryarnWeb.Helpers.Authorize

  import StoryarnWeb.Live.Shared.TreePanelHandlers, only: [focus_layout_defaults: 0]

  alias Storyarn.Localization
  alias Storyarn.Localization.Languages
  alias Storyarn.Projects

  import StoryarnWeb.LocalizationLive.Helpers.LocalizationHelpers
  alias StoryarnWeb.LocalizationLive.Handlers.LocalizationHandlers

  @page_size 50

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      socket={@socket}
      active_tool={:localization}
      on_dashboard={true}
      has_tree={true}
      tree_panel_open={@tree_panel_open}
      tree_panel_pinned={@tree_panel_pinned}
      show_pin={false}
      can_edit={@can_edit}
      tree_props={sidebar_props(assigns)}
    >
      <:top_bar_extra_right :if={@can_edit && @target_languages != []}>
        <.vue
          v-component="modules/localization/LocalizationToolbar"
          v-socket={@socket}
          id="localization-toolbar"
          report-url={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/localization/report"}
          export-csv-url={@selected_locale && ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/localization/export/csv/#{@selected_locale}"}
          export-xlsx-url={@selected_locale && ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/localization/export/xlsx/#{@selected_locale}"}
          has-provider={@has_provider}
        />
      </:top_bar_extra_right>

      <.vue
        v-component="modules/localization/LocalizationIndex"
        v-socket={@socket}
        id="localization-index"
        texts={serialize_texts(assigns)}
        progress={@progress}
        total-count={@total_count}
        page={@page}
        page-size={@page_size}
        filter-status={@filter_status || ""}
        filter-source-type={@filter_source_type || ""}
        search={@search}
        can-edit={@can_edit}
        has-provider={@has_provider}
        has-target-languages={@target_languages != []}
      />
    </Layouts.app>
    """
  end

  @impl true
  def mount(
        %{"workspace_slug" => workspace_slug, "project_slug" => project_slug},
        _session,
        socket
      ) do
    case Projects.get_project_by_slugs(
           socket.assigns.current_scope,
           workspace_slug,
           project_slug
         ) do
      {:ok, project, membership} ->
        can_edit = Projects.can?(membership.role, :edit_content)

        # Auto-create source language from workspace if missing
        {:ok, source_language} = Localization.ensure_source_language(project)

        languages = Localization.list_languages(project.id)
        target_languages = Localization.get_target_languages(project.id)

        # Default to first target language
        selected_locale =
          case target_languages do
            [first | _] -> first.locale_code
            [] -> nil
          end

        has_provider = has_active_provider?(project.id)

        socket =
          socket
          |> assign(focus_layout_defaults())
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_edit, can_edit)
          |> assign(:source_language, source_language)
          |> assign(:languages, languages)
          |> assign(:target_languages, target_languages)
          |> assign(:selected_locale, selected_locale)
          |> assign(:has_provider, has_provider)
          |> assign(:filter_status, nil)
          |> assign(:filter_source_type, nil)
          |> assign(:search, "")
          |> assign(:page, 1)
          |> assign(:page_size, @page_size)
          |> load_texts()

        {:ok, socket}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("localization", "Project not found."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  @impl true
  def handle_event("change_locale", %{"locale" => locale}, socket) do
    {:noreply,
     socket
     |> assign(:selected_locale, locale)
     |> assign(:page, 1)
     |> load_texts()}
  end

  def handle_event("change_filter", params, socket) do
    {:noreply,
     socket
     |> maybe_assign_filter(:filter_status, params, "status")
     |> maybe_assign_filter(:filter_source_type, params, "source_type")
     |> assign(:page, 1)
     |> load_texts()}
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply,
     socket
     |> assign(:search, search)
     |> assign(:page, 1)
     |> load_texts()}
  end

  def handle_event("change_page", %{"page" => page}, socket) do
    case Integer.parse(page) do
      {page_int, ""} when page_int > 0 ->
        {:noreply,
         socket
         |> assign(:page, page_int)
         |> load_texts()}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("add_target_language", %{"locale_code" => ""}, socket),
    do: {:noreply, socket}

  def handle_event("change_source_language", %{"locale_code" => ""}, socket),
    do: {:noreply, socket}

  def handle_event("change_source_language", params, socket) do
    with_auth(:edit_content, socket, fn ->
      LocalizationHandlers.handle_change_source_language(params, socket)
    end)
  end

  def handle_event("add_target_language", params, socket) do
    with_auth(:edit_content, socket, fn ->
      LocalizationHandlers.handle_add_target_language(params, socket)
    end)
  end

  def handle_event("remove_language", params, socket) do
    with_auth(:edit_content, socket, fn ->
      LocalizationHandlers.handle_remove_language(params, socket)
    end)
  end

  def handle_event("sync_texts", params, socket) do
    with_auth(:edit_content, socket, fn ->
      LocalizationHandlers.handle_sync_texts(params, socket)
    end)
  end

  def handle_event("translate_batch", params, socket) do
    with_auth(:edit_content, socket, fn ->
      LocalizationHandlers.handle_translate_batch(params, socket)
    end)
  end

  def handle_event("translate_single", params, socket) do
    with_auth(:edit_content, socket, fn ->
      LocalizationHandlers.handle_translate_single(params, socket)
    end)
  end

  # ============================================================================
  # Serializers
  # ============================================================================

  defp sidebar_props(assigns) do
    existing_codes =
      MapSet.new(
        [assigns.source_language && assigns.source_language.locale_code | Enum.map(assigns.target_languages, & &1.locale_code)]
        |> List.flatten()
        |> Enum.reject(&is_nil/1)
      )

    source_code = assigns.source_language && assigns.source_language.locale_code

    %{
      sourceLanguage: serialize_language(assigns.source_language),
      targetLanguages: Enum.map(assigns.target_languages, &serialize_language/1),
      selectedLocale: assigns.selected_locale,
      canEdit: assigns.can_edit,
      sourceLanguageOptions:
        Languages.options_for_select(exclude: [source_code] |> Enum.reject(&is_nil/1))
        |> Enum.map(fn {label, value} -> %{label: label, value: value} end),
      addLanguageOptions:
        Languages.options_for_select(exclude: MapSet.to_list(existing_codes))
        |> Enum.map(fn {label, value} -> %{label: label, value: value} end)
    }
  end

  defp serialize_language(nil), do: nil

  defp serialize_language(lang) do
    flag_code = Languages.flag_code(lang.locale_code)

    %{
      id: lang.id,
      localeCode: lang.locale_code,
      name: lang.name || Languages.name(lang.locale_code) || lang.locale_code,
      flagUrl: flag_code && "/images/flags/1x1/#{flag_code}.svg",
      shortLabel: Languages.short_label(lang.locale_code)
    }
  end

  defp serialize_texts(assigns) do
    ws_slug = assigns.workspace.slug
    proj_slug = assigns.project.slug

    Enum.map(assigns.texts, fn text ->
      %{
        id: text.id,
        sourceText: strip_html(text.source_text),
        translatedText: text.translated_text && strip_html(text.translated_text),
        status: text.status,
        statusLabel: status_label(text.status),
        sourceType: text.source_type,
        sourceTypeLabel: source_type_label(text.source_type),
        sourceField: text.source_field,
        wordCount: text.word_count || 0,
        machineTranslated: text.machine_translated || false,
        editUrl: ~p"/workspaces/#{ws_slug}/projects/#{proj_slug}/localization/#{text.id}"
      }
    end)
  end

  # ============================================================================
  # Private helpers
  # ============================================================================

  defp with_auth(action, socket, fun) do
    case Authorize.authorize(socket, action) do
      :ok -> fun.()
      {:error, :unauthorized} -> {:noreply, unauthorized_flash(socket)}
    end
  end

  defp unauthorized_flash(socket) do
    put_flash(
      socket,
      :error,
      dgettext("localization", "You don't have permission to perform this action.")
    )
  end

  defp maybe_assign_filter(socket, assign_key, params, param_key) do
    if Map.has_key?(params, param_key) do
      assign(socket, assign_key, blank_to_nil(params[param_key]))
    else
      socket
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
