defmodule StoryarnWeb.LocalizationLive.Report do
  @moduledoc """
  The localization overview: one card per target language with a segmented
  progress bar whose counts open the workbench filtered, plus the speaker,
  voice-over and content detail of one language. With no target language it
  offers to add the first one in place.
  """

  use StoryarnWeb, :live_view

  alias Storyarn.Localization
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.LanguagePickerOption
  alias StoryarnWeb.Live.Shared.ProjectChromeHelpers

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
      onboarding={@onboarding}
      onboarding_autostart
      sidebar_module={StoryarnWeb.LocalizationSidebarLive}
      sidebar_session={
        %{
          "project_id" => @project.id,
          "workspace_slug" => @workspace.slug,
          "project_slug" => @project.slug,
          "selected_locale" => nil,
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
      <.vue
        v-component="live/localization/report/LocalizationReport"
        v-socket={@socket}
        v-inject="project-layout"
        id="localization-report"
        class="contents"
        project-name={@project.name}
        source-language={serialize_source_language(@source_language)}
        language-progress={serialize_language_progress(assigns)}
        target-languages={serialize_languages(@target_languages)}
        selected-locale={@selected_locale}
        speaker-stats={serialize_speaker_stats(@speaker_stats)}
        vo-progress={@vo_progress}
        type-counts={@type_counts}
        capabilities={%{canEdit: @can_edit, hasProvider: @has_provider}}
        empty-state={
          %{
            addLanguageOptions: @add_language_options,
            runtimeWordCount: @runtime_word_count,
            settingsUrl:
              ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/settings/localization"
          }
        }
      />
    </StoryarnWeb.Components.ProjectLayout.project>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    %{project: project} = socket.assigns
    {:ok, source_language} = Localization.ensure_source_language(project)
    target_languages = Localization.get_target_languages(project.id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(
        Storyarn.PubSub,
        StoryarnWeb.LocalizationSidebarLive.shell_topic(project.id)
      )

      # The overview is the tool's landing page — clear any locale highlight
      # the sticky sidebar may have carried over from a previous workbench
      # visit so the overview link looks active instead.
      Phoenix.PubSub.broadcast(
        Storyarn.PubSub,
        StoryarnWeb.LocalizationSidebarLive.shell_topic(project.id),
        {:active_locale, nil}
      )
    end

    socket =
      socket
      |> assign(:source_language, source_language)
      |> assign(:target_languages, target_languages)
      |> assign(:selected_locale, first_locale(target_languages))
      |> assign(:has_provider, Localization.has_active_provider?(project.id))
      |> assign(:online_users, ProjectChromeHelpers.initial_online_users(project.id))
      |> load_report_data()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("change_locale", %{"locale" => locale}, socket) when is_binary(locale) do
    target_locale? =
      Enum.any?(socket.assigns.target_languages, fn language ->
        language.locale_code == locale
      end)

    socket =
      if target_locale? do
        socket
        |> assign(:selected_locale, locale)
        |> load_report_data()
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("add_target_language", %{"locale_code" => code}, socket) when is_binary(code) and code != "" do
    case Authorize.authorize(socket, :edit_content) do
      :ok -> add_target_language(socket, code)
      {:error, :unauthorized} -> {:reply, %{ok: false, error: "unauthorized"}, socket}
    end
  end

  def handle_event("add_target_language", _params, socket), do: {:reply, %{ok: false, error: "invalid"}, socket}

  # `nil` is broadcast when the overview mounts so the sidebar can clear its
  # target-language highlight. Report data still defaults to the first target
  # language, so ignore that sidebar-only signal here.
  @impl true
  def handle_info({:active_locale, nil}, socket), do: {:noreply, socket}

  def handle_info({:active_locale, locale}, socket) do
    socket =
      socket
      |> assign(:selected_locale, locale)
      |> load_report_data()

    {:noreply, socket}
  end

  def handle_info({:languages_changed, _payload}, socket) do
    {:noreply, reload_languages(socket)}
  end

  def handle_info({:toolbar_event, _name, _params}, socket), do: {:noreply, socket}

  def handle_info({:online_users, users}, socket), do: {:noreply, assign(socket, :online_users, users)}

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ===========================================================================
  # Private: language management
  # ===========================================================================

  defp add_target_language(socket, code) do
    %{current_scope: current_scope, project: project} = socket.assigns
    attrs = %{"locale_code" => code, "name" => Localization.language_name(code), "is_source" => false}

    case Localization.add_language_with_count(current_scope, project, attrs) do
      {:ok, %{language: language, extracted_count: count}} ->
        Phoenix.PubSub.broadcast_from(
          Storyarn.PubSub,
          self(),
          StoryarnWeb.LocalizationSidebarLive.shell_topic(project.id),
          {:languages_changed, nil}
        )

        socket =
          socket
          |> reload_languages()
          |> assign(:selected_locale, language.locale_code)
          |> load_report_data()
          |> put_flash(:info, language_added_message(count))

        {:reply, %{ok: true}, socket}

      {:error, _reason} ->
        {:reply, %{ok: false, error: "add_failed"},
         put_flash(socket, :error, dgettext("localization", "Failed to add language."))}
    end
  end

  defp language_added_message(count) when count > 0 do
    dngettext(
      "localization",
      "Language added. Extracted %{count} text.",
      "Language added. Extracted %{count} texts.",
      count,
      count: count
    )
  end

  defp language_added_message(_count), do: dgettext("localization", "Language added.")

  defp reload_languages(socket) do
    project_id = socket.assigns.project.id
    target_languages = Localization.get_target_languages(project_id)

    socket
    |> assign(:source_language, Localization.get_source_language(project_id))
    |> assign(:target_languages, target_languages)
    |> assign(:selected_locale, normalize_selected_locale(socket.assigns.selected_locale, target_languages))
    |> assign(:has_provider, Localization.has_active_provider?(project_id))
    |> load_report_data()
  end

  defp load_report_data(socket) do
    %{project: project, selected_locale: locale, target_languages: target_languages} = socket.assigns

    {speaker_stats, vo_progress, type_counts} =
      if locale do
        {
          Localization.word_counts_by_speaker(project.id, locale),
          Localization.vo_progress(project.id, locale),
          Localization.counts_by_source_type(project.id, locale)
        }
      else
        {[], %{none: 0, needed: 0, recorded: 0, approved: 0}, %{}}
      end

    socket
    |> assign(:language_progress, Localization.progress_by_language(project.id))
    |> assign(:speaker_stats, speaker_stats)
    |> assign(:vo_progress, vo_progress)
    |> assign(:type_counts, type_counts)
    |> assign(:add_language_options, add_language_options(socket.assigns))
    |> assign(:runtime_word_count, runtime_word_count(project.id, target_languages))
  end

  # Only the empty state needs the inventory size; with target languages the
  # per-language word counts come from the progress report.
  defp runtime_word_count(project_id, []) do
    flow_words = project_id |> Localization.flow_word_counts() |> Map.values() |> Enum.sum()
    sheet_words = project_id |> Localization.sheet_word_counts() |> Map.values() |> Enum.sum()
    flow_words + sheet_words
  end

  defp runtime_word_count(_project_id, _target_languages), do: nil

  defp add_language_options(%{can_edit: false}), do: []

  defp add_language_options(assigns) do
    existing =
      Enum.reject(
        [
          assigns.source_language && assigns.source_language.locale_code
          | Enum.map(assigns.target_languages, & &1.locale_code)
        ],
        &is_nil/1
      )

    [exclude: existing]
    |> Localization.language_options_for_select()
    |> Enum.map(fn {_label, code} -> LanguagePickerOption.from_code(code, label: Localization.language_name(code)) end)
  end

  defp first_locale([first | _]), do: first.locale_code
  defp first_locale([]), do: nil

  defp normalize_selected_locale(selected_locale, target_languages) do
    if Enum.any?(target_languages, &(&1.locale_code == selected_locale)) do
      selected_locale
    else
      first_locale(target_languages)
    end
  end

  # ===========================================================================
  # Private: Serializers (Ecto → Vue props)
  # ===========================================================================

  defp serialize_language_progress(assigns) do
    Enum.map(assigns.language_progress, fn lang ->
      %{
        localeCode: lang.locale_code,
        name: lang.name,
        flagCode: Localization.language_flag_code(lang.locale_code),
        shortLabel: Localization.language_short_label(lang.locale_code),
        total: lang.total,
        pending: lang.pending,
        draft: lang.draft,
        inProgress: lang.in_progress,
        review: lang.review,
        final: lang.final,
        stale: lang.stale,
        wordCount: lang.word_count,
        percentage: lang.percentage,
        workbenchUrl:
          ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/localization/texts/#{lang.locale_code}"
      }
    end)
  end

  defp serialize_languages(languages) do
    Enum.map(languages, fn lang ->
      LanguagePickerOption.from_code(lang.locale_code, label: lang.name)
    end)
  end

  defp serialize_source_language(nil), do: nil

  defp serialize_source_language(language) do
    %{
      localeCode: language.locale_code,
      name: language.name || Localization.language_name(language.locale_code),
      flagCode: Localization.language_flag_code(language.locale_code),
      shortLabel: Localization.language_short_label(language.locale_code)
    }
  end

  defp serialize_speaker_stats(stats) do
    Enum.map(stats, fn stat ->
      %{
        speakerSheetId: stat.speaker_sheet_id,
        speakerName: stat.speaker_name,
        lineCount: stat.line_count,
        wordCount: stat.word_count
      }
    end)
  end
end
