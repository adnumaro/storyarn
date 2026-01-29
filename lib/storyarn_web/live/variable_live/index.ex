defmodule StoryarnWeb.VariableLive.Index do
  use StoryarnWeb, :live_view

  alias Storyarn.Entities
  alias Storyarn.Entities.Variable
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
          {gettext("Variables")}
          <:subtitle>
            {gettext("Manage project-wide state for use in flows and conditions")}
          </:subtitle>
          <:actions :if={@can_edit}>
            <.link patch={~p"/projects/#{@project.id}/variables/new"} class="btn btn-primary">
              <.icon name="hero-plus" class="size-4 mr-2" />
              {gettext("New Variable")}
            </.link>
          </:actions>
        </.header>
      </div>

      <div :if={@variables == []} class="text-center py-12">
        <.icon name="hero-variable" class="size-12 mx-auto text-base-content/30 mb-4" />
        <p class="text-base-content/70">
          {gettext("No variables yet. Create your first variable to track game state.")}
        </p>
      </div>

      <div :if={@variables != []}>
        <div :for={{category, vars} <- @grouped_variables} class="mb-6">
          <h3
            :if={category}
            class="text-sm font-medium text-base-content/70 mb-2 flex items-center gap-2"
          >
            <.icon name="hero-folder" class="size-4" />
            {category}
          </h3>
          <h3 :if={!category} class="text-sm font-medium text-base-content/70 mb-2">
            {gettext("Uncategorized")}
          </h3>

          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Name")}</th>
                  <th>{gettext("Type")}</th>
                  <th>{gettext("Default Value")}</th>
                  <th>{gettext("Description")}</th>
                  <th :if={@can_edit}></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={variable <- vars}>
                  <td class="font-mono text-sm">{variable.name}</td>
                  <td>
                    <span class={["badge badge-sm", type_badge_class(variable.type)]}>
                      {variable.type}
                    </span>
                  </td>
                  <td class="font-mono text-sm">{variable.default_value}</td>
                  <td class="text-sm text-base-content/70 max-w-xs truncate">
                    {variable.description || "-"}
                  </td>
                  <td :if={@can_edit} class="text-right">
                    <.link
                      patch={~p"/projects/#{@project.id}/variables/#{variable.id}/edit"}
                      class="btn btn-ghost btn-xs"
                    >
                      <.icon name="hero-pencil" class="size-3" />
                    </.link>
                    <button
                      type="button"
                      class="btn btn-ghost btn-xs text-error"
                      phx-click="delete"
                      phx-value-id={variable.id}
                      data-confirm={gettext("Are you sure you want to delete this variable?")}
                    >
                      <.icon name="hero-trash" class="size-3" />
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <.modal
        :if={@live_action in [:new, :edit]}
        id="variable-modal"
        show
        on_cancel={JS.patch(~p"/projects/#{@project.id}/variables")}
      >
        <.variable_form
          form={@form}
          title={if @live_action == :new, do: gettext("New Variable"), else: gettext("Edit Variable")}
          action={@live_action}
          project={@project}
          categories={@categories}
        />
      </.modal>
    </Layouts.app>
    """
  end

  defp type_badge_class("boolean"), do: "badge-primary"
  defp type_badge_class("integer"), do: "badge-secondary"
  defp type_badge_class("float"), do: "badge-accent"
  defp type_badge_class("string"), do: "badge-ghost"
  defp type_badge_class(_), do: "badge-ghost"

  attr :form, :any, required: true
  attr :title, :string, required: true
  attr :action, :atom, required: true
  attr :project, :map, required: true
  attr :categories, :list, required: true

  defp variable_form(assigns) do
    ~H"""
    <div>
      <.header>{@title}</.header>

      <.form
        for={@form}
        id="variable-form"
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:name]}
          type="text"
          label={gettext("Name")}
          placeholder={gettext("player_health")}
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
          field={@form[:default_value]}
          type="text"
          label={gettext("Default Value")}
          placeholder={default_placeholder(@form)}
        />
        <.input
          field={@form[:category]}
          type="text"
          label={gettext("Category")}
          placeholder={gettext("player")}
          list="categories"
        />
        <datalist id="categories">
          <option :for={cat <- @categories} value={cat} />
        </datalist>
        <.input
          field={@form[:description]}
          type="textarea"
          label={gettext("Description")}
          rows={2}
        />

        <div class="modal-action">
          <.link patch={~p"/projects/#{@project.id}/variables"} class="btn btn-ghost">
            {gettext("Cancel")}
          </.link>
          <.button variant="primary" phx-disable-with={gettext("Saving...")}>
            {if @action == :new, do: gettext("Create Variable"), else: gettext("Save Changes")}
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  defp type_options do
    Enum.map(Variable.types(), &{String.capitalize(&1), &1})
  end

  defp default_placeholder(form) do
    type = Ecto.Changeset.get_field(form.source, :type) || "string"

    case type do
      "boolean" -> "true or false"
      "integer" -> "0"
      "float" -> "0.0"
      "string" -> "text value"
      _ -> ""
    end
  end

  @impl true
  def mount(%{"project_id" => project_id}, _session, socket) do
    case Projects.authorize(socket.assigns.current_scope, project_id, :view) do
      {:ok, project, membership} ->
        variables = Entities.list_variables(project.id)
        categories = Entities.list_variable_categories(project.id)
        can_edit = Projects.ProjectMembership.can?(membership.role, :edit_content)

        socket =
          socket
          |> assign(:project, project)
          |> assign(:variables, variables)
          |> assign(:grouped_variables, group_by_category(variables))
          |> assign(:categories, categories)
          |> assign(:can_edit, can_edit)
          |> assign(:form, nil)
          |> assign(:variable, nil)

        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("You don't have access to this project."))
         |> redirect(to: ~p"/projects")}
    end
  end

  defp group_by_category(variables) do
    variables
    |> Enum.group_by(& &1.category)
    |> Enum.sort_by(fn {cat, _} -> cat || "zzz" end)
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    variable = %Variable{}
    changeset = Entities.change_variable(variable)

    socket
    |> assign(:variable, variable)
    |> assign(:form, to_form(changeset))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    case Entities.get_variable(socket.assigns.project.id, id) do
      nil ->
        socket
        |> put_flash(:error, gettext("Variable not found."))
        |> push_patch(to: ~p"/projects/#{socket.assigns.project.id}/variables")

      variable ->
        changeset = Entities.change_variable(variable)

        socket
        |> assign(:variable, variable)
        |> assign(:form, to_form(changeset))
    end
  end

  defp apply_action(socket, _action, _params) do
    socket
    |> assign(:variable, nil)
    |> assign(:form, nil)
  end

  @impl true
  def handle_event("validate", %{"variable" => params}, socket) do
    changeset =
      socket.assigns.variable
      |> Entities.change_variable(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"variable" => params}, socket) do
    case socket.assigns.live_action do
      :new -> create_variable(socket, params)
      :edit -> update_variable(socket, params)
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    variable = Entities.get_variable!(socket.assigns.project.id, id)

    case Entities.delete_variable(variable) do
      {:ok, _} ->
        variables = Entities.list_variables(socket.assigns.project.id)
        categories = Entities.list_variable_categories(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(:variables, variables)
         |> assign(:grouped_variables, group_by_category(variables))
         |> assign(:categories, categories)
         |> put_flash(:info, gettext("Variable deleted successfully."))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Could not delete variable."))}
    end
  end

  defp create_variable(socket, params) do
    case Entities.create_variable(socket.assigns.project, params) do
      {:ok, _variable} ->
        variables = Entities.list_variables(socket.assigns.project.id)
        categories = Entities.list_variable_categories(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(:variables, variables)
         |> assign(:grouped_variables, group_by_category(variables))
         |> assign(:categories, categories)
         |> put_flash(:info, gettext("Variable created successfully."))
         |> push_patch(to: ~p"/projects/#{socket.assigns.project.id}/variables")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp update_variable(socket, params) do
    case Entities.update_variable(socket.assigns.variable, params) do
      {:ok, _variable} ->
        variables = Entities.list_variables(socket.assigns.project.id)
        categories = Entities.list_variable_categories(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(:variables, variables)
         |> assign(:grouped_variables, group_by_category(variables))
         |> assign(:categories, categories)
         |> put_flash(:info, gettext("Variable updated successfully."))
         |> push_patch(to: ~p"/projects/#{socket.assigns.project.id}/variables")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end
end
