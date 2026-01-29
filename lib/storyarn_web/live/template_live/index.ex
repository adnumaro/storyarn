defmodule StoryarnWeb.TemplateLive.Index do
  use StoryarnWeb, :live_view

  alias Storyarn.Entities
  alias Storyarn.Entities.EntityTemplate
  alias Storyarn.Projects

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mb-8">
        <.back navigate={~p"/projects/#{@project.id}"}>{gettext("Back to project")}</.back>
      </div>

      <div class="text-center mb-8">
        <.header>
          {gettext("Entity Templates")}
          <:subtitle>
            {gettext("Define the structure for your characters, locations, and items")}
          </:subtitle>
          <:actions :if={@can_edit}>
            <.link patch={~p"/projects/#{@project.id}/templates/new"} class="btn btn-primary">
              <.icon name="hero-plus" class="size-4 mr-2" />
              {gettext("New Template")}
            </.link>
          </:actions>
        </.header>
      </div>

      <div :if={@templates == []} class="text-center py-12">
        <.icon name="hero-document-duplicate" class="size-12 mx-auto text-base-content/30 mb-4" />
        <p class="text-base-content/70 mb-4">
          {gettext("No templates yet.")}
        </p>
        <button
          :if={@can_edit}
          type="button"
          class="btn btn-outline"
          phx-click="create_defaults"
        >
          {gettext("Create Default Templates")}
        </button>
      </div>

      <div :if={@templates != []} class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <.template_card
          :for={template <- @templates}
          template={template}
          entity_count={Map.get(@entity_counts, template.id, 0)}
          project={@project}
          can_edit={@can_edit}
        />
      </div>

      <.modal
        :if={@live_action in [:new, :edit]}
        id="template-modal"
        show
        on_cancel={JS.patch(~p"/projects/#{@project.id}/templates")}
      >
        <.template_form
          form={@form}
          title={if @live_action == :new, do: gettext("New Template"), else: gettext("Edit Template")}
          action={@live_action}
          project={@project}
        />
      </.modal>
    </Layouts.app>
    """
  end

  attr :template, :map, required: true
  attr :entity_count, :integer, required: true
  attr :project, :map, required: true
  attr :can_edit, :boolean, required: true

  defp template_card(assigns) do
    ~H"""
    <div class="card bg-base-100 border border-base-300 shadow-sm">
      <div class="card-body">
        <div class="flex items-start justify-between gap-2">
          <div class="flex items-center gap-2">
            <.icon name={@template.icon} class="size-6" style={"color: #{@template.color}"} />
            <div>
              <h3 class="card-title text-lg">{@template.name}</h3>
              <span class="badge badge-sm badge-ghost">{@template.type}</span>
            </div>
          </div>
          <span :if={@template.is_default} class="badge badge-sm badge-outline">
            {gettext("Default")}
          </span>
        </div>
        <p :if={@template.description} class="text-sm text-base-content/70 line-clamp-2">
          {@template.description}
        </p>
        <div class="flex items-center justify-between mt-2">
          <span class="text-sm text-base-content/50">
            {ngettext("%{count} entity", "%{count} entities", @entity_count)}
          </span>
          <div :if={@can_edit} class="flex gap-2">
            <.link
              patch={~p"/projects/#{@project.id}/templates/#{@template.id}/edit"}
              class="btn btn-ghost btn-xs"
            >
              <.icon name="hero-pencil" class="size-3" />
            </.link>
            <button
              :if={@entity_count == 0}
              type="button"
              class="btn btn-ghost btn-xs text-error"
              phx-click="delete"
              phx-value-id={@template.id}
              data-confirm={gettext("Are you sure you want to delete this template?")}
            >
              <.icon name="hero-trash" class="size-3" />
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :title, :string, required: true
  attr :action, :atom, required: true
  attr :project, :map, required: true

  defp template_form(assigns) do
    ~H"""
    <div>
      <.header>{@title}</.header>

      <.form
        for={@form}
        id="template-form"
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:name]}
          type="text"
          label={gettext("Name")}
          placeholder={gettext("Character")}
          required
        />
        <.input
          :if={@action == :new}
          field={@form[:type]}
          type="select"
          label={gettext("Type")}
          options={type_options()}
          required
        />
        <.input
          field={@form[:description]}
          type="textarea"
          label={gettext("Description")}
          rows={2}
        />
        <div class="grid grid-cols-2 gap-4">
          <.input
            field={@form[:color]}
            type="color"
            label={gettext("Color")}
          />
          <.input
            field={@form[:icon]}
            type="select"
            label={gettext("Icon")}
            options={icon_options()}
          />
        </div>

        <div class="modal-action">
          <.link patch={~p"/projects/#{@project.id}/templates"} class="btn btn-ghost">
            {gettext("Cancel")}
          </.link>
          <.button variant="primary" phx-disable-with={gettext("Saving...")}>
            {if @action == :new, do: gettext("Create Template"), else: gettext("Save Changes")}
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  defp type_options do
    Enum.map(EntityTemplate.types(), &{String.capitalize(&1), &1})
  end

  defp icon_options do
    [
      {"User", "hero-user"},
      {"Users", "hero-users"},
      {"Map Pin", "hero-map-pin"},
      {"Building", "hero-building-office"},
      {"Home", "hero-home"},
      {"Cube", "hero-cube"},
      {"Gift", "hero-gift"},
      {"Key", "hero-key"},
      {"Puzzle", "hero-puzzle-piece"},
      {"Star", "hero-star"},
      {"Heart", "hero-heart"},
      {"Flag", "hero-flag"},
      {"Document", "hero-document-text"},
      {"Folder", "hero-folder"}
    ]
  end

  @impl true
  def mount(%{"project_id" => project_id}, _session, socket) do
    case Projects.authorize(socket.assigns.current_scope, project_id, :view) do
      {:ok, project, membership} ->
        templates = Entities.list_templates(project.id)
        entity_counts = Entities.count_entities_by_template(project.id)
        can_edit = Projects.ProjectMembership.can?(membership.role, :edit_content)

        socket =
          socket
          |> assign(:project, project)
          |> assign(:templates, templates)
          |> assign(:entity_counts, entity_counts)
          |> assign(:can_edit, can_edit)
          |> assign(:form, nil)
          |> assign(:template, nil)

        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("You don't have access to this project."))
         |> redirect(to: ~p"/projects")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    template = %EntityTemplate{}
    changeset = Entities.change_template(template)

    socket
    |> assign(:template, template)
    |> assign(:form, to_form(changeset))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    case Entities.get_template(socket.assigns.project.id, id) do
      nil ->
        socket
        |> put_flash(:error, gettext("Template not found."))
        |> push_patch(to: ~p"/projects/#{socket.assigns.project.id}/templates")

      template ->
        changeset = Entities.change_template(template)

        socket
        |> assign(:template, template)
        |> assign(:form, to_form(changeset))
    end
  end

  defp apply_action(socket, _action, _params) do
    socket
    |> assign(:template, nil)
    |> assign(:form, nil)
  end

  @impl true
  def handle_event("validate", %{"entity_template" => params}, socket) do
    changeset =
      socket.assigns.template
      |> Entities.change_template(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"entity_template" => params}, socket) do
    case socket.assigns.live_action do
      :new -> create_template(socket, params)
      :edit -> update_template(socket, params)
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    template = Entities.get_template!(socket.assigns.project.id, id)

    case Entities.delete_template(template) do
      {:ok, _} ->
        templates = Entities.list_templates(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(:templates, templates)
         |> put_flash(:info, gettext("Template deleted successfully."))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Could not delete template."))}
    end
  end

  def handle_event("create_defaults", _params, socket) do
    case Entities.create_default_templates(socket.assigns.project) do
      {:ok, _templates} ->
        templates = Entities.list_templates(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(:templates, templates)
         |> put_flash(:info, gettext("Default templates created successfully."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not create default templates."))}
    end
  end

  defp create_template(socket, params) do
    case Entities.create_template(socket.assigns.project, params) do
      {:ok, _template} ->
        templates = Entities.list_templates(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(:templates, templates)
         |> put_flash(:info, gettext("Template created successfully."))
         |> push_patch(to: ~p"/projects/#{socket.assigns.project.id}/templates")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp update_template(socket, params) do
    case Entities.update_template(socket.assigns.template, params) do
      {:ok, _template} ->
        templates = Entities.list_templates(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(:templates, templates)
         |> put_flash(:info, gettext("Template updated successfully."))
         |> push_patch(to: ~p"/projects/#{socket.assigns.project.id}/templates")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end
end
