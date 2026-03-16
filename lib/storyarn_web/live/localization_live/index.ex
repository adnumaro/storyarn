defmodule StoryarnWeb.LocalizationLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view
  alias StoryarnWeb.Helpers.Authorize

  import StoryarnWeb.Components.UIComponents, only: [empty_state: 1]
  import StoryarnWeb.Live.Shared.TreePanelHandlers
  alias Storyarn.Localization
  alias Storyarn.Projects
  alias StoryarnWeb.Components.LanguagePicker
  alias StoryarnWeb.Components.LocaleMark
  alias StoryarnWeb.Components.PopoverSelect

  import StoryarnWeb.LocalizationLive.Helpers.LocalizationHelpers
  alias StoryarnWeb.LocalizationLive.Handlers.LocalizationHandlers

  @page_size 50

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.focus
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      active_tool={:localization}
      on_dashboard={true}
      has_tree={true}
      tree_panel_open={@tree_panel_open}
      tree_panel_pinned={@tree_panel_pinned}
      show_pin={false}
      can_edit={@can_edit}
    >
      <:tree_content>
        <.localization_sidebar
          source_language={@source_language}
          languages={@languages}
          target_languages={@target_languages}
          selected_locale={@selected_locale}
          can_edit={@can_edit}
        />
      </:tree_content>
      <:top_bar_extra_right :if={@can_edit && @target_languages != []}>
        <div class="flex items-center gap-1 px-1.5 py-1 surface-panel">
          <.link
            navigate={
              ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/localization/report"
            }
            class="btn btn-ghost btn-sm gap-1.5"
          >
            <.icon name="bar-chart-3" class="size-4" />
            <span class="hidden xl:inline">{dgettext("localization", "Report")}</span>
          </.link>
          <div :if={@selected_locale} class="dropdown dropdown-end">
            <div tabindex="0" role="button" class="btn btn-ghost btn-sm gap-1.5">
              <.icon name="download" class="size-4" />
              <span class="hidden xl:inline">{dgettext("localization", "Export")}</span>
            </div>
            <ul
              tabindex="0"
              class="dropdown-content menu bg-base-100 rounded-box z-50 w-40 p-2 shadow-lg border border-base-300 mt-2"
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
            class="btn btn-primary btn-sm gap-1.5"
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
            class="rounded-[1.5rem] border border-base-300 bg-base-200/60 p-4"
          >
            <div class="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
              <div class="space-y-1">
                <p class="text-xs font-semibold uppercase tracking-[0.18em] text-base-content/50">
                  {dgettext("localization", "Progress")}
                </p>
                <h2 class="text-lg font-semibold">
                  {dgettext("localization", "Final translations")}
                </h2>
                <p class="text-sm text-base-content/60">
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
                <div class="flex items-center justify-between text-sm text-base-content/70">
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
            <PopoverSelect.popover_select
              id="localization-status-filter"
              event="change_filter"
              param_key="status"
              options={status_filter_options()}
              selected_value={@filter_status}
              selected_label={selected_status_filter_label(@filter_status)}
              placeholder={dgettext("localization", "All statuses")}
            />

            <PopoverSelect.popover_select
              id="localization-source-type-filter"
              event="change_filter"
              param_key="source_type"
              options={source_type_filter_options()}
              selected_value={@filter_source_type}
              selected_label={selected_source_type_filter_label(@filter_source_type)}
              placeholder={dgettext("localization", "All types")}
            />

            <%!-- Search --%>
            <form id="localization-search-form" phx-change="search" class="flex-1">
              <label class="input input-sm input-bordered flex items-center gap-2">
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
    </Layouts.focus>
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

  attr :source_language, :map, default: nil
  attr :languages, :list, default: []
  attr :target_languages, :list, default: []
  attr :selected_locale, :string, default: nil
  attr :can_edit, :boolean, default: false

  defp localization_sidebar(assigns) do
    ~H"""
    <div id="localization-sidebar" class="space-y-6">
      <section :if={@source_language} id="localization-sidebar-source-language" class="space-y-2">
        <p class="px-1 text-[11px] font-semibold uppercase tracking-[0.18em] text-base-content/50">
          {dgettext("localization", "Source language")}
        </p>
        <div
          id="localization-source-language-option"
          class="flex items-center gap-2 rounded-[1rem] border border-primary/30 bg-primary/10 p-2"
        >
          <div class="flex min-w-0 flex-1 items-center gap-3">
            <LocaleMark.locale_mark locale_code={@source_language.locale_code} />
            <span class="min-w-0">
              <span class="block truncate text-sm font-medium text-base-content">
                {@source_language.name}
              </span>
            </span>
          </div>
        </div>
        <LanguagePicker.language_picker
          :if={@can_edit}
          id="localization-source-language-picker"
          event="change_source_language"
          options={LanguagePicker.source_language_options(@source_language)}
          placeholder={dgettext("localization", "Change source language...")}
          search_placeholder={dgettext("localization", "Search languages...")}
          empty_label={dgettext("localization", "No matches")}
          button_icon="languages"
        />
      </section>

      <section id="localization-sidebar-language-selector" class="space-y-2">
        <div class="flex items-center justify-between px-1">
          <p class="text-[11px] font-semibold uppercase tracking-[0.18em] text-base-content/50">
            {dgettext("localization", "Target languages")}
          </p>
          <span :if={@target_languages != []} class="badge badge-ghost badge-xs">
            {length(@target_languages)}
          </span>
        </div>

        <div
          :if={@target_languages == []}
          class="rounded-[1.25rem] border border-dashed border-base-300 bg-base-200/40 p-3 text-sm text-base-content/60"
        >
          {dgettext("localization", "No target languages yet.")}
        </div>

        <div :if={@target_languages != []} class="space-y-2">
          <div
            :for={lang <- @target_languages}
            id={"localization-language-option-#{lang.id}"}
            class={[
              "flex items-center gap-2 rounded-[1rem] border p-2 transition-colors",
              if(lang.locale_code == @selected_locale,
                do: "border-primary/30 bg-primary/10",
                else: "border-base-300 bg-base-100 hover:bg-base-200/70"
              )
            ]}
          >
            <button
              id={"select-locale-#{lang.locale_code}"}
              type="button"
              phx-click="change_locale"
              phx-value-locale={lang.locale_code}
              class="flex min-w-0 flex-1 items-center gap-3 text-left"
            >
              <LocaleMark.locale_mark
                locale_code={lang.locale_code}
                class={if(lang.locale_code == @selected_locale, do: nil, else: "opacity-90")}
              />
              <span class="min-w-0">
                <span class="block truncate text-sm font-medium text-base-content">
                  {lang.name}
                </span>
              </span>
            </button>

            <button
              :if={@can_edit}
              type="button"
              phx-click={show_modal("remove-language-#{lang.id}")}
              class="btn btn-ghost btn-xs btn-square text-base-content/50 hover:text-error"
              title={dgettext("localization", "Remove language")}
            >
              <.icon name="x" class="size-3.5" />
            </button>
          </div>
        </div>

        <.add_language_picker
          :if={@can_edit}
          languages={@languages}
          source_language={@source_language}
        />

        <button
          :if={@can_edit && @target_languages != []}
          id="localization-sync-button"
          type="button"
          phx-click="sync_texts"
          phx-disable-with={dgettext("localization", "Syncing...")}
          class="btn btn-ghost btn-sm w-full justify-start gap-2"
          title={
            dgettext(
              "localization",
              "Re-extract all translatable content from flows, sheets, and blocks"
            )
          }
        >
          <.icon name="refresh-cw" class="size-4" />
          {dgettext("localization", "Sync")}
        </button>
      </section>
    </div>
    """
  end

  attr :languages, :list, default: []
  attr :source_language, :map, default: nil

  defp add_language_picker(assigns) do
    picker_options = language_picker_options(assigns)

    assigns =
      assigns
      |> assign(:picker_options, picker_options)
      |> assign(:picker_disabled, picker_options == [])

    ~H"""
    <div>
      <div :if={!@picker_disabled}>
        <LanguagePicker.language_picker
          id="localization-language-picker"
          event="add_target_language"
          options={@picker_options}
          placeholder={dgettext("localization", "Add language")}
          search_placeholder={dgettext("localization", "Search languages...")}
          empty_label={dgettext("localization", "No matches")}
          button_icon="plus"
        />
      </div>

      <div
        :if={@picker_disabled}
        id="localization-language-picker"
        class="rounded-[1rem] border border-dashed border-base-300 bg-base-200/40 px-3 py-2 text-sm text-base-content/60"
      >
        {dgettext("localization", "All available languages are already added.")}
      </div>
    </div>
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
          |> assign(:tree_panel_open, true)
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
  def handle_event("tree_panel_" <> _ = event, params, socket),
    do: handle_tree_panel_event(event, params, socket)

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

  defp status_filter_options do
    [
      {dgettext("localization", "All statuses"), ""}
      | Enum.map(~w(pending draft in_progress review final), &{status_label(&1), &1})
    ]
  end

  defp source_type_filter_options do
    [
      {dgettext("localization", "All types"), ""}
      | Enum.map(~w(flow_node block sheet flow scene), &{source_type_label(&1), &1})
    ]
  end

  defp selected_status_filter_label(nil), do: dgettext("localization", "All statuses")
  defp selected_status_filter_label(status), do: status_label(status)

  defp selected_source_type_filter_label(nil), do: dgettext("localization", "All types")
  defp selected_source_type_filter_label(source_type), do: source_type_label(source_type)

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
