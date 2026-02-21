defmodule StoryarnWeb.LocalizationLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  alias Storyarn.Localization
  alias Storyarn.Localization.Languages
  alias Storyarn.Projects
  alias Storyarn.Repo

  import StoryarnWeb.LocalizationLive.Helpers.LocalizationHelpers
  alias StoryarnWeb.LocalizationLive.Handlers.LocalizationHandlers

  @page_size 50

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.project
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      current_path={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/localization"}
      can_edit={@can_edit}
    >
      <div class="max-w-6xl mx-auto">
        <.header>
          {dgettext("localization", "Localization")}
          <:subtitle>
            {dgettext("localization", "Manage translations for your project content")}
          </:subtitle>
          <:actions :if={@can_edit && @target_languages != []}>
            <div class="flex items-center gap-2">
              <.link
                navigate={
                  ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/localization/report"
                }
                class="btn btn-sm btn-ghost"
              >
                <.icon name="bar-chart-3" class="size-4 mr-1" />
                {dgettext("localization", "Report")}
              </.link>
              <div :if={@selected_locale} class="dropdown dropdown-end">
                <div tabindex="0" role="button" class="btn btn-sm btn-ghost">
                  <.icon name="download" class="size-4 mr-1" />
                  {dgettext("localization", "Export")}
                </div>
                <ul
                  tabindex="0"
                  class="dropdown-content menu bg-base-200 rounded-box z-10 w-40 p-2 shadow-sm"
                >
                  <li>
                    <a href={
                      ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/localization/export/xlsx/#{@selected_locale}"
                    }>
                      {dgettext("localization", "Excel (.xlsx)")}
                    </a>
                  </li>
                  <li>
                    <a href={
                      ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/localization/export/csv/#{@selected_locale}"
                    }>
                      {dgettext("localization", "CSV (.csv)")}
                    </a>
                  </li>
                </ul>
              </div>
              <.button
                :if={@has_provider}
                phx-click="translate_batch"
                phx-disable-with={dgettext("localization", "Translating...")}
                variant="primary"
              >
                <.icon name="languages" class="size-4 mr-1" />
                {dgettext("localization", "Translate All Pending")}
              </.button>
            </div>
          </:actions>
        </.header>

        <%!-- Language management bar --%>
        <div class="mt-6">
          <div class="flex flex-wrap items-center gap-2 mb-4">
            <%!-- Source language badge --%>
            <div :if={@source_language} class="badge badge-primary gap-1.5 py-3">
              <.icon name="flag" class="size-3" />
              {Languages.name(@source_language.locale_code)}
              <span class="opacity-60">({@source_language.locale_code})</span>
            </div>

            <%!-- Target language chips --%>
            <div
              :for={lang <- @target_languages}
              class="badge badge-outline gap-1 py-3"
            >
              {lang.name}
              <span class="opacity-60">({lang.locale_code})</span>
              <button
                :if={@can_edit}
                phx-click={show_modal("remove-language-#{lang.id}")}
                class="ml-0.5 hover:text-error cursor-pointer"
                title={dgettext("localization", "Remove language")}
              >
                <.icon name="x" class="size-3" />
              </button>
            </div>

            <%!-- Add Language dropdown --%>
            <div :if={@can_edit} class="dropdown">
              <div tabindex="0" role="button" class="btn btn-ghost btn-xs gap-1">
                <.icon name="plus" class="size-3.5" />
                {dgettext("localization", "Add Language")}
              </div>
              <div
                tabindex="0"
                class="dropdown-content bg-base-200 rounded-box z-10 w-64 p-3 shadow-sm"
              >
                <form phx-change="add_target_language">
                  <select name="locale_code" class="select select-bordered select-sm w-full">
                    <option value="">{dgettext("localization", "Select language...")}</option>
                    <option
                      :for={{label, code} <- language_picker_options(assigns)}
                      value={code}
                    >
                      {label}
                    </option>
                  </select>
                </form>
              </div>
            </div>

            <%!-- Sync button --%>
            <button
              :if={@can_edit && @target_languages != []}
              phx-click="sync_texts"
              phx-disable-with={dgettext("localization", "Syncing...")}
              class="btn btn-ghost btn-xs gap-1"
              title={
                dgettext(
                  "localization",
                  "Re-extract all translatable content from flows, sheets, and blocks"
                )
              }
            >
              <.icon name="refresh-cw" class="size-3.5" />
              {dgettext("localization", "Sync")}
            </button>
          </div>

          <%!-- Remove language confirmation modals --%>
          <.confirm_modal
            :for={lang <- @target_languages}
            id={"remove-language-#{lang.id}"}
            title={dgettext("localization", "Remove language?")}
            message={
              dgettext(
                "localization",
                "This will remove %{name} (%{code}) and all its translations from this project.",
                name: lang.name,
                code: lang.locale_code
              )
            }
            confirm_text={dgettext("localization", "Remove")}
            confirm_variant="error"
            icon="trash-2"
            on_confirm={JS.push("remove_language", value: %{id: lang.id})}
          />
        </div>

        <%!-- No target languages yet --%>
        <div :if={@target_languages == []} class="mt-4">
          <.empty_state icon="globe">
            {dgettext("localization", "Add a target language above to start translating.")}
          </.empty_state>
        </div>

        <%!-- Filters + Progress (only when target languages exist) --%>
        <div :if={@target_languages != []} class="mt-2">
          <%!-- Language selector + Progress bar --%>
          <div class="flex items-center justify-between mb-4">
            <div class="flex items-center gap-3">
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
                  {lang.name} ({lang.locale_code})
                </option>
              </select>
            </div>

            <div :if={@progress} class="flex items-center gap-3">
              <progress
                class="progress progress-primary w-40"
                value={@progress.final}
                max={max(@progress.total, 1)}
              />
              <span class="text-sm opacity-70">
                {dgettext("localization", "%{done} / %{total} final",
                  done: @progress.final,
                  total: @progress.total
                )}
              </span>
            </div>
          </div>

          <%!-- Filters row --%>
          <div class="flex items-center gap-3 mb-4">
            <%!-- Status filter --%>
            <select
              name="status"
              class="select select-bordered select-sm"
              phx-change="change_filter"
            >
              <option value="" selected={@filter_status == nil}>
                {dgettext("localization", "All statuses")}
              </option>
              <option
                :for={s <- ~w(pending draft in_progress review final)}
                value={s}
                selected={@filter_status == s}
              >
                {status_label(s)}
              </option>
            </select>

            <%!-- Source type filter --%>
            <select
              name="source_type"
              class="select select-bordered select-sm"
              phx-change="change_filter"
            >
              <option value="" selected={@filter_source_type == nil}>
                {dgettext("localization", "All types")}
              </option>
              <option
                :for={t <- ~w(flow_node block sheet flow)}
                value={t}
                selected={@filter_source_type == t}
              >
                {source_type_label(t)}
              </option>
            </select>

            <%!-- Search --%>
            <form phx-change="search" class="flex-1">
              <label class="input input-sm input-bordered flex items-center gap-2">
                <.icon name="search" class="size-4 opacity-50" />
                <input
                  type="text"
                  name="search"
                  value={@search}
                  placeholder={dgettext("localization", "Search in source or translation...")}
                  phx-debounce="300"
                  class="grow"
                />
              </label>
            </form>
          </div>

          <%!-- Empty state --%>
          <.empty_state :if={@texts == []} icon="file-text">
            {dgettext("localization", "No translations found matching your filters.")}
          </.empty_state>

          <%!-- Translation table --%>
          <div :if={@texts != []} class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th class="w-12">{dgettext("localization", "Type")}</th>
                  <th>{dgettext("localization", "Source Text")}</th>
                  <th>{dgettext("localization", "Translation")}</th>
                  <th class="w-28">{dgettext("localization", "Status")}</th>
                  <th class="w-16">{dgettext("localization", "Words")}</th>
                  <th :if={@can_edit} class="w-20"></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={text <- @texts} class="hover">
                  <td>
                    <span
                      class="badge badge-ghost badge-sm"
                      title={source_type_label(text.source_type)}
                    >
                      <.icon name={source_type_icon(text.source_type)} class="size-3" />
                    </span>
                  </td>
                  <td class="max-w-xs">
                    <div class="truncate text-sm" title={strip_html(text.source_text)}>
                      {strip_html(text.source_text)}
                    </div>
                    <div class="text-xs opacity-50">{text.source_field}</div>
                  </td>
                  <td class="max-w-xs">
                    <div :if={text.translated_text} class="truncate text-sm">
                      {strip_html(text.translated_text)}
                    </div>
                    <div :if={!text.translated_text} class="text-sm opacity-30 italic">
                      {dgettext("localization", "Not translated")}
                    </div>
                    <span
                      :if={text.machine_translated}
                      class="badge badge-xs badge-outline opacity-60"
                    >
                      {dgettext("localization", "MT")}
                    </span>
                  </td>
                  <td>
                    <.status_badge status={text.status} />
                  </td>
                  <td class="text-sm opacity-60">{text.word_count || 0}</td>
                  <td :if={@can_edit}>
                    <.link
                      navigate={
                        ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/localization/#{text.id}"
                      }
                      class="btn btn-ghost btn-xs"
                    >
                      <.icon name="pencil" class="size-3.5" />
                    </.link>
                    <button
                      :if={@has_provider && !text.translated_text}
                      phx-click="translate_single"
                      phx-value-id={text.id}
                      class="btn btn-ghost btn-xs"
                      title={dgettext("localization", "Translate with DeepL")}
                    >
                      <.icon name="sparkles" class="size-3.5" />
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <%!-- Pagination --%>
          <div :if={@total_count > @page_size} class="flex justify-center mt-4">
            <div class="join">
              <button
                class="join-item btn btn-sm"
                disabled={@page == 1}
                phx-click="change_page"
                phx-value-page={@page - 1}
              >
                «
              </button>
              <button class="join-item btn btn-sm btn-disabled">
                {dgettext("localization", "Page %{page} of %{total}",
                  page: @page,
                  total: ceil(@total_count / @page_size)
                )}
              </button>
              <button
                class="join-item btn btn-sm"
                disabled={@page * @page_size >= @total_count}
                phx-click="change_page"
                phx-value-page={@page + 1}
              >
                »
              </button>
            </div>
          </div>
        </div>
      </div>
    </Layouts.project>
    """
  end

  attr :status, :string, required: true

  defp status_badge(assigns) do
    ~H"""
    <span class={["badge badge-sm", status_class(@status)]}>
      {status_label(@status)}
    </span>
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
        project = Repo.preload(project, :workspace)
        can_edit = Projects.ProjectMembership.can?(membership.role, :edit_content)

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
    status = if params["status"] == "", do: nil, else: params["status"]
    source_type = if params["source_type"] == "", do: nil, else: params["source_type"]

    {:noreply,
     socket
     |> assign(:filter_status, status || socket.assigns.filter_status)
     |> assign(:filter_source_type, source_type || socket.assigns.filter_source_type)
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
    {:noreply,
     socket
     |> assign(:page, String.to_integer(page))
     |> load_texts()}
  end

  def handle_event("add_target_language", %{"locale_code" => ""}, socket),
    do: {:noreply, socket}

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

  defp with_auth(action, socket, fun) do
    case authorize(socket, action) do
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
end
