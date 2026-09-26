defmodule StoryarnWeb.TemplateLive.Index do
  @moduledoc """
  Lists project templates visible to the authenticated user.
  """

  use StoryarnWeb, :live_view

  alias Storyarn.Projects

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
      <.vue
        v-component="live/template/list/TemplateList"
        v-socket={@socket}
        v-inject="workspace-layout"
        id="templates-index-page"
        sections={serialize_sections(assigns)}
        query={@search}
        pending-delete-id={@pending_delete_template_id}
        workspaces-href={~p"/workspaces"}
      />
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
         {:ok, template} <- Projects.get_project_template(socket.assigns.current_scope, template_id),
         {:ok, _template} <- Projects.archive_project_template(socket.assigns.current_scope, template) do
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
         {:ok, template} <-
           Projects.get_project_template(socket.assigns.current_scope, template_id, status: "archived"),
         {:ok, _template} <- Projects.unarchive_project_template(socket.assigns.current_scope, template) do
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
         {:ok, template} <-
           Projects.get_project_template(socket.assigns.current_scope, template_id, status: "archived"),
         {:ok, _template} <- Projects.delete_project_template(socket.assigns.current_scope, template) do
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

  defp serialize_sections(assigns) do
    %{current_scope: scope, template_query_params: params} = assigns

    Enum.map(
      [
        {"private", assigns.private_page},
        {"public", assigns.public_page},
        {"archived", assigns.archived_page}
      ],
      fn {key, page} ->
        %{
          key: key,
          templates:
            Enum.map(
              page.entries,
              &serialize_template(&1, key != "public" && Projects.can_manage_project_template?(scope, &1))
            ),
          totalCount: page.total_count,
          page: page.page,
          totalPages: page.total_pages,
          prevHref: if(page.page > 1, do: page_patch(params, key, page.page - 1)),
          nextHref: if(page.page < page.total_pages, do: page_patch(params, key, page.page + 1))
        }
      end
    )
  end

  defp serialize_template(template, can_manage) do
    %{
      id: template.id,
      name: template.name,
      description: template.description,
      visibility: template.visibility,
      versionNumber: version_number(template.current_version),
      updatedAt: template.updated_at,
      previewNames: preview_names(template.current_version),
      canManage: can_manage,
      href: ~p"/templates/#{template.id}"
    }
  end

  defp version_number(%{version_number: number}) when is_integer(number), do: number
  defp version_number(_version), do: nil

  defp refresh_templates(socket) do
    assign_template_pages(socket, socket.assigns.template_query_params)
  end

  defp assign_template_pages(socket, params) do
    search = params |> Map.get("q", "") |> normalize_search()

    private_page =
      Projects.paginate_project_templates(socket.assigns.current_scope,
        status: "active",
        visibility: "private",
        search: search,
        page: Map.get(params, "private_page"),
        per_page: @section_per_page
      )

    public_page =
      Projects.paginate_project_templates(socket.assigns.current_scope,
        status: "active",
        visibility: "public",
        search: search,
        page: Map.get(params, "public_page"),
        per_page: @section_per_page
      )

    archived_page =
      Projects.paginate_project_templates(socket.assigns.current_scope,
        status: "archived",
        search: search,
        page: Map.get(params, "archived_page"),
        per_page: @section_per_page
      )

    socket
    |> assign(:search, search)
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

  defp preview_names(%{preview: %{} = preview}) do
    ["sheets", "flows", "scenes"]
    |> Enum.flat_map(fn type ->
      preview
      |> Map.get(type, [])
      |> Enum.map(&Map.get(&1, "name"))
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.take(3)
  end

  defp preview_names(_version), do: []

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
