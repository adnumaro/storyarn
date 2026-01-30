defmodule StoryarnWeb.EntityLive.Form do
  @moduledoc """
  Form component for creating and editing entities.

  Renders a dynamic form based on the entity template schema.
  """
  use StoryarnWeb, :live_component

  alias Storyarn.Entities
  alias Storyarn.Entities.Entity

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle :if={@template}>
          <span
            class="inline-flex items-center gap-1"
            style={"color: #{@template.color}"}
          >
            <.icon name={@template.icon} class="size-4" />
            {@template.name}
          </span>
        </:subtitle>
      </.header>

      <.form
        for={@form}
        id="entity-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:display_name]}
          type="text"
          label={gettext("Display Name")}
          placeholder={gettext("My Character")}
          required
        />
        <.input
          field={@form[:technical_name]}
          type="text"
          label={gettext("Technical Name")}
          placeholder={gettext("my_character")}
        />
        <.input
          field={@form[:description]}
          type="textarea"
          label={gettext("Description")}
          rows={3}
        />
        <.input
          field={@form[:color]}
          type="color"
          label={gettext("Color")}
        />

        <.render_custom_fields form={@form} template={@template} />

        <div class="modal-action">
          <.link patch={@navigate} class="btn btn-ghost">
            {gettext("Cancel")}
          </.link>
          <.button variant="primary" phx-disable-with={gettext("Saving...")}>
            {if @action == :new, do: gettext("Create Entity"), else: gettext("Save Changes")}
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :template, :any, required: true

  defp render_custom_fields(assigns) do
    # Schema is now an array of field definitions
    schema = assigns.template && assigns.template.schema
    has_fields = is_list(schema) && schema != []
    assigns = assign(assigns, :has_fields, has_fields)

    ~H"""
    <div :if={@has_fields} class="mt-4 pt-4 border-t border-base-300">
      <h3 class="text-sm font-medium mb-3">{gettext("Custom Fields")}</h3>
      <div :for={field <- @template.schema || []}>
        <.render_custom_field
          form={@form}
          field={field}
        />
      </div>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :field, :map, required: true

  defp render_custom_field(assigns) do
    field = assigns.field
    field_name = Map.get(field, "name")
    field_type = Map.get(field, "type", "string")
    label = Map.get(field, "label", field_name)
    required = Map.get(field, "required", false)
    description = Map.get(field, "description")
    default = Map.get(field, "default", "")
    options = Map.get(field, "options", [])

    assigns =
      assigns
      |> assign(:field_name, field_name)
      |> assign(:field_type, field_type)
      |> assign(:label, label)
      |> assign(:required, required)
      |> assign(:description, description)
      |> assign(:default, default)
      |> assign(:options, options)

    ~H"""
    <div class="mb-2">
      <%= case @field_type do %>
        <% "boolean" -> %>
          <.input
            type="checkbox"
            name={"entity[data][#{@field_name}]"}
            label={@label}
            value={get_data_value(@form, @field_name, @default)}
            checked={get_data_value(@form, @field_name, @default) == "true"}
            required={@required}
          />
        <% "integer" -> %>
          <.input
            type="number"
            name={"entity[data][#{@field_name}]"}
            label={@label}
            value={get_data_value(@form, @field_name, @default)}
            required={@required}
          />
        <% "text" -> %>
          <.input
            type="textarea"
            name={"entity[data][#{@field_name}]"}
            label={@label}
            value={get_data_value(@form, @field_name, @default)}
            rows={3}
            required={@required}
          />
        <% "select" -> %>
          <.input
            type="select"
            name={"entity[data][#{@field_name}]"}
            label={@label}
            value={get_data_value(@form, @field_name, @default)}
            options={Enum.map(@options, &{&1, &1})}
            prompt={gettext("Select an option")}
            required={@required}
          />
        <% "asset_reference" -> %>
          <div class="form-control">
            <label class="label">
              <span class="label-text">{@label}</span>
              <span :if={@required} class="label-text-alt text-error">*</span>
            </label>
            <div class="input input-bordered flex items-center justify-center text-base-content/50 h-20">
              <.icon name="hero-photo" class="size-6 mr-2" />
              {gettext("Asset upload coming soon")}
            </div>
          </div>
        <% _ -> %>
          <.input
            type="text"
            name={"entity[data][#{@field_name}]"}
            label={@label}
            value={get_data_value(@form, @field_name, @default)}
            required={@required}
          />
      <% end %>
      <p :if={@description} class="text-xs text-base-content/50 mt-1">{@description}</p>
    </div>
    """
  end

  defp get_data_value(form, field_name, default) do
    data = Ecto.Changeset.get_field(form.source, :data) || %{}
    Map.get(data, field_name, default)
  end

  @impl true
  def update(assigns, socket) do
    entity = Map.get(assigns, :entity, %Entity{})
    changeset = Entities.change_entity(entity)

    # Default can_edit to true for backwards compatibility, but parent should pass it
    can_edit = Map.get(assigns, :can_edit, true)

    socket =
      socket
      |> assign(assigns)
      |> assign(:entity, entity)
      |> assign(:can_edit, can_edit)
      |> assign(:form, to_form(changeset))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"entity" => entity_params}, socket) do
    entity_params = merge_data_params(entity_params)

    changeset =
      socket.assigns.entity
      |> Entities.change_entity(entity_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"entity" => entity_params}, socket) do
    if socket.assigns.can_edit do
      entity_params = merge_data_params(entity_params)

      case socket.assigns.action do
        :new -> create_entity(socket, entity_params)
        :edit -> update_entity(socket, entity_params)
      end
    else
      {:noreply,
       socket
       |> Phoenix.LiveView.put_flash(:error, gettext("You don't have permission to perform this action."))}
    end
  end

  defp merge_data_params(params) do
    data = Map.get(params, "data", %{})
    Map.put(params, "data", data)
  end

  defp create_entity(socket, entity_params) do
    case Entities.create_entity(socket.assigns.project, socket.assigns.template, entity_params) do
      {:ok, entity} ->
        notify_parent({:saved, entity})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp update_entity(socket, entity_params) do
    case Entities.update_entity(socket.assigns.entity, entity_params) do
      {:ok, entity} ->
        notify_parent({:saved, entity})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
