defmodule StoryarnWeb.SheetLive.Handlers.ConfigPanelHandlers do
  @moduledoc """
  Handles configuration-panel events for the ContentTab LiveComponent.

  Covers: configure_block, save_block_config, toggle_constant.

  The `helpers` map must contain:
    - `:reload_blocks`        - fn(socket) -> socket
    - `:maybe_create_version` - fn(socket) -> any
    - `:notify_parent`        - fn(socket, status) -> any
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Sheets
  alias StoryarnWeb.SheetLive.Helpers.ContentTabHelpers

  # ---------------------------------------------------------------------------
  # configure_block
  # ---------------------------------------------------------------------------

  @doc "Opens the config panel for the given block."
  def handle_configure_block(block_id, socket, _helpers) do
    block_id = ContentTabHelpers.to_integer(block_id)

    case Sheets.get_block_in_project(block_id, socket.assigns.project.id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Block not found."))}

      block ->
        {:noreply, assign(socket, :configuring_block, block)}
    end
  end

  # ---------------------------------------------------------------------------
  # save_block_config
  # ---------------------------------------------------------------------------

  @doc "Saves configuration params for the currently-configuring block."
  def handle_save_block_config(config_params, socket, helpers) do
    block = socket.assigns.configuring_block
    prev_config = block.config

    case Sheets.update_block_config(block, config_params) do
      {:ok, updated_block} ->
        helpers.push_undo.({:update_block_config, block.id, prev_config, config_params})
        helpers.maybe_create_version.(socket)
        helpers.notify_parent.(socket, :saved)

        {:noreply,
         socket
         |> assign(:configuring_block, updated_block)
         |> helpers.reload_blocks.()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not save configuration."))}
    end
  end

  # ---------------------------------------------------------------------------
  # toggle_constant
  # ---------------------------------------------------------------------------

  @doc "Toggles the `is_constant` flag on the currently-configuring block."
  def handle_toggle_constant(socket, helpers) do
    block = socket.assigns.configuring_block
    prev_value = block.is_constant
    new_value = !prev_value

    case Sheets.update_block(block, %{is_constant: new_value}) do
      {:ok, updated_block} ->
        helpers.push_undo.({:toggle_constant, block.id, prev_value, new_value})
        helpers.maybe_create_version.(socket)
        helpers.notify_parent.(socket, :saved)

        {:noreply,
         socket
         |> assign(:configuring_block, updated_block)
         |> helpers.reload_blocks.()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not toggle constant."))}
    end
  end
end
