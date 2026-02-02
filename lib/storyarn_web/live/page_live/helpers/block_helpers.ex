defmodule StoryarnWeb.PageLive.Helpers.BlockHelpers do
  @moduledoc """
  Block operation helpers for the page editor.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Pages

  @doc """
  Adds a new block to the page.
  Returns {:noreply, socket} tuple.
  """
  @spec add_block(Phoenix.LiveView.Socket.t(), String.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def add_block(socket, type) do
    case Pages.create_block(socket.assigns.page, %{type: type}) do
      {:ok, _block} ->
        blocks = Pages.list_blocks(socket.assigns.page.id)

        {:noreply,
         socket
         |> assign(:blocks, blocks)
         |> assign(:show_block_menu, false)}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Could not add block."))
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
    block = Pages.get_block!(block_id)

    case Pages.update_block_value(block, %{"content" => value}) do
      {:ok, _block} ->
        blocks = Pages.list_blocks(socket.assigns.page.id)
        schedule_save_status_reset()

        {:noreply,
         socket
         |> assign(:blocks, blocks)
         |> assign(:save_status, :saved)}

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
    block = Pages.get_block!(block_id)

    case Pages.delete_block(block) do
      {:ok, _} ->
        blocks = Pages.list_blocks(socket.assigns.page.id)

        {:noreply,
         socket
         |> assign(:blocks, blocks)
         |> assign(:configuring_block, nil)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not delete block."))}
    end
  end

  @doc """
  Reorders blocks.
  Returns {:noreply, socket} tuple.
  """
  @spec reorder_blocks(Phoenix.LiveView.Socket.t(), list()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def reorder_blocks(socket, ids) do
    case Pages.reorder_blocks(socket.assigns.page.id, ids) do
      {:ok, blocks} ->
        {:noreply, assign(socket, :blocks, blocks)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not reorder blocks."))}
    end
  end

  @doc """
  Toggles a multi-select option.
  Returns {:noreply, socket} tuple.
  """
  @spec toggle_multi_select(Phoenix.LiveView.Socket.t(), any(), String.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def toggle_multi_select(socket, block_id, key) do
    block = Pages.get_block!(block_id)
    current = get_in(block.value, ["content"]) || []

    new_content =
      if key in current do
        List.delete(current, key)
      else
        [key | current]
      end

    case Pages.update_block_value(block, %{"content" => new_content}) do
      {:ok, _block} ->
        blocks = Pages.list_blocks(socket.assigns.page.id)
        schedule_save_status_reset()

        {:noreply,
         socket
         |> assign(:blocks, blocks)
         |> assign(:save_status, :saved)}

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
    block = Pages.get_block!(block_id)

    case Pages.update_block_value(block, %{"content" => content}) do
      {:ok, _block} ->
        # Don't reload blocks to avoid disrupting the editor
        schedule_save_status_reset()
        {:noreply, assign(socket, :save_status, :saved)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  # Private functions

  defp add_multi_select_option(socket, block_id, value) do
    block = Pages.get_block!(block_id)

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
             Pages.update_block_config(block, %{
               "options" => new_options,
               "label" => block.config["label"] || ""
             }),
           block <- Pages.get_block!(block_id),
           {:ok, _} <- Pages.update_block_value(block, %{"content" => new_content}) do
        blocks = Pages.list_blocks(socket.assigns.page.id)
        schedule_save_status_reset()

        {:noreply,
         socket
         |> assign(:blocks, blocks)
         |> assign(:save_status, :saved)}
      else
        _ -> {:noreply, socket}
      end
    end
  end

  defp update_multi_select_content(socket, block, new_content) do
    case Pages.update_block_value(block, %{"content" => new_content}) do
      {:ok, _} ->
        blocks = Pages.list_blocks(socket.assigns.page.id)
        schedule_save_status_reset()

        {:noreply,
         socket
         |> assign(:blocks, blocks)
         |> assign(:save_status, :saved)}

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

  defp schedule_save_status_reset do
    Process.send_after(self(), :reset_save_status, 4000)
  end
end
