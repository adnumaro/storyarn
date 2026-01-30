defmodule StoryarnWeb.TemplateLive.Index do
  use StoryarnWeb, :live_view
  use StoryarnWeb.LiveHelpers.Authorize

  alias Storyarn.Entities
  alias Storyarn.Entities.EntityTemplate
  alias Storyarn.Projects
  alias StoryarnWeb.TemplateLive.SchemaBuilder

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} workspaces={@workspaces}>
      <%= if @live_action == :schema do %>
        <.schema_view
          template={@template}
          project={@project}
          can_edit={@can_edit}
        />
      <% else %>
        <.index_view
          templates={@templates}
          entity_counts={@entity_counts}
          project={@project}
          can_edit={@can_edit}
          live_action={@live_action}
          form={@form}
        />
      <% end %>
    </Layouts.app>
    """
  end

  attr :templates, :list, required: true
  attr :entity_counts, :map, required: true
  attr :project, :map, required: true
  attr :can_edit, :boolean, required: true
  attr :live_action, :atom, required: true
  attr :form, :any

  defp index_view(assigns) do
    ~H"""
    <div>
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

      <.empty_state :if={@templates == []} icon="hero-document-duplicate">
        {gettext("No templates yet.")}
        <:action :if={@can_edit}>
          <button type="button" class="btn btn-outline" phx-click="create_defaults">
            {gettext("Create Default Templates")}
          </button>
        </:action>
      </.empty_state>

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
    </div>
    """
  end

  attr :template, :map, required: true
  attr :project, :map, required: true
  attr :can_edit, :boolean, required: true

  defp schema_view(assigns) do
    ~H"""
    <div>
      <div class="mb-8">
        <.back navigate={~p"/projects/#{@project.id}/templates"}>
          {gettext("Back to templates")}
        </.back>
      </div>

      <div class="mb-8">
        <div class="flex items-center gap-3 mb-2">
          <.icon name={@template.icon} class="size-8" style={"color: #{@template.color}"} />
          <div>
            <h1 class="text-2xl font-bold">{@template.name}</h1>
            <span class="badge badge-ghost">{@template.type}</span>
          </div>
        </div>
        <p :if={@template.description} class="text-base-content/70">
          {@template.description}
        </p>
      </div>

      <div class="card bg-base-100 border border-base-300 shadow-sm">
        <div class="card-body">
          <.live_component
            module={SchemaBuilder}
            id="schema-builder"
            template={@template}
            can_edit={@can_edit}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :template, :map, required: true
  attr :entity_count, :integer, required: true
  attr :project, :map, required: true
  attr :can_edit, :boolean, required: true

  defp template_card(assigns) do
    field_count = length(assigns.template.schema || [])
    assigns = assign(assigns, :field_count, field_count)

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
          <div class="flex gap-2 text-sm text-base-content/50">
            <span>{ngettext("%{count} entity", "%{count} entities", @entity_count)}</span>
            <span class="text-base-content/30">|</span>
            <span>{ngettext("%{count} field", "%{count} fields", @field_count)}</span>
          </div>
          <div :if={@can_edit} class="flex gap-1">
            <.link
              patch={~p"/projects/#{@project.id}/templates/#{@template.id}/schema"}
              class="btn btn-ghost btn-xs"
              title={gettext("Edit Schema")}
            >
              <.icon name="hero-rectangle-stack" class="size-3" />
            </.link>
            <.link
              patch={~p"/projects/#{@project.id}/templates/#{@template.id}/edit"}
              class="btn btn-ghost btn-xs"
              title={gettext("Edit Template")}
            >
              <.icon name="hero-pencil" class="size-3" />
            </.link>
            <button
              :if={@entity_count == 0}
              type="button"
              class="btn btn-ghost btn-xs text-error"
              title={gettext("Delete Template")}
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
          |> assign(:membership, membership)
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
         |> redirect(to: ~p"/workspaces")}
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

  defp apply_action(socket, :schema, %{"id" => id}) do
    case Entities.get_template(socket.assigns.project.id, id) do
      nil ->
        socket
        |> put_flash(:error, gettext("Template not found."))
        |> push_patch(to: ~p"/projects/#{socket.assigns.project.id}/templates")

      template ->
        socket
        |> assign(:template, template)
        |> assign(:form, nil)
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
    with :ok <- authorize(socket, :edit_content) do
      case socket.assigns.live_action do
        :new -> create_template(socket, params)
        :edit -> update_template(socket, params)
      end
    else
      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    with :ok <- authorize(socket, :edit_content) do
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
    else
      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("create_defaults", _params, socket) do
    with :ok <- authorize(socket, :edit_content) do
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
    else
      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
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

  @impl true
  def handle_info({SchemaBuilder, {:schema_changed, updated_template}}, socket) do
    # Update both the template and the templates list
    templates = Entities.list_templates(socket.assigns.project.id)

    {:noreply,
     socket
     |> assign(:template, updated_template)
     |> assign(:templates, templates)}
  end
end
