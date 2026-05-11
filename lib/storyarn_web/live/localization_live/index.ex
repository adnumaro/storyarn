defmodule StoryarnWeb.LocalizationLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view

  import StoryarnWeb.LocalizationLive.Helpers.LocalizationHelpers

  alias Storyarn.Localization
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.Live.Shared.ProjectChromeHelpers
  alias StoryarnWeb.LocalizationLive.Handlers.LocalizationHandlers

  @page_size 50

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.ProjectLayout.project_layout
      socket={@socket}
      project={@project}
      workspace={@workspace}
      current_scope={@current_scope}
      current_user={@current_user}
      urls={@urls}
      active_tool={:localization}
      is_super_admin={@is_super_admin}
      online_users={@online_users}
      sidebar_module={StoryarnWeb.LocalizationSidebarLive}
      sidebar_session={
        %{
          "project_id" => @project.id,
          "workspace_slug" => @workspace.slug,
          "project_slug" => @project.slug,
          "selected_locale" => @selected_locale,
          "can_edit" => @can_edit,
          "active_tool" => "localization",
          "dashboard_url" =>
            ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/localization",
          "current_scope" => @current_scope,
          "locale" => @locale
        }
      }
    >
      <%= if @can_edit && @target_languages != [] do %>
        {live_render(@socket, StoryarnWeb.LocalizationToolbarLive,
          id: "localization-toolbar-#{@project.id}",
          sticky: true,
          session: %{
            "project_id" => @project.id,
            "workspace_slug" => @workspace.slug,
            "project_slug" => @project.slug,
            "selected_locale" => @selected_locale,
            "has_provider" => @has_provider,
            "can_edit" => @can_edit,
            "current_scope" => @current_scope,
            "locale" => @locale,
            "inject_target" => "project-layout"
          }
        )}
      <% end %>

      <.vue
        v-component="live/localization/texts/Index"
        v-socket={@socket}
        v-inject="project-layout"
        id="localization-index"
        class="contents"
        texts={serialize_texts(assigns)}
        progress={@progress}
        total-count={@total_count}
        pagination={%{page: @page, pageSize: @page_size}}
        filter-status={@filter_status || ""}
        filter-source-type={@filter_source_type || ""}
        search={@search}
        can-edit={@can_edit}
        has-provider={@has_provider}
        has-target-languages={@target_languages != []}
      />
    </StoryarnWeb.Components.ProjectLayout.project_layout>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    %{project: project} = socket.assigns

    # Auto-create source language from workspace if missing
    {:ok, source_language} = Localization.ensure_source_language(project)

    languages = Localization.list_languages(project.id)
    target_languages = Localization.get_target_languages(project.id)

    has_provider = has_active_provider?(project.id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(
        Storyarn.PubSub,
        StoryarnWeb.LocalizationSidebarLive.shell_topic(project.id)
      )
    end

    socket =
      socket
      |> assign(:source_language, source_language)
      |> assign(:languages, languages)
      |> assign(:target_languages, target_languages)
      # selected_locale is driven by the URL — filled in by handle_params
      |> assign(:selected_locale, nil)
      |> assign(:has_provider, has_provider)
      |> assign(:filter_status, nil)
      |> assign(:filter_source_type, nil)
      |> assign(:search, "")
      |> assign(:page, 1)
      |> assign(:page_size, @page_size)
      |> assign(:texts, [])
      |> assign(:total_count, 0)
      |> assign(:progress, %{total: 0, pending: 0, draft: 0, in_progress: 0, review: 0, final: 0})
      |> assign(:online_users, ProjectChromeHelpers.initial_online_users(project.id))

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"locale" => locale}, _url, socket) do
    if locale == socket.assigns.selected_locale do
      {:noreply, socket}
    else
      # Broadcast so LocalizationSidebarLive updates the highlighted target.
      Phoenix.PubSub.broadcast(
        Storyarn.PubSub,
        StoryarnWeb.LocalizationSidebarLive.shell_topic(socket.assigns.project.id),
        {:active_locale, locale}
      )

      {:noreply,
       socket
       |> assign(:selected_locale, locale)
       |> assign(:page, 1)
       |> load_texts()}
    end
  end

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  # Tree panel + localization mutations (change_locale, add/remove language,
  # sync_texts) live in LocalizationSidebarLive. translate_batch lives in
  # LocalizationToolbarLive. ProjectNavbarContext.vue's main_sidebar_* events fire
  # here; forward them to the sidebar via shell topic.

  @impl true
  def handle_event("main_sidebar_" <> _ = event, params, socket),
    do: ProjectChromeHelpers.forward_main_sidebar(socket, event, params)

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

  def handle_event("translate_single", params, socket) do
    with_auth(:edit_content, socket, fn ->
      LocalizationHandlers.handle_translate_single(params, socket)
    end)
  end

  # ============================================================================
  # Shell fan-in
  # ============================================================================

  # Sidebar broadcast when the user picks a different locale.
  @impl true
  def handle_info({:active_locale, locale}, socket) do
    socket =
      socket
      |> assign(:selected_locale, locale)
      |> assign(:page, 1)
      |> load_texts()

    {:noreply, socket}
  end

  # Sidebar broadcast after a language mutation (add/remove/sync).
  def handle_info({:languages_changed, _payload}, socket) do
    project_id = socket.assigns.project.id
    target_languages = Localization.get_target_languages(project_id)
    has_provider = has_active_provider?(project_id)

    {:noreply,
     socket
     |> assign(:target_languages, target_languages)
     |> assign(:has_provider, has_provider)
     |> load_texts()}
  end

  # Ignore toolbar-forwarded panel events; they're the sidebar's concern.
  def handle_info({:toolbar_event, _name, _params}, socket), do: {:noreply, socket}

  def handle_info({:online_users, users}, socket), do: {:noreply, assign(socket, :online_users, users)}

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ============================================================================
  # Serializers
  # ============================================================================

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
        editUrl: ~p"/workspaces/#{ws_slug}/projects/#{proj_slug}/localization/text/#{text.id}"
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

  # Treat blanks and the "all" sentinel (used by the Vue select to clear
  # filter selection) as "no filter".
  defp blank_to_nil(""), do: nil
  defp blank_to_nil("all"), do: nil
  defp blank_to_nil(value), do: value
end
