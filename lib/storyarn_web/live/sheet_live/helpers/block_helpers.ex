defmodule StoryarnWeb.SheetLive.Helpers.BlockHelpers do
  @moduledoc """
  Block operation helpers for the sheet editor.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]
  import StoryarnWeb.Helpers.SaveStatusTimer

  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Sheets

  @doc """
  Adds a new block to the sheet.
  Returns {:noreply, socket} tuple.
  """
  @spec add_block(Phoenix.LiveView.Socket.t(), String.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def add_block(socket, type) do
    case Sheets.create_block(socket.assigns.sheet, %{type: type}) do
      {:ok, _block} ->
        blocks = Sheets.list_blocks(socket.assigns.sheet.id)

        # Create version for significant change (block added)
        user_id = socket.assigns.current_scope.user.id
        Sheets.maybe_create_version(socket.assigns.sheet, user_id)

        {:noreply,
         socket
         |> assign(:blocks, blocks)
         |> assign(:show_block_menu, false)}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("sheets", "Could not add block."))
         |> assign(:show_block_menu, false)}
    end
  end

  @doc """
  Updates a block's value.
  Returns {:noreply, socket} tuple.
  """
  @spec update_block_value(Phoenix.LiveView.Socket.t(), any(), any()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def update_block_value(socket, block_id, value) do
    block = Sheets.get_block_in_project!(block_id, socket.assigns.project.id)

    case Sheets.update_block_value(block, %{"content" => value}) do
      {:ok, _block} ->
        blocks = Sheets.list_blocks(socket.assigns.sheet.id)

        {:noreply,
         socket
         |> assign(:blocks, blocks)
         |> mark_saved()}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @doc """
  Deletes a block.
  Returns {:noreply, socket} tuple.
  """
  @spec delete_block(Phoenix.LiveView.Socket.t(), any()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def delete_block(socket, block_id) do
    block = Sheets.get_block_in_project!(block_id, socket.assigns.project.id)

    case Sheets.delete_block(block) do
      {:ok, _} ->
        blocks = Sheets.list_blocks(socket.assigns.sheet.id)

        # Create version for significant change (block deleted)
        user_id = socket.assigns.current_scope.user.id
        Sheets.maybe_create_version(socket.assigns.sheet, user_id)

        {:noreply, assign(socket, :blocks, blocks)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not delete block."))}
    end
  end

  @doc """
  Reorders blocks.
  Returns {:noreply, socket} tuple.
  """
  @spec reorder_blocks(Phoenix.LiveView.Socket.t(), list()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def reorder_blocks(socket, ids) do
    case Sheets.reorder_blocks(socket.assigns.sheet.id, ids) do
      {:ok, blocks} ->
        {:noreply, assign(socket, :blocks, blocks)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not reorder blocks."))}
    end
  end

  @doc """
  Toggles a multi-select option.
  Returns {:noreply, socket} tuple.
  """
  @spec toggle_multi_select(Phoenix.LiveView.Socket.t(), any(), String.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def toggle_multi_select(socket, block_id, key) do
    block = Sheets.get_block_in_project!(block_id, socket.assigns.project.id)
    current = get_in(block.value, ["content"]) || []

    new_content =
      if key in current do
        List.delete(current, key)
      else
        [key | current]
      end

    case Sheets.update_block_value(block, %{"content" => new_content}) do
      {:ok, _block} ->
        blocks = Sheets.list_blocks(socket.assigns.sheet.id)

        {:noreply,
         socket
         |> assign(:blocks, blocks)
         |> mark_saved()}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @doc """
  Handles multi-select keydown (Enter to add new option).
  Returns {:noreply, socket} tuple.
  """
  @spec handle_multi_select_enter(Phoenix.LiveView.Socket.t(), any(), String.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_multi_select_enter(socket, block_id, value) do
    value = String.trim(value)

    if value == "" do
      {:noreply, socket}
    else
      add_multi_select_option(socket, block_id, value)
    end
  end

  @doc """
  Updates rich text content.
  Returns {:noreply, socket} tuple.
  """
  @spec update_rich_text(Phoenix.LiveView.Socket.t(), any(), String.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def update_rich_text(socket, block_id, content) do
    block = Sheets.get_block_in_project!(block_id, socket.assigns.project.id)

    case Sheets.update_block_value(block, %{"content" => content}) do
      {:ok, _block} ->
        # Don't reload blocks to avoid disrupting the editor
        {:noreply, mark_saved(socket)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @doc """
  Sets a boolean block to a specific value.
  Used by both two-state and tri-state modes.
  Returns {:noreply, socket} tuple.
  """
  @spec set_boolean_block(Phoenix.LiveView.Socket.t(), any(), String.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def set_boolean_block(socket, block_id, value_string) do
    block = Sheets.get_block_in_project!(block_id, socket.assigns.project.id)

    new_value =
      case value_string do
        "true" -> true
        "false" -> false
        "null" -> nil
        _ -> nil
      end

    case Sheets.update_block_value(block, %{"content" => new_value}) do
      {:ok, _block} ->
        blocks = Sheets.list_blocks(socket.assigns.sheet.id)

        {:noreply,
         socket
         |> assign(:blocks, blocks)
         |> mark_saved()}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  # Private functions

  defp add_multi_select_option(socket, block_id, value) do
    project_id = socket.assigns.project.id
    block = Sheets.get_block_in_project!(block_id, project_id)

    # Generate a unique key from the value
    key = generate_option_key(value)

    # Get current options and content
    current_options = get_in(block.config, ["options"]) || []
    current_content = get_in(block.value, ["content"]) || []

    # Check if option already exists (by key or value)
    existing =
      Enum.find(current_options, fn opt ->
        opt["key"] == key || String.downcase(opt["value"] || "") == String.downcase(value)
      end)

    if existing do
      # Option exists - just select it if not already selected
      if existing["key"] in current_content do
        {:noreply, socket}
      else
        new_content = [existing["key"] | current_content]
        update_multi_select_content(socket, block, new_content)
      end
    else
      # Create new option and select it
      new_option = %{"key" => key, "value" => value}
      new_options = current_options ++ [new_option]
      new_content = [key | current_content]

      # Update both config and value
      with {:ok, _} <-
             Sheets.update_block_config(block, %{
               "options" => new_options,
               "label" => block.config["label"] || ""
             }),
           block <- Sheets.get_block_in_project!(block_id, project_id),
           {:ok, _} <- Sheets.update_block_value(block, %{"content" => new_content}) do
        blocks = Sheets.list_blocks(socket.assigns.sheet.id)

        {:noreply,
         socket
         |> assign(:blocks, blocks)
         |> mark_saved()}
      else
        _ -> {:noreply, socket}
      end
    end
  end

  defp update_multi_select_content(socket, block, new_content) do
    case Sheets.update_block_value(block, %{"content" => new_content}) do
      {:ok, _} ->
        blocks = Sheets.list_blocks(socket.assigns.sheet.id)

        {:noreply,
         socket
         |> assign(:blocks, blocks)
         |> mark_saved()}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp generate_option_key(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> then(fn key ->
      if key == "", do: "option-#{:rand.uniform(9999)}", else: key
    end)
  end

  # ===========================================================================
  # Value-returning functions for LiveComponent usage
  # Delegated to BlockValueHelpers module
  # ===========================================================================

  alias StoryarnWeb.SheetLive.Helpers.BlockValueHelpers

  defdelegate toggle_multi_select_value(socket, block_id, key), to: BlockValueHelpers
  defdelegate handle_multi_select_enter_value(socket, block_id, value), to: BlockValueHelpers
  defdelegate update_rich_text_value(socket, block_id, content), to: BlockValueHelpers
  defdelegate set_boolean_block_value(socket, block_id, value_string), to: BlockValueHelpers
end
