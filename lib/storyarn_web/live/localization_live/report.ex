defmodule StoryarnWeb.LocalizationLive.Report do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Localization
  alias StoryarnWeb.Live.Shared.ProjectChromeHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.ProjectShell.project_shell
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
          "selected_locale" => nil,
          "can_edit" => @can_edit,
          "active_tool" => "localization",
          "dashboard_url" =>
            ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/localization",
          "current_scope" => @current_scope
        }
      }
    >
      <.vue
        v-component="modules/localization/components/LocalizationReport"
        v-socket={@socket}
        id="localization-report"
        language-progress={serialize_language_progress(@language_progress)}
        target-languages={serialize_languages(@target_languages)}
        selected-locale={@selected_locale}
        speaker-stats={serialize_speaker_stats(@speaker_stats)}
        vo-progress={@vo_progress}
        type-counts={@type_counts}
      />
    </StoryarnWeb.Components.ProjectShell.project_shell>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    %{project: project} = socket.assigns
    target_languages = Localization.get_target_languages(project.id)

    selected_locale =
      case target_languages do
        [first | _] -> first.locale_code
        [] -> nil
      end

    if connected?(socket) do
      Phoenix.PubSub.subscribe(
        Storyarn.PubSub,
        StoryarnWeb.LocalizationSidebarLive.shell_topic(project.id)
      )

      # Report is the tool "dashboard" — clear any locale highlight the
      # sticky sidebar may have carried over from a previous Index/Edit
      # visit so the dashboard link looks active instead.
      Phoenix.PubSub.broadcast(
        Storyarn.PubSub,
        StoryarnWeb.LocalizationSidebarLive.shell_topic(project.id),
        {:active_locale, nil}
      )
    end

    socket =
      socket
      |> assign(:target_languages, target_languages)
      |> assign(:selected_locale, selected_locale)
      |> assign(:online_users, ProjectChromeHelpers.initial_online_users(project.id))
      |> load_report_data()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("tree_panel_" <> _ = event, params, socket),
    do: ProjectChromeHelpers.forward_tree_panel(socket, event, params)

  # change_locale is emitted by LocalizationSidebar.vue which now lives inside
  # LocalizationSidebarLive; the sidebar broadcasts `{:active_locale, locale}`
  # on the shell topic, which we pick up below.
  @impl true
  def handle_info({:active_locale, locale}, socket) do
    socket =
      socket
      |> assign(:selected_locale, locale)
      |> load_report_data()

    {:noreply, socket}
  end

  def handle_info({:languages_changed, _payload}, socket) do
    project_id = socket.assigns.project.id

    {:noreply,
     socket
     |> assign(:target_languages, Localization.get_target_languages(project_id))
     |> load_report_data()}
  end

  def handle_info({:toolbar_event, _name, _params}, socket), do: {:noreply, socket}

  def handle_info({:online_users, users}, socket), do: {:noreply, assign(socket, :online_users, users)}

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp load_report_data(socket) do
    project_id = socket.assigns.project.id
    locale = socket.assigns.selected_locale

    language_progress = Localization.progress_by_language(project_id)

    {speaker_stats, vo_progress, type_counts} =
      if locale do
        {
          Localization.word_counts_by_speaker(project_id, locale),
          Localization.vo_progress(project_id, locale),
          Localization.counts_by_source_type(project_id, locale)
        }
      else
        {[], %{none: 0, needed: 0, recorded: 0, approved: 0}, %{}}
      end

    socket
    |> assign(:language_progress, language_progress)
    |> assign(:speaker_stats, speaker_stats)
    |> assign(:vo_progress, vo_progress)
    |> assign(:type_counts, type_counts)
  end

  # ===========================================================================
  # Private: Serializers (Ecto → Vue props)
  # ===========================================================================

  defp serialize_language_progress(progress) do
    Enum.map(progress, fn lang ->
      %{
        localeCode: lang.locale_code,
        name: lang.name,
        final: lang.final,
        total: lang.total,
        percentage: lang.percentage
      }
    end)
  end

  defp serialize_languages(languages) do
    Enum.map(languages, fn lang ->
      %{localeCode: lang.locale_code, name: lang.name}
    end)
  end

  defp serialize_speaker_stats(stats) do
    Enum.map(stats, fn stat ->
      %{
        speakerSheetId: stat.speaker_sheet_id,
        lineCount: stat.line_count,
        wordCount: stat.word_count
      }
    end)
  end
end
