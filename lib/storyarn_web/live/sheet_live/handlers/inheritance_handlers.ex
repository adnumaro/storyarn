defmodule StoryarnWeb.SheetLive.Handlers.InheritanceHandlers do
  @moduledoc """
  Handles inheritance and propagation events for the ContentTab LiveComponent.

  Each public function corresponds to one or more `handle_event` clauses in
  `ContentTab` and returns `{:noreply, socket}`.

  Socket helpers (`reload_blocks/1`, `maybe_create_version/1`, `notify_parent/2`)
  are passed in as a `helpers` map so this module stays decoupled from the
  LiveComponent internals.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_navigate: 2, put_flash: 3]

  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Sheets
  alias StoryarnWeb.SheetLive.Helpers.ContentTabHelpers

  # ---------------------------------------------------------------------------
  # detach_inherited_block
  # ---------------------------------------------------------------------------

  @doc "Detaches an inherited block so it becomes an independent copy."
  def handle_detach(block_id, socket, helpers) do
    block_id = ContentTabHelpers.to_integer(block_id)
    project_id = socket.assigns.project.id

    case Sheets.get_block_in_project(block_id, project_id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Block not found."))}

      block ->
        case Sheets.detach_block(block) do
          {:ok, _} ->
            helpers.maybe_create_version.(socket)
            helpers.notify_parent.(socket, :saved)

            {:noreply,
             socket
             |> helpers.reload_blocks.()
             |> put_flash(
               :info,
               dgettext(
                 "sheets",
                 "Property detached. Changes to the source won't affect this copy."
               )
             )}

          {:error, _} ->
            {:noreply,
             put_flash(socket, :error, dgettext("sheets", "Could not detach property."))}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # reattach_block
  # ---------------------------------------------------------------------------

  @doc "Re-syncs an inherited block with its source."
  def handle_reattach(block_id, socket, helpers) do
    block_id = ContentTabHelpers.to_integer(block_id)
    project_id = socket.assigns.project.id

    case Sheets.get_block_in_project(block_id, project_id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Block not found."))}

      block ->
        case Sheets.reattach_block(block) do
          {:ok, _} ->
            helpers.maybe_create_version.(socket)
            helpers.notify_parent.(socket, :saved)

            {:noreply,
             socket
             |> assign(:configuring_block, nil)
             |> helpers.reload_blocks.()
             |> put_flash(:info, dgettext("sheets", "Property re-synced with source."))}

          {:error, :source_not_found} ->
            {:noreply,
             put_flash(socket, :error, dgettext("sheets", "Source block no longer exists."))}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # hide_inherited_for_children / unhide_inherited_for_children
  # ---------------------------------------------------------------------------

  @doc "Hides an inherited block from child sheets."
  def handle_hide_for_children(block_id, socket, _helpers) do
    block_id = ContentTabHelpers.to_integer(block_id)
    sheet = socket.assigns.sheet

    case Sheets.hide_for_children(sheet, block_id) do
      {:ok, updated_sheet} ->
        {:noreply,
         socket
         |> assign(:sheet, updated_sheet)
         |> put_flash(:info, dgettext("sheets", "Property hidden from children."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not hide property."))}
    end
  end

  @doc "Restores an inherited block's visibility to child sheets."
  def handle_unhide_for_children(block_id, socket, _helpers) do
    block_id = ContentTabHelpers.to_integer(block_id)
    sheet = socket.assigns.sheet

    case Sheets.unhide_for_children(sheet, block_id) do
      {:ok, updated_sheet} ->
        {:noreply,
         socket
         |> assign(:sheet, updated_sheet)
         |> put_flash(:info, dgettext("sheets", "Property visible to children again."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not unhide property."))}
    end
  end

  # ---------------------------------------------------------------------------
  # navigate_to_source
  # ---------------------------------------------------------------------------

  @doc "Navigates to the sheet that owns the source block."
  def handle_navigate_to_source(block_id, socket, _helpers) do
    block_id = ContentTabHelpers.to_integer(block_id)
    project_id = socket.assigns.project.id

    case Sheets.get_block_in_project(block_id, project_id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Source block not found."))}

      block ->
        source_sheet = Sheets.get_source_sheet(block)

        if source_sheet do
          workspace = socket.assigns.workspace
          project = socket.assigns.project

          {:noreply,
           push_navigate(socket,
             to:
               ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{source_sheet.id}"
           )}
        else
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Source sheet not found."))}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # change_block_scope
  # ---------------------------------------------------------------------------

  @doc ~S[Changes the scope of a block ("self" | "children"), opening the propagation modal when needed.]
  def handle_change_scope(scope, socket, helpers) do
    block = socket.assigns.configuring_block

    if block.scope == scope do
      {:noreply, socket}
    else
      do_change_block_scope(socket, block, scope, helpers)
    end
  end

  # ---------------------------------------------------------------------------
  # toggle_required
  # ---------------------------------------------------------------------------

  @doc "Toggles the `required` flag on the currently-configuring block."
  def handle_toggle_required(socket, helpers) do
    block = socket.assigns.configuring_block
    new_value = !block.required

    case Sheets.update_block(block, %{required: new_value}) do
      {:ok, updated_block} ->
        helpers.notify_parent.(socket, :saved)

        {:noreply,
         socket
         |> assign(:configuring_block, updated_block)
         |> helpers.reload_blocks.()}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, dgettext("sheets", "Could not update required flag."))}
    end
  end

  # ---------------------------------------------------------------------------
  # Propagation events
  # ---------------------------------------------------------------------------

  @doc "Opens the propagation modal for the given block."
  def handle_open_propagation_modal(block_id, socket, _helpers) do
    block_id = ContentTabHelpers.to_integer(block_id)

    case Sheets.get_block_in_project(block_id, socket.assigns.project.id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Block not found."))}

      block ->
        {:noreply, assign(socket, :propagation_block, block)}
    end
  end

  @doc "Cancels the propagation modal."
  def handle_cancel_propagation(socket) do
    {:noreply, assign(socket, :propagation_block, nil)}
  end

  @doc "Propagates a block to the selected descendant sheet IDs."
  def handle_propagate_property(sheet_ids_json, socket, _helpers) do
    block = socket.assigns.propagation_block

    case Jason.decode(sheet_ids_json) do
      {:ok, sheet_ids} when is_list(sheet_ids) ->
        do_propagate_property(socket, block, sheet_ids)

      _ ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Invalid sheet selection."))}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp do_change_block_scope(socket, block, scope, helpers) do
    case Sheets.update_block(block, %{scope: scope}) do
      {:ok, updated_block} ->
        helpers.maybe_create_version.(socket)
        helpers.notify_parent.(socket, :saved)

        socket =
          socket
          |> assign(:configuring_block, updated_block)
          |> helpers.reload_blocks.()
          |> maybe_open_propagation_modal(scope, updated_block)

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not change scope."))}
    end
  end

  defp maybe_open_propagation_modal(socket, "children", updated_block) do
    descendant_ids = Sheets.get_descendant_sheet_ids(socket.assigns.sheet.id)

    if descendant_ids != [] do
      assign(socket, :propagation_block, updated_block)
    else
      socket
    end
  end

  defp maybe_open_propagation_modal(socket, _scope, _block) do
    assign(socket, :propagation_block, nil)
  end

  defp do_propagate_property(socket, block, sheet_ids) do
    case Sheets.propagate_to_descendants(block, sheet_ids) do
      {:ok, count} ->
        {:noreply,
         socket
         |> assign(:propagation_block, nil)
         |> put_flash(
           :info,
           dgettext("sheets", "Property propagated to %{count} pages.", count: count)
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not propagate property."))}
    end
  end
end
