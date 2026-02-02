defmodule StoryarnWeb.PageLive.Helpers.ConfigHelpers do
  @moduledoc """
  Block configuration panel helpers for the page editor.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Pages

  @doc """
  Opens the configuration panel for a block.
  Returns {:noreply, socket} tuple.
  """
  @spec configure_block(Phoenix.LiveView.Socket.t(), any()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def configure_block(socket, block_id) do
    block = Pages.get_block!(block_id)
    {:noreply, assign(socket, :configuring_block, block)}
  end

  @doc """
  Closes the configuration panel.
  Returns {:noreply, socket} tuple.
  """
  @spec close_config_panel(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def close_config_panel(socket) do
    {:noreply, assign(socket, :configuring_block, nil)}
  end

  @doc """
  Saves block configuration.
  Returns {:noreply, socket} tuple.
  """
  @spec save_block_config(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def save_block_config(socket, config_params) do
    block = socket.assigns.configuring_block

    # Convert options from indexed map to list
    config_params = normalize_config_params(config_params)

    case Pages.update_block_config(block, config_params) do
      {:ok, updated_block} ->
        blocks = Pages.list_blocks(socket.assigns.page.id)
        schedule_save_status_reset()

        {:noreply,
         socket
         |> assign(:blocks, blocks)
         |> assign(:configuring_block, updated_block)
         |> assign(:save_status, :saved)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not save configuration."))}
    end
  end

  @doc """
  Adds a new select option.
  Returns {:noreply, socket} tuple.
  """
  @spec add_select_option(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def add_select_option(socket) do
    block = socket.assigns.configuring_block
    options = get_in(block.config, ["options"]) || []
    new_option = %{"key" => "option-#{length(options) + 1}", "value" => ""}
    new_options = options ++ [new_option]

    case Pages.update_block_config(block, %{"options" => new_options}) do
      {:ok, updated_block} ->
        blocks = Pages.list_blocks(socket.assigns.page.id)

        {:noreply,
         socket
         |> assign(:blocks, blocks)
         |> assign(:configuring_block, updated_block)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @doc """
  Removes a select option by index.
  Returns {:noreply, socket} tuple.
  """
  @spec remove_select_option(Phoenix.LiveView.Socket.t(), String.t() | integer()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def remove_select_option(socket, index) do
    case parse_index(index) do
      {:ok, idx} ->
        block = socket.assigns.configuring_block
        options = get_in(block.config, ["options"]) || []
        new_options = List.delete_at(options, idx)

        case Pages.update_block_config(block, %{"options" => new_options}) do
          {:ok, updated_block} ->
            blocks = Pages.list_blocks(socket.assigns.page.id)

            {:noreply,
             socket
             |> assign(:blocks, blocks)
             |> assign(:configuring_block, updated_block)}

          {:error, _} ->
            {:noreply, socket}
        end

      :error ->
        {:noreply, socket}
    end
  end

  @doc """
  Updates a select option at a given index.
  Returns {:noreply, socket} tuple.
  """
  @spec update_select_option(
          Phoenix.LiveView.Socket.t(),
          String.t() | integer(),
          String.t(),
          String.t()
        ) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def update_select_option(socket, index, key, value) do
    case parse_index(index) do
      {:ok, idx} ->
        block = socket.assigns.configuring_block
        options = get_in(block.config, ["options"]) || []

        new_options =
          List.update_at(options, idx, fn _opt ->
            %{"key" => key, "value" => value}
          end)

        case Pages.update_block_config(block, %{"options" => new_options}) do
          {:ok, updated_block} ->
            blocks = Pages.list_blocks(socket.assigns.page.id)

            {:noreply,
             socket
             |> assign(:blocks, blocks)
             |> assign(:configuring_block, updated_block)}

          {:error, _} ->
            {:noreply, socket}
        end

      :error ->
        {:noreply, socket}
    end
  end

  # Private functions

  defp normalize_config_params(params) do
    case Map.get(params, "options") do
      nil ->
        params

      options when is_map(options) ->
        Map.put(params, "options", options_map_to_list(options))

      _ ->
        params
    end
  end

  defp options_map_to_list(options) do
    options
    |> Enum.map(&parse_option_with_index/1)
    |> Enum.sort_by(fn {idx, _} -> idx end)
    |> Enum.map(fn {_, opt} -> opt end)
  end

  defp parse_option_with_index({idx, opt}) do
    case parse_index(idx) do
      {:ok, int} -> {int, opt}
      :error -> {0, opt}
    end
  end

  defp parse_index(index) when is_binary(index) do
    case Integer.parse(index) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  defp parse_index(index) when is_integer(index), do: {:ok, index}
  defp parse_index(_), do: :error

  defp schedule_save_status_reset do
    Process.send_after(self(), :reset_save_status, 4000)
  end
end
