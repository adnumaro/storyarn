defmodule StoryarnWeb.LocalizationLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view
  alias StoryarnWeb.Helpers.Authorize

  import StoryarnWeb.Components.UIComponents, only: [empty_state: 1]
  import StoryarnWeb.Live.Shared.TreePanelHandlers, only: [focus_layout_defaults: 0]
  alias Storyarn.Localization
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
      has_tree={false}
      can_edit={@can_edit}
    >
      <:top_bar_extra_right :if={@can_edit && @target_languages != []}>
        <div class="flex items-center gap-1 px-1.5 py-1 surface-panel">
          <.link
            navigate={
              ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/localization/report"
            }
            class="inline-flex items-center justify-center h-8 px-3 text-sm rounded-md hover:bg-accent transition-colors gap-1.5"
          >
            <.icon name="bar-chart-3" class="size-4" />
            <span class="hidden xl:inline">{dgettext("localization", "Report")}</span>
          </.link>
          <div :if={@selected_locale} class="relative">
            <div
              tabindex="0"
              role="button"
              class="inline-flex items-center justify-center h-8 px-3 text-sm rounded-md hover:bg-accent transition-colors gap-1.5"
            >
              <.icon name="download" class="size-4" />
              <span class="hidden xl:inline">{dgettext("localization", "Export")}</span>
            </div>
            <ul
              tabindex="0"
              class="absolute top-full mt-1 menu bg-background rounded-box z-50 w-40 p-2 shadow-lg border border-border mt-2"
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
          <button
            :if={@has_provider}
            phx-click="translate_batch"
            phx-disable-with={dgettext("localization", "Translating...")}
            class="inline-flex items-center justify-center h-8 px-3 text-sm font-medium rounded-md bg-primary text-primary-foreground hover:bg-primary/90 transition-colors gap-1.5"
          >
            <.icon name="languages" class="size-4" />
            <span class="hidden xl:inline">{dgettext("localization", "Translate All Pending")}</span>
          </button>
        </div>
      </:top_bar_extra_right>
      <div class="mx-auto mt-4 max-w-6xl space-y-6">
        <.header>
          {dgettext("localization", "Localization")}
          <:subtitle>
            {dgettext(
              "localization",
              "Review source strings, filter translations, and track progress for every target language."
            )}
          </:subtitle>
        </.header>

        <%!-- No target languages yet --%>
        <div :if={@target_languages == []}>
          <.empty_state icon="globe">
            {dgettext(
              "localization",
              "Use the sidebar to add a target language and start translating."
            )}
          </.empty_state>
        </div>

        <%!-- Filters + Progress (only when target languages exist) --%>
        <div :if={@target_languages != []} class="space-y-4">
          <div
            :if={@progress}
            id="localization-progress-summary"
            class="rounded-[1.5rem] border border-border bg-muted/60 p-4"
          >
            <div class="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
              <div class="space-y-1">
                <p class="text-xs font-semibold uppercase tracking-[0.18em] text-muted-foreground">
                  {dgettext("localization", "Progress")}
                </p>
                <h2 class="text-lg font-semibold">
                  {dgettext("localization", "Final translations")}
                </h2>
                <p class="text-sm text-muted-foreground">
                  {dgettext(
                    "localization",
                    "Measure the strings that are ready to ship in the active language."
                  )}
                </p>
              </div>
              <div class="min-w-0 lg:w-72 space-y-2">
                <progress
                  class="progress progress-primary w-full"
                  value={@progress.final}
                  max={max(@progress.total, 1)}
                />
                <div class="flex items-center justify-between text-sm text-muted-foreground">
                  <span>
                    {dgettext("localization", "%{done} / %{total} final",
                      done: @progress.final,
                      total: @progress.total
                    )}
                  </span>
                  <span class="tabular-nums">
                    {if @progress.total > 0,
                      do: round(@progress.final * 100 / @progress.total),
                      else: 0}%
                  </span>
                </div>
              </div>
            </div>
          </div>

          <%!-- Filters row --%>
          <div class="flex flex-col gap-3 lg:flex-row lg:items-center">
            <.vue
              v-component="form-fields/SelectField"
              v-socket={@socket}
              id="localization-status-filter"
              options={[
                %{value: "", label: dgettext("localization", "All statuses")},
                %{value: "pending", label: dgettext("localization", "Pending")},
                %{value: "draft", label: dgettext("localization", "Draft")},
                %{value: "in_progress", label: dgettext("localization", "In progress")},
                %{value: "review", label: dgettext("localization", "Review")},
                %{value: "final", label: dgettext("localization", "Final")}
              ]}
              value={@filter_status || ""}
              placeholder={dgettext("localization", "All statuses")}
              event="change_filter"
              param-key="status"
            />
            <.vue
              v-component="form-fields/SelectField"
              v-socket={@socket}
              id="localization-source-type-filter"
              options={[
                %{value: "", label: dgettext("localization", "All types")},
                %{value: "flow_node", label: dgettext("localization", "Flow node")},
                %{value: "block", label: dgettext("localization", "Block")},
                %{value: "sheet", label: dgettext("localization", "Sheet")},
                %{value: "flow", label: dgettext("localization", "Flow")},
                %{value: "scene", label: dgettext("localization", "Scene")}
              ]}
              value={@filter_source_type || ""}
              placeholder={dgettext("localization", "All types")}
              event="change_filter"
              param-key="source_type"
            />

            <%!-- Search --%>
            <form id="localization-search-form" phx-change="search" class="flex-1">
              <label class="h-8 rounded-md border border-input bg-background px-2 text-sm input-bordered flex items-center gap-2">
                <.icon name="search" class="size-4 opacity-50" />
                <input
                  id="localization-search-input"
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
            <table class="w-full text-sm">
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
                      class="text-xs px-1.5 py-0.5 rounded bg-muted text-muted-foreground badge-sm"
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
                      class="text-[10px] px-1 rounded bg-muted text-muted-foreground badge-outline opacity-60"
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
                      class="inline-flex items-center justify-center px-3 py-2 text-sm rounded-md hover:bg-accent transition-colors btn-xs"
                    >
                      <.icon name="pencil" class="size-3.5" />
                    </.link>
                    <button
                      :if={@has_provider && !text.translated_text}
                      phx-click="translate_single"
                      phx-value-id={text.id}
                      class="inline-flex items-center justify-center px-3 py-2 text-sm rounded-md hover:bg-accent transition-colors btn-xs"
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
                class="join-item inline-flex items-center justify-center h-8 px-3 text-sm rounded-md bg-primary text-primary-foreground hover:bg-primary/90"
                disabled={@page == 1}
                phx-click="change_page"
                phx-value-page={@page - 1}
              >
                «
              </button>
              <button class="join-item inline-flex items-center justify-center h-8 px-3 text-sm rounded-md bg-primary text-primary-foreground hover:bg-primary/90 btn-disabled">
                {dgettext("localization", "Page %{page} of %{total}",
                  page: @page,
                  total: ceil(@total_count / @page_size)
                )}
              </button>
              <button
                class="join-item inline-flex items-center justify-center h-8 px-3 text-sm rounded-md bg-primary text-primary-foreground hover:bg-primary/90"
                disabled={@page * @page_size >= @total_count}
                phx-click="change_page"
                phx-value-page={@page + 1}
              >
                »
              </button>
            </div>
          </div>
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
    </Layouts.app>
    """
  end

  attr :status, :string, required: true

  defp status_badge(assigns) do
    ~H"""
    <span class={[
      "text-xs px-1.5 py-0.5 rounded bg-muted text-muted-foreground",
      status_class(@status)
    ]}>
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
