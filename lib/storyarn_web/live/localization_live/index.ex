defmodule StoryarnWeb.LocalizationLive.Index do
  @moduledoc """
  The translation workbench of one target language.

  The URL is the state: `/localization/texts/:locale[/:id]?status=…&source_type=…&
  vo_status=…&speaker=…&stale=1&search=…`. Filter changes patch the URL so the
  overview can deep-link into a filtered list and a translator can share one.
  """

  use StoryarnWeb, :live_view

  import StoryarnWeb.LocalizationLive.Helpers.LocalizationHelpers

  alias Storyarn.Localization
  alias Storyarn.Platform.Shared.HtmlSanitizer
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.LanguagePickerOption
  alias StoryarnWeb.Live.Shared.ProjectChromeHelpers

  @page_size 50
  @empty_filters %{status: nil, source_type: nil, vo_status: nil, speaker: nil, stale: false, search: ""}
  @text_preloads [:speaker_sheet, :translated_by]

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
      membership={@membership}
      urls={@urls}
      active_tool={:localization}
      online_users={@online_users}
      sidebar_module={StoryarnWeb.LocalizationSidebarLive}
      sidebar_session={
        %{
          "project_id" => @project.id,
          "workspace_slug" => @workspace.slug,
          "project_slug" => @project.slug,
          "selected_locale" => @selected_locale,
          "can_edit" => @can_edit,
          "membership" => @membership,
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
            "membership" => @membership,
            "filters" => toolbar_filters(assigns),
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
        pagination={%{page: @page, pageSize: @page_size, hasMore: length(@texts) < @total_count}}
        filters={serialize_filters(assigns)}
        capabilities={
          %{
            canEdit: @can_edit,
            hasProvider: @has_provider,
            hasTargetLanguages: @target_languages != []
          }
        }
        selected-text={serialize_selected_text(assigns)}
        languages={
          %{current: serialize_language(assigns), targets: serialize_target_languages(assigns)}
        }
        speakers={serialize_speakers(@speakers)}
        overview-url={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/localization"}
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
      # selected_locale and the filters are driven by the URL — see handle_params
      |> assign(:selected_locale, nil)
      |> assign(:has_provider, has_active_provider?(project.id))
      |> assign_filters(@empty_filters)
      |> assign(:page, 1)
      |> assign(:page_size, @page_size)
      |> assign(:texts, [])
      |> assign(:total_count, 0)
      |> assign(:progress, nil)
      |> assign(:selected_text, nil)
      |> assign(:source_context, nil)
      |> assign(:glossary_hits, [])
      |> assign(:speakers, [])
      |> assign(:glossary_pairs, [])
      |> assign(:language_word_count, 0)
      |> assign(:online_users, ProjectChromeHelpers.initial_online_users(project.id))

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"locale" => locale} = params, _url, socket) do
    filters = parse_filters(params)

    socket =
      cond do
        locale != socket.assigns.selected_locale ->
          # Broadcast so LocalizationSidebarLive updates the highlighted target.
          Phoenix.PubSub.broadcast(
            Storyarn.PubSub,
            StoryarnWeb.LocalizationSidebarLive.shell_topic(socket.assigns.project.id),
            {:active_locale, locale}
          )

          socket
          |> assign(:selected_locale, locale)
          |> assign_filters(filters)
          |> assign(:page, 1)
          |> load_locale_context()
          |> load_texts()
          |> tap(&broadcast_filters/1)

        filters != current_filters(socket) ->
          socket
          |> assign_filters(filters)
          |> assign(:page, 1)
          |> load_texts()
          |> tap(&broadcast_filters/1)

        true ->
          socket
      end

    {:noreply, assign_selected_text(socket, params["id"])}
  end

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  # ============================================================================
  # Filters and navigation (the URL is the state)
  # ============================================================================

  @impl true
  def handle_event("change_filter", params, socket) do
    filters =
      socket
      |> current_filters()
      |> merge_filter_param(params, "status", :status, statuses())
      |> merge_filter_param(params, "source_type", :source_type, source_types())
      |> merge_filter_param(params, "vo_status", :vo_status, vo_statuses())
      |> merge_speaker_param(params)
      |> merge_stale_param(params)

    {:noreply, patch_workbench(socket, filters, selected_id(socket), replace: true)}
  end

  def handle_event("search", %{"search" => search}, socket) when is_binary(search) do
    filters = %{current_filters(socket) | search: search}
    {:noreply, patch_workbench(socket, filters, selected_id(socket), replace: true)}
  end

  def handle_event("load_more", _params, socket) do
    if length(socket.assigns.texts) < socket.assigns.total_count do
      socket =
        socket
        |> assign(:page, socket.assigns.page + 1)
        |> load_texts(:append)

      {:reply, %{ok: true}, socket}
    else
      {:reply, %{ok: true}, socket}
    end
  end

  def handle_event("select_text", %{"id" => id}, socket) do
    case parse_id(id) do
      {:ok, text_id} -> {:noreply, patch_workbench(socket, current_filters(socket), text_id)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("close_editor", _params, socket) do
    {:noreply, patch_workbench(socket, current_filters(socket), nil)}
  end

  # The empty editor pane offers the next piece of work: narrow the list to
  # that set and open its first string.
  def handle_event("select_next", %{"kind" => kind}, socket) when kind in ~w(pending review stale) do
    filters =
      case kind do
        "pending" -> %{current_filters(socket) | status: "pending", stale: false}
        "review" -> %{current_filters(socket) | status: "review", stale: false}
        "stale" -> %{current_filters(socket) | status: nil, stale: true}
      end

    opts = socket.assigns |> Map.merge(filter_assigns(filters)) |> text_filter_opts()

    case Localization.list_texts(socket.assigns.project.id, opts ++ [limit: 1]) do
      [text | _] -> {:noreply, patch_workbench(socket, filters, text.id)}
      [] -> {:noreply, socket}
    end
  end

  # ============================================================================
  # Translation
  # ============================================================================

  def handle_event("translate_single", params, socket) do
    with_auth(:edit_content, socket, fn ->
      translate_single(params, socket)
    end)
  end

  def handle_event("save_translation", %{"id" => id, "lock_version" => lock_version, "localized_text" => params}, socket) do
    with_auth(:edit_content, socket, fn ->
      save_translation(socket, id, lock_version, params)
    end)
  end

  # ============================================================================
  # Shell fan-in
  # ============================================================================

  @impl true
  def handle_info({:active_locale, locale}, %{assigns: %{selected_locale: locale}} = socket) do
    {:noreply, socket}
  end

  def handle_info({:active_locale, locale}, socket) do
    socket =
      socket
      |> assign(:selected_locale, locale)
      |> assign(:page, 1)
      |> clear_selected_text()
      |> load_locale_context()
      |> load_texts()

    {:noreply, socket}
  end

  # Sidebar broadcast after a language mutation (add/remove/sync/source change)
  # or a completed import or batch run.
  def handle_info({:languages_changed, _payload}, socket) do
    project_id = socket.assigns.project.id

    {:noreply,
     socket
     |> assign(:source_language, Localization.get_source_language(project_id))
     |> assign(:target_languages, Localization.get_target_languages(project_id))
     |> assign(:has_provider, has_active_provider?(project_id))
     |> load_locale_context()
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
        contentRole: text.content_role,
        contentRoleLabel: content_role_label(text.content_role),
        speakerName: speaker_name(text),
        voEligible: text.vo_eligible,
        voStatus: text.vo_status || "none",
        wordCount: text.word_count || 0,
        machineTranslated: text.machine_translated || false,
        stale: Localization.text_stale?(text),
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
      contentRole: text.content_role,
      contentRoleLabel: content_role_label(text.content_role),
      speakerName: speaker_name(text),
      sourceRef: source_reference(assigns.source_context, text, assigns),
      sourceHtml: HtmlSanitizer.sanitize_html(text.source_text || ""),
      sourceText: strip_html(text.source_text),
      wordCount: text.word_count || 0,
      localeCode: text.locale_code,
      localeName: selected_locale_name(assigns),
      translatedText: text.translated_text || "",
      status: text.status,
      translatorNotes: text.translator_notes || "",
      voStatus: text.vo_status || "none",
      voEligible: text.vo_eligible,
      machineTranslated: text.machine_translated || false,
      lastTranslatedAt: text.last_translated_at && DateTime.to_iso8601(text.last_translated_at),
      translatedBy: translator_name(text),
      stale: Localization.text_stale?(text),
      placeholders: Localization.text_placeholders(text.source_text),
      glossaryHits: Enum.map(assigns.glossary_hits, fn {source, target} -> %{source: source, target: target} end),
      lockVersion: text.lock_version
    }
  end

  defp serialize_filters(assigns) do
    %{
      status: assigns.filter_status || "",
      sourceType: assigns.filter_source_type || "",
      voStatus: assigns.filter_vo_status || "",
      speaker: assigns.filter_speaker,
      stale: assigns.filter_stale,
      search: assigns.search
    }
  end

  defp serialize_language(%{selected_locale: nil}), do: nil

  defp serialize_language(assigns) do
    code = assigns.selected_locale

    %{
      code: code,
      name: selected_locale_name(assigns),
      flagCode: Localization.language_flag_code(code),
      shortLabel: Localization.language_short_label(code),
      wordCount: assigns.language_word_count,
      sourceName: source_language_name(assigns.source_language)
    }
  end

  defp serialize_target_languages(assigns) do
    Enum.map(assigns.target_languages, fn language ->
      language.locale_code
      |> LanguagePickerOption.from_code(label: language.name)
      |> Map.put(
        :href,
        ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/localization/texts/#{language.locale_code}"
      )
    end)
  end

  defp serialize_speakers(speakers) do
    speakers
    |> Enum.reject(&is_nil(&1.speaker_sheet_id))
    |> Enum.map(fn speaker ->
      %{
        id: speaker.speaker_sheet_id,
        name: speaker.speaker_name,
        lineCount: speaker.line_count,
        wordCount: speaker.word_count
      }
    end)
  end

  defp source_reference(nil, text, _assigns) do
    %{parent: nil, label: content_role_label(text.content_role), url: nil}
  end

  defp source_reference(%{kind: :flow_node} = context, text, assigns) do
    %{
      parent: context.parent_name,
      label: context.label || content_role_label(text.content_role),
      url:
        ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/flows/#{context.flow_id}?node=#{context.node_id}"
    }
  end

  defp source_reference(context, text, assigns) do
    %{
      parent: context.parent_name,
      label: context.label || content_role_label(text.content_role),
      url: ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/sheets/#{context.sheet_id}"
    }
  end

  defp speaker_name(%{speaker_sheet: %{name: name}}) when is_binary(name), do: name
  defp speaker_name(_text), do: nil

  defp translator_name(%{translated_by: %{display_name: name}}) when is_binary(name) and name != "", do: name
  defp translator_name(%{translated_by: %{email: email}}) when is_binary(email), do: email
  defp translator_name(_text), do: nil

  defp toolbar_filters(assigns) do
    %{
      "status" => assigns.filter_status,
      "source_type" => assigns.filter_source_type,
      "search" => assigns.search
    }
  end

  # ============================================================================
  # Filters
  # ============================================================================

  defp parse_filters(params) do
    %{
      status: pick(params["status"], statuses()),
      source_type: pick(params["source_type"], source_types()),
      vo_status: pick(params["vo_status"], vo_statuses()),
      speaker: parse_speaker(params["speaker"]),
      stale: params["stale"] in ["1", "true"],
      search: if(is_binary(params["search"]), do: params["search"], else: "")
    }
  end

  defp pick(value, allowed) when is_binary(value) and value != "" do
    if value in allowed, do: value
  end

  defp pick(_value, _allowed), do: nil

  defp parse_speaker(value) do
    case parse_id(value) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  defp merge_filter_param(filters, params, param_key, filter_key, allowed) do
    if Map.has_key?(params, param_key) do
      Map.put(filters, filter_key, pick(params[param_key], allowed))
    else
      filters
    end
  end

  defp merge_speaker_param(filters, %{"speaker" => value}), do: Map.put(filters, :speaker, parse_speaker(value))
  defp merge_speaker_param(filters, _params), do: filters

  defp merge_stale_param(filters, %{"stale" => value}), do: Map.put(filters, :stale, value in [true, "1", "true"])
  defp merge_stale_param(filters, _params), do: filters

  defp current_filters(socket) do
    %{
      status: socket.assigns.filter_status,
      source_type: socket.assigns.filter_source_type,
      vo_status: socket.assigns.filter_vo_status,
      speaker: socket.assigns.filter_speaker,
      stale: socket.assigns.filter_stale,
      search: socket.assigns.search
    }
  end

  defp filter_assigns(filters) do
    %{
      filter_status: filters.status,
      filter_source_type: filters.source_type,
      filter_vo_status: filters.vo_status,
      filter_speaker: filters.speaker,
      filter_stale: filters.stale,
      search: filters.search
    }
  end

  defp assign_filters(socket, filters), do: assign(socket, filter_assigns(filters))

  defp filter_query(filters) do
    []
    |> maybe_add(:status, filters.status)
    |> maybe_add(:source_type, filters.source_type)
    |> maybe_add(:vo_status, filters.vo_status)
    |> maybe_add(:speaker, filters.speaker)
    |> maybe_add(:stale, if(filters.stale, do: "1"))
    |> maybe_add(:search, non_blank(filters.search))
    |> Enum.reverse()
  end

  defp workbench_path(socket, filters, text_id) do
    %{workspace: workspace, project: project, selected_locale: locale} = socket.assigns

    base =
      if text_id do
        ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/localization/texts/#{locale}/#{text_id}"
      else
        ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/localization/texts/#{locale}"
      end

    case filter_query(filters) do
      [] -> base
      query -> base <> "?" <> URI.encode_query(query)
    end
  end

  defp patch_workbench(socket, filters, text_id, opts \\ []) do
    push_patch(socket, to: workbench_path(socket, filters, text_id), replace: Keyword.get(opts, :replace, false))
  end

  defp selected_id(%{assigns: %{selected_text: %{id: id}}}), do: id
  defp selected_id(_socket), do: nil

  defp broadcast_filters(socket) do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      StoryarnWeb.LocalizationSidebarLive.shell_topic(socket.assigns.project.id),
      {:localization_filters, toolbar_filters(socket.assigns)}
    )
  end

  # ============================================================================
  # Locale context: speakers, glossary pair and word count
  # ============================================================================

  defp load_locale_context(%{assigns: %{selected_locale: nil}} = socket) do
    socket
    |> assign(:speakers, [])
    |> assign(:glossary_pairs, [])
    |> assign(:language_word_count, 0)
  end

  defp load_locale_context(socket) do
    %{project: project, selected_locale: locale, source_language: source_language} = socket.assigns

    word_count =
      project.id
      |> Localization.progress_by_language()
      |> Enum.find_value(0, fn entry -> if entry.locale_code == locale, do: entry.word_count end)

    glossary_pairs =
      if source_language do
        Localization.get_glossary_entries_for_pair(project.id, source_language.locale_code, locale)
      else
        []
      end

    socket
    |> assign(:speakers, Localization.word_counts_by_speaker(project.id, locale))
    |> assign(:glossary_pairs, glossary_pairs)
    |> assign(:language_word_count, word_count)
  end

  defp glossary_hits(pairs, source_text) do
    haystack = source_text |> strip_html() |> String.downcase()

    Enum.filter(pairs, fn {source_term, _target_term} ->
      is_binary(source_term) and source_term != "" and String.contains?(haystack, String.downcase(source_term))
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

  defp selected_locale_name(%{selected_locale: nil}), do: ""

  defp selected_locale_name(assigns) do
    case Enum.find(assigns.target_languages, &(&1.locale_code == assigns.selected_locale)) do
      nil -> Localization.language_name(assigns.selected_locale)
      language -> language.name
    end
  end

  defp source_language_name(nil), do: ""
  defp source_language_name(%{name: name, locale_code: code}), do: name || Localization.language_name(code)

  defp assign_selected_text(socket, nil), do: clear_selected_text(socket)

  defp assign_selected_text(socket, id) do
    with {:ok, text_id} <- parse_id(id),
         text when not is_nil(text) <-
           Localization.get_text(socket.assigns.project.id, text_id, preload: @text_preloads),
         true <- text.locale_code == socket.assigns.selected_locale do
      socket
      |> assign(:selected_text, text)
      |> assign(:source_context, Localization.text_source_context(text))
      |> assign(:glossary_hits, glossary_hits(socket.assigns.glossary_pairs, text.source_text || ""))
    else
      _reason -> clear_selected_text(socket)
    end
  end

  defp clear_selected_text(socket) do
    socket
    |> assign(:selected_text, nil)
    |> assign(:source_context, nil)
    |> assign(:glossary_hits, [])
  end

  defp reload_selected_text(%{assigns: %{selected_text: nil}} = socket), do: socket

  defp reload_selected_text(socket) do
    assign_selected_text(socket, socket.assigns.selected_text.id)
  end

  defp translate_single(%{"id" => id}, socket) do
    with {:ok, text_id} <- parse_id(id),
         {:ok, updated} <- Localization.translate_single(socket.assigns.project.id, text_id),
         translated when not is_nil(translated) <-
           Localization.get_text(socket.assigns.project.id, updated.id, preload: @text_preloads) do
      socket =
        socket
        |> load_texts()
        |> reload_translated_selection(translated.id)

      {:reply, %{ok: true, text: serialize_translation_reply(socket.assigns, translated)}, socket}
    else
      {:error, reason} -> {:reply, %{ok: false, error: inspect(reason)}, socket}
      nil -> {:reply, %{ok: false, error: "text_not_found"}, socket}
      :error -> {:reply, %{ok: false, error: "invalid_id"}, socket}
    end
  end

  defp reload_translated_selection(%{assigns: %{selected_text: %{id: selected_id}}} = socket, id)
       when selected_id == id do
    assign_selected_text(socket, id)
  end

  defp reload_translated_selection(socket, _id), do: socket

  defp serialize_translation_reply(assigns, text) do
    reply_assigns =
      assigns
      |> Map.put(:selected_text, text)
      |> Map.put(:source_context, Localization.text_source_context(text))
      |> Map.put(:glossary_hits, glossary_hits(assigns.glossary_pairs, text.source_text || ""))

    serialize_selected_text(reply_assigns)
  end

  defp save_translation(socket, id, lock_version, params) do
    with {:ok, text_id} <- parse_id(id),
         {:ok, expected_lock} <- parse_id(lock_version),
         text when not is_nil(text) <-
           Localization.get_text(socket.assigns.project.id, text_id, preload: @text_preloads),
         true <- text.locale_code == socket.assigns.selected_locale do
      save_with_lock(socket, text_id, text, expected_lock, params)
    else
      _reason -> {:reply, %{ok: false, error: "text_not_found"}, socket}
    end
  end

  defp save_with_lock(socket, text_id, %{lock_version: expected_lock} = text, expected_lock, params) do
    params = Map.put(params, "translated_by_id", socket.assigns.current_scope.user.id)

    case Localization.update_text(text, params) do
      {:ok, updated} -> successful_save_reply(socket, updated)
      {:error, changeset} -> failed_save_reply(socket, text_id, changeset)
    end
  end

  defp save_with_lock(socket, _text_id, text, _expected_lock, _params), do: conflict_reply(socket, text)

  defp successful_save_reply(socket, updated) do
    socket = socket |> load_texts() |> assign_selected_text(updated.id)
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
    case Localization.get_text(socket.assigns.project.id, text_id, preload: @text_preloads) do
      nil -> {:reply, %{ok: false, error: "text_not_found"}, socket}
      current -> conflict_reply(socket, current)
    end
  end

  defp conflict_reply(socket, current) do
    assigns =
      socket.assigns
      |> Map.put(:selected_text, current)
      |> Map.put(:source_context, Localization.text_source_context(current))

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
end
