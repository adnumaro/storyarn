defmodule StoryarnWeb.LocalizationLive.Report do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  alias Storyarn.Localization
  alias Storyarn.Localization.Reports
  alias Storyarn.Projects

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.focus
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      active_tool={:localization}
      has_tree={false}
      can_edit={@can_edit}
    >
      <div class="max-w-4xl mx-auto">
        <.header>
          {dgettext("localization", "Localization Report")}
          <:subtitle>
            {dgettext("localization", "Translation progress and statistics")}
          </:subtitle>
          <:actions>
            <.link
              navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/localization"}
              class="btn btn-ghost btn-sm"
            >
              <.icon name="arrow-left" class="size-4 mr-1" />
              {dgettext("localization", "Back to Translations")}
            </.link>
          </:actions>
        </.header>

        <%!-- Progress by Language --%>
        <section class="mt-8">
          <h3 class="text-lg font-semibold mb-4">
            {dgettext("localization", "Progress by Language")}
          </h3>

          <div :if={@language_progress == []} class="text-sm opacity-60">
            {dgettext("localization", "No target languages configured.")}
          </div>

          <div class="space-y-3">
            <div
              :for={lang <- @language_progress}
              class="flex items-center gap-4 bg-base-200 rounded-lg p-3"
            >
              <span class="font-mono text-sm w-12">{lang.locale_code}</span>
              <span class="w-24">{lang.name}</span>
              <progress
                class="progress progress-primary flex-1"
                value={lang.final}
                max={max(lang.total, 1)}
              />
              <span class="text-sm font-medium w-20 text-right">
                {lang.percentage}%
              </span>
              <span class="text-xs opacity-50 w-24 text-right">
                {dgettext("localization", "%{done}/%{total}", done: lang.final, total: lang.total)}
              </span>
            </div>
          </div>
        </section>

        <%!-- Word Counts by Speaker --%>
        <section :if={@selected_locale && @speaker_stats != []} class="mt-8">
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-lg font-semibold">
              {dgettext("localization", "Word Counts by Speaker")}
            </h3>
            <select
              name="locale"
              class="select select-bordered select-sm"
              phx-change="change_locale"
            >
              <option
                :for={lang <- @target_languages}
                value={lang.locale_code}
                selected={lang.locale_code == @selected_locale}
              >
                {lang.name}
              </option>
            </select>
          </div>

          <table class="table table-sm">
            <thead>
              <tr>
                <th>{dgettext("localization", "Speaker")}</th>
                <th class="text-right">{dgettext("localization", "Lines")}</th>
                <th class="text-right">{dgettext("localization", "Words")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={stat <- @speaker_stats}>
                <td>
                  <span :if={stat.speaker_sheet_id}>
                    {dgettext("localization", "Speaker #%{id}", id: stat.speaker_sheet_id)}
                  </span>
                  <span :if={!stat.speaker_sheet_id} class="opacity-50 italic">
                    {dgettext("localization", "No speaker")}
                  </span>
                </td>
                <td class="text-right">{stat.line_count}</td>
                <td class="text-right">{stat.word_count}</td>
              </tr>
            </tbody>
          </table>
        </section>

        <%!-- VO Progress --%>
        <section :if={@selected_locale} class="mt-8">
          <h3 class="text-lg font-semibold mb-4">
            {dgettext("localization", "Voice-Over Progress")}
          </h3>
          <div class="stats shadow">
            <div class="stat">
              <div class="stat-title">{dgettext("localization", "None")}</div>
              <div class="stat-value text-base-content/50">{@vo_progress.none}</div>
            </div>
            <div class="stat">
              <div class="stat-title">{dgettext("localization", "Needed")}</div>
              <div class="stat-value text-warning">{@vo_progress.needed}</div>
            </div>
            <div class="stat">
              <div class="stat-title">{dgettext("localization", "Recorded")}</div>
              <div class="stat-value text-info">{@vo_progress.recorded}</div>
            </div>
            <div class="stat">
              <div class="stat-title">{dgettext("localization", "Approved")}</div>
              <div class="stat-value text-success">{@vo_progress.approved}</div>
            </div>
          </div>
        </section>

        <%!-- Content Type Breakdown --%>
        <section :if={@selected_locale && @type_counts != %{}} class="mt-8">
          <h3 class="text-lg font-semibold mb-4">{dgettext("localization", "Content Breakdown")}</h3>
          <div class="flex gap-3 flex-wrap">
            <div
              :for={{type, count} <- @type_counts}
              class="badge badge-lg badge-outline gap-1"
            >
              <.icon name={type_icon(type)} class="size-3.5" />
              {type_label(type)}: {count}
            </div>
          </div>
        </section>
      </div>
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
        can_edit = Projects.ProjectMembership.can?(membership.role, :edit_content)
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

    language_progress = Reports.progress_by_language(project_id)

    {speaker_stats, vo_progress, type_counts} =
      if locale do
        {
          Reports.word_counts_by_speaker(project_id, locale),
          Reports.vo_progress(project_id, locale),
          Reports.counts_by_source_type(project_id, locale)
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

  defp type_icon("flow_node"), do: "message-square"
  defp type_icon("block"), do: "square"
  defp type_icon("sheet"), do: "file-text"
  defp type_icon("flow"), do: "git-branch"
  defp type_icon("screenplay"), do: "clapperboard"
  defp type_icon(_), do: "box"

  defp type_label("flow_node"), do: dgettext("localization", "Nodes")
  defp type_label("block"), do: dgettext("localization", "Blocks")
  defp type_label("sheet"), do: dgettext("localization", "Sheets")
  defp type_label("flow"), do: dgettext("localization", "Flows")
  defp type_label("screenplay"), do: dgettext("localization", "Screenplays")
  defp type_label(other), do: other
end
