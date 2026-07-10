defmodule StoryarnWeb.LocalizationLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view

  import StoryarnWeb.LocalizationLive.Helpers.LocalizationHelpers

  alias Storyarn.Localization
  alias Storyarn.Localization.HtmlHandler
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Shared.HtmlSanitizer
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.Live.Shared.ProjectChromeHelpers

  @page_size 50

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.ProjectLayout.project
      socket={@socket}
      flash={@flash}
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
            "filters" => %{
              "status" => @filter_status,
              "source_type" => @filter_source_type,
              "search" => @search
            },
            "current_scope" => @current_scope,
            "locale" => @locale,
            "inject_target" => "project-layout"
          }
        )}
      <% end %>

      <.vue
        v-component="live/localization/texts/LocalizationTextsIndex"
        v-socket={@socket}
        v-inject="project-layout"
        id="localization-index"
        class="contents"
        texts={serialize_texts(assigns)}
        progress={@progress}
        total-count={@total_count}
        pagination={%{page: @page, pageSize: @page_size}}
        filters={
          %{status: @filter_status || "", sourceType: @filter_source_type || "", search: @search}
        }
        capabilities={
          %{
            canEdit: @can_edit,
            hasProvider: @has_provider,
            hasTargetLanguages: @target_languages != []
          }
        }
        selected-text={serialize_selected_text(assigns)}
        selected-locale-name={selected_locale_name(assigns)}
      />
    </StoryarnWeb.Components.ProjectLayout.project>
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
      |> assign(:selected_text, nil)
      |> assign(:total_count, 0)
      |> assign(:progress, %{total: 0, pending: 0, draft: 0, in_progress: 0, review: 0, final: 0, stale: 0})
      |> assign(:online_users, ProjectChromeHelpers.initial_online_users(project.id))

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"locale" => locale} = params, _url, socket) do
    socket =
      if locale == socket.assigns.selected_locale do
        socket
      else
        # Broadcast so LocalizationSidebarLive updates the highlighted target.
        Phoenix.PubSub.broadcast(
          Storyarn.PubSub,
          StoryarnWeb.LocalizationSidebarLive.shell_topic(socket.assigns.project.id),
          {:active_locale, locale}
        )

        socket
        |> assign(:selected_locale, locale)
        |> assign(:page, 1)
        |> load_texts()
      end

    {:noreply, assign_selected_text(socket, params["id"])}
  end

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("change_filter", params, socket) do
    socket =
      socket
      |> maybe_assign_filter(:filter_status, params, "status")
      |> maybe_assign_filter(:filter_source_type, params, "source_type")
      |> assign(:page, 1)
      |> load_texts()

    broadcast_filters(socket)
    {:noreply, socket}
  end

  def handle_event("search", %{"search" => search}, socket) do
    socket =
      socket
      |> assign(:search, search)
      |> assign(:page, 1)
      |> load_texts()

    broadcast_filters(socket)
    {:noreply, socket}
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
      translate_single(params, socket)
    end)
  end

  def handle_event("select_text", %{"id" => id}, socket) do
    case parse_id(id) do
      {:ok, text_id} ->
        {:noreply,
         push_patch(socket,
           to:
             ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/localization/texts/#{socket.assigns.selected_locale}/#{text_id}"
         )}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("close_editor", _params, socket) do
    {:noreply,
     push_patch(socket,
       to:
         ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/localization/texts/#{socket.assigns.selected_locale}"
     )}
  end

  def handle_event("save_translation", %{"id" => id, "lock_version" => lock_version, "localized_text" => params}, socket) do
    with_auth(:edit_content, socket, fn ->
      save_translation(socket, id, lock_version, params)
    end)
  end

  # ============================================================================
  # Shell fan-in
  # ============================================================================

  # Sidebar broadcast when the user picks a different locale.
  @impl true
  def handle_info({:active_locale, locale}, %{assigns: %{selected_locale: locale}} = socket) do
    {:noreply, socket}
  end

  def handle_info({:active_locale, locale}, socket) do
    socket =
      socket
      |> assign(:selected_locale, locale)
      |> assign(:page, 1)
      |> assign(:selected_text, nil)
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
     |> load_texts()
     |> reload_selected_text()}
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
        stale: LocalizedText.stale?(text),
        sourceTypeIcon: source_type_icon(text.source_type),
        editUrl: ~p"/workspaces/#{ws_slug}/projects/#{proj_slug}/localization/texts/#{text.locale_code}/#{text.id}"
      }
    end)
  end

  defp serialize_selected_text(%{selected_text: nil}), do: nil

  defp serialize_selected_text(%{selected_text: text} = assigns) do
    %{
      id: text.id,
      sourceType: text.source_type,
      sourceTypeLabel: source_type_label(text.source_type),
      sourceField: text.source_field,
      sourceReference: "#{source_type_label(text.source_type)} ##{text.source_id} · #{text.source_field}",
      sourceHtml: HtmlSanitizer.sanitize_html(text.source_text || ""),
      sourceText: strip_html(text.source_text),
      wordCount: text.word_count || 0,
      localeCode: text.locale_code,
      localeName: selected_locale_name(assigns),
      translatedText: text.translated_text || "",
      status: text.status,
      translatorNotes: text.translator_notes || "",
      voStatus: text.vo_status || "none",
      machineTranslated: text.machine_translated || false,
      lastTranslatedAt: text.last_translated_at && DateTime.to_iso8601(text.last_translated_at),
      stale: LocalizedText.stale?(text),
      placeholders: HtmlHandler.placeholders(text.source_text),
      lockVersion: text.lock_version
    }
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

  defp selected_locale_name(%{selected_locale: nil}), do: ""

  defp selected_locale_name(assigns) do
    case Enum.find(assigns.target_languages, &(&1.locale_code == assigns.selected_locale)) do
      nil -> Localization.language_name(assigns.selected_locale)
      language -> language.name
    end
  end

  defp assign_selected_text(socket, nil), do: assign(socket, :selected_text, nil)

  defp assign_selected_text(socket, id) do
    with {:ok, text_id} <- parse_id(id),
         text when not is_nil(text) <- Localization.get_text(socket.assigns.project.id, text_id),
         true <- text.locale_code == socket.assigns.selected_locale do
      assign(socket, :selected_text, text)
    else
      _reason -> assign(socket, :selected_text, nil)
    end
  end

  defp reload_selected_text(%{assigns: %{selected_text: nil}} = socket), do: socket

  defp reload_selected_text(socket) do
    assign_selected_text(socket, socket.assigns.selected_text.id)
  end

  defp translate_single(%{"id" => id}, socket) do
    with {:ok, text_id} <- parse_id(id),
         {:ok, updated} <- Localization.translate_single(socket.assigns.project.id, text_id) do
      socket =
        socket
        |> load_texts()
        |> assign(:selected_text, updated)

      {:reply, %{ok: true, text: serialize_selected_text(socket.assigns)}, socket}
    else
      {:error, reason} -> {:reply, %{ok: false, error: inspect(reason)}, socket}
      :error -> {:reply, %{ok: false, error: "invalid_id"}, socket}
    end
  end

  defp save_translation(socket, id, lock_version, params) do
    with {:ok, text_id} <- parse_id(id),
         {:ok, expected_lock} <- parse_id(lock_version),
         text when not is_nil(text) <- Localization.get_text(socket.assigns.project.id, text_id) do
      save_with_lock(socket, text_id, text, expected_lock, params)
    else
      _reason -> {:reply, %{ok: false, error: "text_not_found"}, socket}
    end
  end

  defp save_with_lock(socket, text_id, %LocalizedText{lock_version: expected_lock} = text, expected_lock, params) do
    params = Map.put(params, "translated_by_id", socket.assigns.current_scope.user.id)

    case Localization.update_text(text, params) do
      {:ok, updated} -> successful_save_reply(socket, updated)
      {:error, changeset} -> failed_save_reply(socket, text_id, changeset)
    end
  end

  defp save_with_lock(socket, _text_id, text, _expected_lock, _params), do: conflict_reply(socket, text)

  defp successful_save_reply(socket, updated) do
    socket = socket |> load_texts() |> assign(:selected_text, updated)
    {:reply, %{ok: true, text: serialize_selected_text(socket.assigns)}, socket}
  end

  defp failed_save_reply(socket, text_id, changeset) do
    if Keyword.has_key?(changeset.errors, :lock_version) do
      latest_conflict_reply(socket, text_id)
    else
      {:reply, %{ok: false, errors: changeset_errors(changeset)}, socket}
    end
  end

  defp latest_conflict_reply(socket, text_id) do
    case Localization.get_text(socket.assigns.project.id, text_id) do
      nil -> {:reply, %{ok: false, error: "text_not_found"}, socket}
      current -> conflict_reply(socket, current)
    end
  end

  defp conflict_reply(socket, current) do
    assigns = Map.put(socket.assigns, :selected_text, current)
    {:reply, %{ok: false, conflict: true, text: serialize_selected_text(assigns)}, socket}
  end

  defp changeset_errors(changeset) do
    Map.new(changeset.errors, fn {field, {message, _metadata}} -> {field, message} end)
  end

  defp parse_id(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> {:ok, id}
      _other -> :error
    end
  end

  defp parse_id(_value), do: :error

  defp broadcast_filters(socket) do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      StoryarnWeb.LocalizationSidebarLive.shell_topic(socket.assigns.project.id),
      {:localization_filters,
       %{
         "status" => socket.assigns.filter_status,
         "source_type" => socket.assigns.filter_source_type,
         "search" => socket.assigns.search
       }}
    )
  end
end
