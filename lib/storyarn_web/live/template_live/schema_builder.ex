defmodule StoryarnWeb.TemplateLive.SchemaBuilder do
  @moduledoc """
  LiveComponent for visual template schema building.

  Provides a drag-and-drop interface for managing custom fields in entity templates.
  """
  use StoryarnWeb, :live_component

  alias Storyarn.Entities

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h3 class="text-lg font-semibold">{gettext("Schema Fields")}</h3>
          <p class="text-sm text-base-content/70">
            {gettext("Define custom fields for entities using this template. Drag to reorder.")}
          </p>
        </div>
        <button
          type="button"
          class="btn btn-primary btn-sm"
          phx-click="add_field"
          phx-target={@myself}
        >
          <.icon name="hero-plus" class="size-4" />
          {gettext("Add Field")}
        </button>
      </div>

      <div
        :if={@schema == []}
        class="text-center py-8 border border-dashed border-base-300 rounded-lg"
      >
        <.icon name="hero-rectangle-stack" class="size-12 mx-auto text-base-content/30 mb-2" />
        <p class="text-base-content/50">{gettext("No fields yet. Add your first field above.")}</p>
      </div>

      <ul
        :if={@schema != []}
        id="schema-fields"
        phx-hook="SortableList"
        data-group="schema"
        data-handle=".drag-handle"
        class="space-y-2"
        phx-update="replace"
      >
        <li
          :for={field <- @schema}
          data-id={field["name"]}
          class="flex items-center gap-3 p-3 bg-base-200 rounded-lg group sortable-item"
        >
          <button
            type="button"
            class="drag-handle cursor-grab active:cursor-grabbing text-base-content/40 hover:text-base-content"
          >
            <.icon name="hero-bars-3" class="size-5" />
          </button>
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2">
              <span class="font-medium">{field["label"]}</span>
              <span class="badge badge-xs badge-ghost">{field["name"]}</span>
              <span :if={field["required"]} class="badge badge-xs badge-primary">
                {gettext("Required")}
              </span>
            </div>
            <div class="flex items-center gap-2 text-sm text-base-content/60">
              <span class="badge badge-xs">{type_label(field["type"])}</span>
              <span :if={field["description"]} class="truncate">{field["description"]}</span>
            </div>
          </div>
          <div class="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
            <button
              type="button"
              class="btn btn-ghost btn-xs"
              phx-click="edit_field"
              phx-value-name={field["name"]}
              phx-target={@myself}
            >
              <.icon name="hero-pencil" class="size-3" />
            </button>
            <button
              type="button"
              class="btn btn-ghost btn-xs text-error"
              phx-click="delete_field"
              phx-value-name={field["name"]}
              phx-target={@myself}
              data-confirm={gettext("Are you sure you want to delete this field?")}
            >
              <.icon name="hero-trash" class="size-3" />
            </button>
          </div>
        </li>
      </ul>

      <.modal
        :if={@show_field_modal}
        id="field-modal"
        show
        on_cancel={JS.push("close_modal", target: @myself)}
      >
        <.field_form
          form={@field_form}
          editing={@editing_field}
          myself={@myself}
        />
      </.modal>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :editing, :string
  attr :myself, :any, required: true

  defp field_form(assigns) do
    ~H"""
    <div>
      <.header>
        {if @editing, do: gettext("Edit Field"), else: gettext("Add Field")}
      </.header>

      <.form for={@form} id="field-form" phx-submit="save_field" phx-target={@myself}>
        <div class="space-y-4">
          <.input
            field={@form[:label]}
            type="text"
            label={gettext("Label")}
            placeholder={gettext("Display Name")}
            required
          />

          <.input
            field={@form[:name]}
            type="text"
            label={gettext("Field Name")}
            placeholder={gettext("field_name")}
            required
            pattern="^[a-z][a-z0-9_]*$"
            title={
              gettext("Must start with a letter, only lowercase letters, numbers, and underscores")
            }
          />

          <.input
            field={@form[:type]}
            type="select"
            label={gettext("Type")}
            options={type_options()}
            required
          />

          <.input
            field={@form[:required]}
            type="checkbox"
            label={gettext("Required")}
          />

          <.input
            field={@form[:default]}
            type="text"
            label={gettext("Default Value")}
            placeholder={gettext("(optional)")}
          />

          <.input
            field={@form[:description]}
            type="textarea"
            label={gettext("Description")}
            rows={2}
            placeholder={gettext("Help text for users filling in this field")}
          />

          <div id="options-container" phx-update="ignore">
            <.input
              field={@form[:options_text]}
              type="textarea"
              label={gettext("Options (for Select type)")}
              rows={3}
              placeholder={gettext("One option per line")}
            />
            <p class="text-xs text-base-content/50 mt-1">
              {gettext("Enter each option on a new line. Only used for Select type.")}
            </p>
          </div>
        </div>

        <div class="modal-action">
          <button type="button" class="btn btn-ghost" phx-click="close_modal" phx-target={@myself}>
            {gettext("Cancel")}
          </button>
          <.button variant="primary" phx-disable-with={gettext("Saving...")}>
            {if @editing, do: gettext("Update Field"), else: gettext("Add Field")}
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  defp type_options do
    [
      {gettext("Text (single line)"), "string"},
      {gettext("Text (multiline)"), "text"},
      {gettext("Number"), "integer"},
      {gettext("Yes/No"), "boolean"},
      {gettext("Dropdown"), "select"},
      {gettext("Asset Reference"), "asset_reference"}
    ]
  end

  defp type_label(type) do
    case type do
      "string" -> gettext("Text")
      "text" -> gettext("Multiline")
      "integer" -> gettext("Number")
      "boolean" -> gettext("Yes/No")
      "select" -> gettext("Dropdown")
      "asset_reference" -> gettext("Asset")
      _ -> type
    end
  end

  @impl true
  def update(%{template: template} = assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign(:schema, template.schema || [])
      |> assign(:show_field_modal, false)
      |> assign(:editing_field, nil)
      |> assign(:field_form, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("add_field", _params, socket) do
    form = build_field_form(%{})

    socket =
      socket
      |> assign(:show_field_modal, true)
      |> assign(:editing_field, nil)
      |> assign(:field_form, form)

    {:noreply, socket}
  end

  def handle_event("edit_field", %{"name" => name}, socket) do
    field = Enum.find(socket.assigns.schema, fn f -> f["name"] == name end)

    if field do
      # Convert options list to text for textarea
      field_with_options_text =
        Map.put(field, "options_text", options_to_text(field["options"]))

      form = build_field_form(field_with_options_text)

      socket =
        socket
        |> assign(:show_field_modal, true)
        |> assign(:editing_field, name)
        |> assign(:field_form, form)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_modal", _params, socket) do
    socket =
      socket
      |> assign(:show_field_modal, false)
      |> assign(:editing_field, nil)
      |> assign(:field_form, nil)

    {:noreply, socket}
  end

  def handle_event("save_field", %{"field" => params}, socket) do
    # Convert options_text to options list
    field_attrs = params_to_field_attrs(params)

    result =
      if socket.assigns.editing_field do
        Entities.update_schema_field(
          socket.assigns.template,
          socket.assigns.editing_field,
          field_attrs
        )
      else
        Entities.add_schema_field(socket.assigns.template, field_attrs)
      end

    case result do
      {:ok, updated_template} ->
        notify_parent({:schema_changed, updated_template})

        socket =
          socket
          |> assign(:template, updated_template)
          |> assign(:schema, updated_template.schema)
          |> assign(:show_field_modal, false)
          |> assign(:editing_field, nil)
          |> assign(:field_form, nil)

        {:noreply, socket}

      {:error, reason} when is_binary(reason) ->
        {:noreply, put_flash(socket, :error, reason)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Could not save field."))}
    end
  end

  def handle_event("delete_field", %{"name" => name}, socket) do
    case Entities.remove_schema_field(socket.assigns.template, name) do
      {:ok, updated_template} ->
        notify_parent({:schema_changed, updated_template})

        socket =
          socket
          |> assign(:template, updated_template)
          |> assign(:schema, updated_template.schema)

        {:noreply, socket}

      {:error, reason} when is_binary(reason) ->
        {:noreply, put_flash(socket, :error, reason)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not delete field."))}
    end
  end

  def handle_event("reorder", %{"ids" => ids}, socket) do
    case Entities.reorder_schema_fields(socket.assigns.template, ids) do
      {:ok, updated_template} ->
        notify_parent({:schema_changed, updated_template})

        socket =
          socket
          |> assign(:template, updated_template)
          |> assign(:schema, updated_template.schema)

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not reorder fields."))}
    end
  end

  defp build_field_form(attrs) do
    data = %{
      name: Map.get(attrs, "name", ""),
      label: Map.get(attrs, "label", ""),
      type: Map.get(attrs, "type", "string"),
      required: Map.get(attrs, "required", false),
      default: Map.get(attrs, "default", ""),
      description: Map.get(attrs, "description", ""),
      options_text: Map.get(attrs, "options_text", "")
    }

    types = %{
      name: :string,
      label: :string,
      type: :string,
      required: :boolean,
      default: :string,
      description: :string,
      options_text: :string
    }

    changeset =
      {data, types}
      |> Ecto.Changeset.cast(%{}, Map.keys(types))

    to_form(changeset, as: :field)
  end

  defp params_to_field_attrs(params) do
    attrs = %{
      "name" => params["name"],
      "label" => params["label"],
      "type" => params["type"],
      "required" => params["required"] == "true"
    }

    attrs =
      if params["default"] != "" do
        Map.put(attrs, "default", params["default"])
      else
        attrs
      end

    attrs =
      if params["description"] != "" do
        Map.put(attrs, "description", params["description"])
      else
        attrs
      end

    # Convert options_text to options list for select type
    if params["type"] == "select" && params["options_text"] != "" do
      options =
        params["options_text"]
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      Map.put(attrs, "options", options)
    else
      attrs
    end
  end

  defp options_to_text(nil), do: ""
  defp options_to_text(options) when is_list(options), do: Enum.join(options, "\n")

  defp notify_parent(msg) do
    send(self(), {__MODULE__, msg})
  end
end
