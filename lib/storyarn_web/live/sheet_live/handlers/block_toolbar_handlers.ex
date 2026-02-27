defmodule StoryarnWeb.SheetLive.Handlers.BlockToolbarHandlers do
  @moduledoc """
  Handles toolbar action events for the ContentTab LiveComponent.

  Covers: duplicate_block, toolbar_toggle_constant, move_block_up, move_block_down,
  save_config_field, add/remove/update_select_option, change_block_scope (by id),
  toggle_required (by id).

  The `helpers` map must contain:
    - `:reload_blocks`        - fn(socket) -> socket
    - `:maybe_create_version` - fn(socket) -> any
    - `:notify_parent`        - fn(socket, status) -> any
    - `:push_undo`            - fn(action) -> any (not required for all handlers)
  """

  import Phoenix.LiveView, only: [put_flash: 3]

  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Sheets
  alias StoryarnWeb.SheetLive.Handlers.InheritanceHandlers
  alias StoryarnWeb.SheetLive.Handlers.UndoRedoHandlers
  alias StoryarnWeb.SheetLive.Helpers.ContentTabHelpers

  # ---------------------------------------------------------------------------
  # duplicate_block
  # ---------------------------------------------------------------------------

  @doc "Duplicates a block, placing the copy after the original."
  def handle_duplicate_block(block_id, socket, helpers) do
    block_id = ContentTabHelpers.to_integer(block_id)
    project_id = socket.assigns.project.id

    case Sheets.get_block_in_project(block_id, project_id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Block not found."))}

      block ->
        case Sheets.duplicate_block(block) do
          {:ok, new_block} ->
            helpers.push_undo.({:create_block, UndoRedoHandlers.block_to_snapshot(new_block)})
            helpers.maybe_create_version.(socket)
            helpers.notify_parent.(socket, :saved)
            {:noreply, helpers.reload_blocks.(socket)}

          {:error, _} ->
            {:noreply,
             put_flash(socket, :error, dgettext("sheets", "Could not duplicate block."))}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # toolbar_toggle_constant
  # ---------------------------------------------------------------------------

  @doc "Toggles the is_constant flag on a block from the toolbar."
  def handle_toggle_constant(block_id, socket, helpers) do
    block_id = ContentTabHelpers.to_integer(block_id)
    project_id = socket.assigns.project.id

    case Sheets.get_block_in_project(block_id, project_id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Block not found."))}

      block ->
        prev_value = block.is_constant
        new_value = !prev_value

        case Sheets.update_block(block, %{is_constant: new_value}) do
          {:ok, _updated} ->
            helpers.push_undo.({:toggle_constant, block.id, prev_value, new_value})
            helpers.maybe_create_version.(socket)
            helpers.notify_parent.(socket, :saved)
            {:noreply, helpers.reload_blocks.(socket)}

          {:error, _} ->
            {:noreply,
             put_flash(socket, :error, dgettext("sheets", "Could not toggle constant."))}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # move_block_up
  # ---------------------------------------------------------------------------

  @doc "Moves a block up by swapping with the previous block."
  def handle_move_block_up(block_id, socket, helpers) do
    block_id = ContentTabHelpers.to_integer(block_id)
    sheet_id = socket.assigns.sheet.id
    prev_order = Sheets.list_blocks(sheet_id) |> Enum.map(& &1.id)

    case Sheets.move_block_up(block_id, sheet_id) do
      {:ok, :moved} ->
        new_order = Sheets.list_blocks(sheet_id) |> Enum.map(& &1.id)
        helpers.push_undo.({:reorder_blocks, prev_order, new_order})
        helpers.maybe_create_version.(socket)
        helpers.notify_parent.(socket, :saved)
        {:noreply, helpers.reload_blocks.(socket)}

      {:ok, :already_first} ->
        {:noreply, socket}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Block not found."))}
    end
  end

  # ---------------------------------------------------------------------------
  # move_block_down
  # ---------------------------------------------------------------------------

  @doc "Moves a block down by swapping with the next block."
  def handle_move_block_down(block_id, socket, helpers) do
    block_id = ContentTabHelpers.to_integer(block_id)
    sheet_id = socket.assigns.sheet.id
    prev_order = Sheets.list_blocks(sheet_id) |> Enum.map(& &1.id)

    case Sheets.move_block_down(block_id, sheet_id) do
      {:ok, :moved} ->
        new_order = Sheets.list_blocks(sheet_id) |> Enum.map(& &1.id)
        helpers.push_undo.({:reorder_blocks, prev_order, new_order})
        helpers.maybe_create_version.(socket)
        helpers.notify_parent.(socket, :saved)
        {:noreply, helpers.reload_blocks.(socket)}

      {:ok, :already_last} ->
        {:noreply, socket}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Block not found."))}
    end
  end

  # ---------------------------------------------------------------------------
  # save_config_field (popover blur saves)
  # ---------------------------------------------------------------------------

  @doc "Saves a single config field from the popover (blur event)."
  def handle_save_config_field(block_id, field, value, socket, helpers) do
    block_id = ContentTabHelpers.to_integer(block_id)
    project_id = socket.assigns.project.id

    case Sheets.get_block_in_project(block_id, project_id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Block not found."))}

      block ->
        normalized = normalize_config_value(field, value)
        new_config = Map.put(block.config || %{}, field, normalized)
        prev_config = block.config

        case Sheets.update_block_config(block, new_config) do
          {:ok, _updated} ->
            helpers.push_undo.({:update_block_config, block.id, prev_config, new_config})
            helpers.maybe_create_version.(socket)
            helpers.notify_parent.(socket, :saved)
            {:noreply, helpers.reload_blocks.(socket)}

          {:error, _} ->
            {:noreply,
             put_flash(socket, :error, dgettext("sheets", "Could not save configuration."))}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Select option management (popover)
  # ---------------------------------------------------------------------------

  @doc "Adds a new option to a select/multi_select block."
  def handle_add_option(block_id, socket, helpers) do
    block_id = ContentTabHelpers.to_integer(block_id)
    project_id = socket.assigns.project.id

    case Sheets.get_block_in_project(block_id, project_id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Block not found."))}

      block ->
        options = get_in(block.config, ["options"]) || []
        new_option = %{"key" => "option_#{length(options) + 1}", "value" => ""}
        prev_config = block.config
        new_config = Map.put(block.config || %{}, "options", options ++ [new_option])

        case Sheets.update_block_config(block, new_config) do
          {:ok, _updated} ->
            helpers.push_undo.({:update_block_config, block.id, prev_config, new_config})
            helpers.maybe_create_version.(socket)
            helpers.notify_parent.(socket, :saved)
            {:noreply, helpers.reload_blocks.(socket)}

          {:error, _} ->
            {:noreply,
             put_flash(socket, :error, dgettext("sheets", "Could not save configuration."))}
        end
    end
  end

  @doc "Removes a select option at the given index."
  def handle_remove_option(block_id, index, socket, helpers) do
    block_id = ContentTabHelpers.to_integer(block_id)
    index = ContentTabHelpers.to_integer(index)
    project_id = socket.assigns.project.id

    case Sheets.get_block_in_project(block_id, project_id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Block not found."))}

      block ->
        options = get_in(block.config, ["options"]) || []
        prev_config = block.config
        new_config = Map.put(block.config || %{}, "options", List.delete_at(options, index))

        case Sheets.update_block_config(block, new_config) do
          {:ok, _updated} ->
            helpers.push_undo.({:update_block_config, block.id, prev_config, new_config})
            helpers.maybe_create_version.(socket)
            helpers.notify_parent.(socket, :saved)
            {:noreply, helpers.reload_blocks.(socket)}

          {:error, _} ->
            {:noreply,
             put_flash(socket, :error, dgettext("sheets", "Could not save configuration."))}
        end
    end
  end

  @doc "Updates a single field (key or value) of a select option at the given index."
  def handle_update_option(block_id, index, key_field, value, socket, helpers) do
    block_id = ContentTabHelpers.to_integer(block_id)
    index = ContentTabHelpers.to_integer(index)
    project_id = socket.assigns.project.id

    case Sheets.get_block_in_project(block_id, project_id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Block not found."))}

      block ->
        options = get_in(block.config, ["options"]) || []
        prev_config = block.config

        new_options =
          List.update_at(options, index, fn opt ->
            Map.put(opt || %{}, key_field, value)
          end)

        new_config = Map.put(block.config || %{}, "options", new_options)

        case Sheets.update_block_config(block, new_config) do
          {:ok, _updated} ->
            helpers.push_undo.({:update_block_config, block.id, prev_config, new_config})
            helpers.maybe_create_version.(socket)
            helpers.notify_parent.(socket, :saved)
            {:noreply, helpers.reload_blocks.(socket)}

          {:error, _} ->
            {:noreply,
             put_flash(socket, :error, dgettext("sheets", "Could not save configuration."))}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # toggle_allowed_type (reference block)
  # ---------------------------------------------------------------------------

  @doc "Toggles an allowed reference type. Ensures at least one type remains."
  def handle_toggle_allowed_type(block_id, type, socket, helpers) do
    block_id = ContentTabHelpers.to_integer(block_id)
    project_id = socket.assigns.project.id

    case Sheets.get_block_in_project(block_id, project_id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Block not found."))}

      block ->
        current = get_in(block.config, ["allowed_types"]) || ["sheet", "flow"]

        new_types =
          if type in current,
            do: List.delete(current, type),
            else: current ++ [type]

        # Ensure at least one type remains
        new_types = if new_types == [], do: current, else: new_types

        prev_config = block.config
        new_config = Map.put(block.config || %{}, "allowed_types", new_types)

        case Sheets.update_block_config(block, new_config) do
          {:ok, _updated} ->
            helpers.push_undo.({:update_block_config, block.id, prev_config, new_config})
            helpers.maybe_create_version.(socket)
            helpers.notify_parent.(socket, :saved)
            {:noreply, helpers.reload_blocks.(socket)}

          {:error, _} ->
            {:noreply,
             put_flash(socket, :error, dgettext("sheets", "Could not save configuration."))}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # change_block_scope (by block id, from popover)
  # ---------------------------------------------------------------------------

  @doc "Changes block scope by looking up the block by id. Delegates to InheritanceHandlers."
  def handle_change_scope(block_id, scope, socket, helpers) do
    block_id = ContentTabHelpers.to_integer(block_id)
    project_id = socket.assigns.project.id

    case Sheets.get_block_in_project(block_id, project_id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Block not found."))}

      block ->
        InheritanceHandlers.handle_change_scope(block, scope, socket, helpers)
    end
  end

  # ---------------------------------------------------------------------------
  # toggle_required (by block id, from popover)
  # ---------------------------------------------------------------------------

  @doc "Toggles required flag by looking up the block by id. Delegates to InheritanceHandlers."
  def handle_toggle_required_by_id(block_id, socket, helpers) do
    block_id = ContentTabHelpers.to_integer(block_id)
    project_id = socket.assigns.project.id

    case Sheets.get_block_in_project(block_id, project_id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Block not found."))}

      block ->
        InheritanceHandlers.handle_toggle_required(block, socket, helpers)
    end
  end

  # ---------------------------------------------------------------------------
  # update_variable_name
  # ---------------------------------------------------------------------------

  @doc "Updates a block's variable_name from the toolbar inline input."
  def handle_update_variable_name(block_id, variable_name, socket, helpers) do
    block_id = ContentTabHelpers.to_integer(block_id)
    project_id = socket.assigns.project.id

    case Sheets.get_block_in_project(block_id, project_id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Block not found."))}

      block ->
        prev_name = block.variable_name

        case Sheets.update_variable_name(block, variable_name) do
          {:ok, updated} ->
            helpers.push_undo.(
              {:update_variable_name, block.id, prev_name, updated.variable_name}
            )

            helpers.maybe_create_version.(socket)
            helpers.notify_parent.(socket, :saved)
            {:noreply, helpers.reload_blocks.(socket)}

          {:error, _} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               dgettext("sheets", "Could not update variable name.")
             )}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp normalize_config_value("max_length", ""), do: nil

  defp normalize_config_value("max_length", value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp normalize_config_value("max_options", ""), do: nil

  defp normalize_config_value("max_options", value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp normalize_config_value(field, "") when field in ~w(min_date max_date), do: nil

  defp normalize_config_value(field, "") when field in ~w(min max step), do: nil

  defp normalize_config_value(field, value) when field in ~w(min max step) and is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> nil
    end
  end

  defp normalize_config_value(_field, value), do: value
end
