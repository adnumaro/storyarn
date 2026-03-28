defmodule StoryarnWeb.LocalizationLive.Report do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Localization
  alias Storyarn.Projects

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.focus
      socket={@socket}
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      active_tool={:localization}
      has_tree={false}
      can_edit={@can_edit}
    >
      <.vue
        v-component="localization/LocalizationReport"
        v-socket={@socket}
        id="localization-report"
        language-progress={serialize_language_progress(@language_progress)}
        target-languages={serialize_languages(@target_languages)}
        selected-locale={@selected_locale}
        speaker-stats={serialize_speaker_stats(@speaker_stats)}
        vo-progress={@vo_progress}
        type-counts={@type_counts}
        back-url={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/localization"}
      />
    </Layouts.focus>
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
        target_languages = Localization.get_target_languages(project.id)

        selected_locale =
          case target_languages do
            [first | _] -> first.locale_code
            [] -> nil
          end

        socket =
          socket
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_edit, can_edit)
          |> assign(:target_languages, target_languages)
          |> assign(:selected_locale, selected_locale)
          |> load_report_data()

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
    socket =
      socket
      |> assign(:selected_locale, locale)
      |> load_report_data()

    {:noreply, socket}
  end

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
