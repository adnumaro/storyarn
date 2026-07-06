defmodule StoryarnWeb.TemplateLive.Index do
  @moduledoc """
  Lists project templates visible to the authenticated user.
  """

  use StoryarnWeb, :live_view

  import StoryarnWeb.TemplateLive.Helpers

  alias Storyarn.ProjectTemplates

  @section_per_page 9

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_new(:current_workspace, fn -> nil end)
     |> assign_new(:workspaces, fn -> [] end)
     |> assign(:page_title, dgettext("projects", "Templates"))
     |> assign(:pending_delete_template_id, nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign_template_pages(socket, params)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.WorkspaceLayout.workspace
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      current_workspace={@current_workspace}
      workspaces={@workspaces}
    >
      <main id="templates-index" class="min-h-dvh bg-base-100 px-6 py-8 lg:px-10">
        <div class="mx-auto flex w-full max-w-6xl flex-col gap-8">
          <header class="flex flex-col gap-3 border-b border-base-300 pb-6 md:flex-row md:items-end md:justify-between">
            <div>
              <p class="text-sm font-medium text-base-content/60">
                {dgettext("projects", "Project templates")}
              </p>
              <h1 class="text-3xl font-semibold tracking-normal text-base-content">
                {dgettext("projects", "Templates")}
              </h1>
            </div>

            <.link navigate={~p"/workspaces"} class="btn btn-ghost btn-sm">
              {dgettext("workspaces", "Workspaces")}
            </.link>
          </header>

          <section class="rounded-box border border-base-300 bg-base-100 p-4">
            <.form for={@search_form} id="template-search-form" phx-submit="search">
              <div class="flex flex-col gap-3 md:flex-row md:items-end">
                <label class="form-control flex-1 gap-2">
                  <span class="label-text">{dgettext("projects", "Search templates")}</span>
                  <input
                    id="template-search-input"
                    name={@search_form[:q].name}
                    value={@search_form[:q].value}
                    type="search"
                    class="input input-bordered w-full"
                    placeholder={dgettext("projects", "Search by name or description")}
                  />
                </label>
                <div class="flex gap-2">
                  <button id="template-search-submit" type="submit" class="btn btn-primary">
                    {dgettext("projects", "Search")}
                  </button>
                  <button
                    :if={@search != ""}
                    id="template-search-clear"
                    type="button"
                    class="btn btn-ghost"
                    phx-click="clear_search"
                  >
                    {dgettext("projects", "Clear")}
                  </button>
                </div>
              </div>
            </.form>
          </section>

          <section id="my-templates-section" class="flex flex-col gap-4">
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-semibold text-base-content">
                {dgettext("projects", "Private templates")}
              </h2>
              <span class="badge badge-neutral">{@private_page.total_count}</span>
            </div>

            <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
              <%= for template <- @private_page.entries do %>
                <.template_card
                  template={template}
                  can_manage={ProjectTemplates.can_manage_template?(@current_scope, template)}
                />
              <% end %>
              <div
                :if={@private_page.entries == []}
                id="my-templates-empty"
                class="rounded-box border border-dashed border-base-300 p-6 text-sm text-base-content/60"
              >
                {dgettext("projects", "No private templates yet.")}
              </div>
            </div>

            <.pagination page={@private_page} section="private" params={@template_query_params} />
          </section>

          <section id="public-templates-section" class="flex flex-col gap-4">
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-semibold text-base-content">
                {dgettext("projects", "Storyarn demos")}
              </h2>
              <span class="badge badge-neutral">{@public_page.total_count}</span>
            </div>

            <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
              <%= for template <- @public_page.entries do %>
                <.template_card template={template} can_manage={false} />
              <% end %>
              <div
                :if={@public_page.entries == []}
                id="public-templates-empty"
                class="rounded-box border border-dashed border-base-300 p-6 text-sm text-base-content/60"
              >
                {dgettext("projects", "No public demos available.")}
              </div>
            </div>

            <.pagination page={@public_page} section="public" params={@template_query_params} />
          </section>

          <section id="archived-templates-section" class="flex flex-col gap-4">
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-semibold text-base-content">
                {dgettext("projects", "Archived templates")}
              </h2>
              <span class="badge badge-neutral">{@archived_page.total_count}</span>
            </div>

            <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
              <%= for template <- @archived_page.entries do %>
                <.template_card
                  template={template}
                  can_manage={ProjectTemplates.can_manage_template?(@current_scope, template)}
                  archived
                  pending_delete={@pending_delete_template_id == template.id}
                />
              <% end %>
              <div
                :if={@archived_page.entries == []}
                id="archived-templates-empty"
                class="rounded-box border border-dashed border-base-300 p-6 text-sm text-base-content/60"
              >
                {dgettext("projects", "No archived templates.")}
              </div>
            </div>

            <.pagination page={@archived_page} section="archived" params={@template_query_params} />
          </section>
        </div>
      </main>
    </StoryarnWeb.Components.WorkspaceLayout.workspace>
    """
  end

  @impl true
  def handle_event("search", %{"search" => search_params}, socket) do
    query = search_params |> Map.get("q", "") |> normalize_search()
    {:noreply, push_patch(socket, to: ~p"/templates?#{search_patch_params(query)}")}
  end

  def handle_event("clear_search", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/templates")}
  end

  def handle_event("archive_template", %{"id" => id}, socket) do
    with {:ok, template_id} <- parse_template_id(id),
         {:ok, template} <- ProjectTemplates.get_template(socket.assigns.current_scope, template_id),
         {:ok, _template} <- ProjectTemplates.archive_template(socket.assigns.current_scope, template) do
      {:noreply,
       socket
       |> assign(:pending_delete_template_id, nil)
       |> refresh_templates()
       |> put_flash(:info, dgettext("projects", "Template archived."))}
    else
      _reason ->
        {:noreply, put_flash(socket, :error, dgettext("projects", "Template could not be archived."))}
    end
  end

  def handle_event("unarchive_template", %{"id" => id}, socket) do
    with {:ok, template_id} <- parse_template_id(id),
         {:ok, template} <- ProjectTemplates.get_template(socket.assigns.current_scope, template_id, status: "archived"),
         {:ok, _template} <- ProjectTemplates.unarchive_template(socket.assigns.current_scope, template) do
      {:noreply,
       socket
       |> assign(:pending_delete_template_id, nil)
       |> refresh_templates()
       |> put_flash(:info, dgettext("projects", "Template restored."))}
    else
      _reason ->
        {:noreply, put_flash(socket, :error, dgettext("projects", "Template could not be restored."))}
    end
  end

  def handle_event("delete_template", %{"id" => id}, socket) do
    with {:ok, template_id} <- parse_template_id(id),
         {:ok, template} <- ProjectTemplates.get_template(socket.assigns.current_scope, template_id, status: "archived"),
         {:ok, _template} <- ProjectTemplates.delete_template(socket.assigns.current_scope, template) do
      {:noreply,
       socket
       |> assign(:pending_delete_template_id, nil)
       |> refresh_templates()
       |> put_flash(:info, dgettext("projects", "Template permanently deleted."))}
    else
      _reason ->
        {:noreply, put_flash(socket, :error, dgettext("projects", "Template could not be deleted."))}
    end
  end

  def handle_event("prepare_delete_template", %{"id" => id}, socket) do
    case parse_template_id(id) do
      {:ok, template_id} ->
        {:noreply, assign(socket, :pending_delete_template_id, template_id)}

      _reason ->
        {:noreply, put_flash(socket, :error, dgettext("projects", "Template could not be deleted."))}
    end
  end

  def handle_event("cancel_delete_template", _params, socket) do
    {:noreply, assign(socket, :pending_delete_template_id, nil)}
  end

  attr :template, :map, required: true
  attr :can_manage, :boolean, required: true
  attr :archived, :boolean, default: false
  attr :pending_delete, :boolean, default: false

  defp template_card(assigns) do
    ~H"""
    <article
      id={"template-card-#{@template.id}"}
      class="card border border-base-300 bg-base-100 shadow-sm transition hover:border-base-content/20"
    >
      <div class="card-body gap-4 p-5">
        <div class="flex items-start justify-between gap-3">
          <div class="min-w-0">
            <h3 class="truncate text-base font-semibold text-base-content">{@template.name}</h3>
            <p class="mt-1 line-clamp-2 text-sm text-base-content/60">
              {template_description(@template)}
            </p>
          </div>
          <span class={["badge shrink-0", visibility_badge_class(@template.visibility)]}>
            {visibility_label(@template.visibility)}
          </span>
        </div>

        <div class="flex items-center justify-between text-xs text-base-content/60">
          <span>{version_label(@template.current_version)}</span>
          <span>{format_datetime(@template.updated_at)}</span>
        </div>

        <p :if={preview_summary(@template.current_version) != ""} class="text-xs text-base-content/55">
          {preview_summary(@template.current_version)}
        </p>

        <div
          :if={@pending_delete}
          id={"delete-template-confirmation-#{@template.id}"}
          class="rounded-box border border-error/30 bg-error/10 p-3 text-xs text-error"
        >
          {dgettext("projects", "Delete this template permanently? This cannot be undone.")}
        </div>

        <div class="card-actions justify-end">
          <button
            :if={@can_manage and not @archived}
            id={"archive-template-#{@template.id}"}
            type="button"
            class="btn btn-ghost btn-sm text-error"
            phx-click="archive_template"
            phx-value-id={@template.id}
          >
            {dgettext("projects", "Archive")}
          </button>
          <button
            :if={@can_manage and @archived}
            id={"unarchive-template-#{@template.id}"}
            type="button"
            class="btn btn-outline btn-sm"
            phx-click="unarchive_template"
            phx-value-id={@template.id}
          >
            {dgettext("projects", "Restore")}
          </button>
          <button
            :if={@can_manage and @archived and not @pending_delete}
            id={"delete-template-#{@template.id}"}
            type="button"
            class="btn btn-ghost btn-sm text-error"
            phx-click="prepare_delete_template"
            phx-value-id={@template.id}
          >
            {dgettext("projects", "Delete")}
          </button>
          <button
            :if={@can_manage and @archived and @pending_delete}
            id={"cancel-delete-template-#{@template.id}"}
            type="button"
            class="btn btn-ghost btn-sm"
            phx-click="cancel_delete_template"
          >
            {dgettext("projects", "Cancel")}
          </button>
          <button
            :if={@can_manage and @archived and @pending_delete}
            id={"confirm-delete-template-#{@template.id}"}
            type="button"
            class="btn btn-error btn-sm"
            phx-click="delete_template"
            phx-value-id={@template.id}
          >
            {dgettext("projects", "Delete permanently")}
          </button>
          <.link
            :if={not @archived}
            navigate={~p"/templates/#{@template.id}"}
            class="btn btn-primary btn-sm"
          >
            {dgettext("projects", "Open")}
          </.link>
        </div>
      </div>
    </article>
    """
  end

  attr :page, :map, required: true
  attr :section, :string, required: true
  attr :params, :map, required: true

  defp pagination(assigns) do
    ~H"""
    <nav :if={@page.total_pages > 1} class="flex items-center justify-end gap-2">
      <.link
        id={"#{@section}-templates-prev-page"}
        patch={page_patch(@params, @section, @page.page - 1)}
        class={["btn btn-outline btn-sm", @page.page <= 1 && "btn-disabled"]}
      >
        {dgettext("projects", "Previous")}
      </.link>
      <span class="text-sm text-base-content/60">
        {dgettext("projects", "Page %{page} of %{total}", page: @page.page, total: @page.total_pages)}
      </span>
      <.link
        id={"#{@section}-templates-next-page"}
        patch={page_patch(@params, @section, @page.page + 1)}
        class={["btn btn-outline btn-sm", @page.page >= @page.total_pages && "btn-disabled"]}
      >
        {dgettext("projects", "Next")}
      </.link>
    </nav>
    """
  end

  defp refresh_templates(socket) do
    assign_template_pages(socket, socket.assigns.template_query_params)
  end

  defp assign_template_pages(socket, params) do
    search = params |> Map.get("q", "") |> normalize_search()

    private_page =
      ProjectTemplates.paginate_templates(socket.assigns.current_scope,
        status: "active",
        visibility: "private",
        search: search,
        page: Map.get(params, "private_page"),
        per_page: @section_per_page
      )

    public_page =
      ProjectTemplates.paginate_templates(socket.assigns.current_scope,
        status: "active",
        visibility: "public",
        search: search,
        page: Map.get(params, "public_page"),
        per_page: @section_per_page
      )

    archived_page =
      ProjectTemplates.paginate_templates(socket.assigns.current_scope,
        status: "archived",
        search: search,
        page: Map.get(params, "archived_page"),
        per_page: @section_per_page
      )

    socket
    |> assign(:search, search)
    |> assign(:search_form, to_form(%{"q" => search}, as: :search))
    |> assign(:private_page, private_page)
    |> assign(:public_page, public_page)
    |> assign(:archived_page, archived_page)
    |> assign(:template_query_params, %{
      "q" => search,
      "private_page" => private_page.page,
      "public_page" => public_page.page,
      "archived_page" => archived_page.page
    })
  end

  defp search_patch_params(""), do: %{}
  defp search_patch_params(query), do: %{"q" => query}

  defp page_patch(params, section, page) do
    patch_params =
      params
      |> Map.put(section_page_param(section), page)
      |> clean_patch_params()

    ~p"/templates?#{patch_params}"
  end

  defp section_page_param("private"), do: "private_page"
  defp section_page_param("public"), do: "public_page"
  defp section_page_param("archived"), do: "archived_page"

  defp clean_patch_params(params) do
    params
    |> Enum.reject(fn
      {"q", ""} -> true
      {_key, value} when value in [nil, "", 1, "1"] -> true
      _other -> false
    end)
    |> Map.new()
  end

  defp preview_summary(%{preview: %{} = preview}) do
    ["sheets", "flows", "scenes"]
    |> Enum.flat_map(fn type ->
      preview
      |> Map.get(type, [])
      |> Enum.map(&Map.get(&1, "name"))
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.take(3)
    |> case do
      [] -> ""
      names -> Enum.join(names, " / ")
    end
  end

  defp preview_summary(_version), do: ""

  defp normalize_search(search) when is_binary(search), do: String.trim(search)
  defp normalize_search(_search), do: ""

  defp parse_template_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> {:error, :invalid_template_id}
    end
  end

  defp parse_template_id(value) when is_integer(value), do: {:ok, value}
  defp parse_template_id(_value), do: {:error, :invalid_template_id}
end
