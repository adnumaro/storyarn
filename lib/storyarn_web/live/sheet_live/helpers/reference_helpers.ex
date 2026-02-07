defmodule StoryarnWeb.SheetLive.Helpers.ReferenceHelpers do
  @moduledoc false

  import Phoenix.Component
  import Phoenix.LiveView
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Sheets

  @doc """
  Handles search_references event.
  """
  def search_references(socket, query, block_id) do
    block = Sheets.get_block_in_project!(block_id, socket.assigns.project.id)
    allowed_types = get_in(block.config, ["allowed_types"]) || ["sheet", "flow"]

    results = Sheets.search_referenceable(socket.assigns.project.id, query, allowed_types)

    # Send results to client via push_event
    {:noreply,
     push_event(socket, "reference_results", %{
       block_id: block_id,
       results: results
     })}
  end

  @doc """
  Handles select_reference event.
  """
  def select_reference(socket, block_id, target_type, target_id) do
    project_id = socket.assigns.project.id
    block = Sheets.get_block_in_project!(block_id, project_id)

    with {target_id_int, ""} <- Integer.parse(target_id),
         {:ok, _target} <- Sheets.validate_reference_target(target_type, target_id_int, project_id),
         {:ok, _block} <-
           Sheets.update_block_value(block, %{
             "target_type" => target_type,
             "target_id" => target_id_int
           }) do
      blocks = load_blocks_with_references(socket.assigns.sheet.id, project_id)

      {:noreply,
       socket
       |> assign(:blocks, blocks)
       |> assign(:save_status, :saved)
       |> schedule_save_status_reset()}
    else
      :error ->
        {:noreply, put_flash(socket, :error, gettext("Invalid reference ID."))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, gettext("Reference target not found."))}

      {:error, :invalid_type} ->
        {:noreply, put_flash(socket, :error, gettext("Invalid reference type."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not set reference."))}
    end
  end

  @doc """
  Handles clear_reference event.
  """
  def clear_reference(socket, block_id) do
    block = Sheets.get_block_in_project!(block_id, socket.assigns.project.id)

    case Sheets.update_block_value(block, %{"target_type" => nil, "target_id" => nil}) do
      {:ok, _block} ->
        blocks = load_blocks_with_references(socket.assigns.sheet.id, socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(:blocks, blocks)
         |> assign(:save_status, :saved)
         |> schedule_save_status_reset()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not clear reference."))}
    end
  end

  @doc """
  Loads blocks with their reference targets resolved.
  """
  def load_blocks_with_references(sheet_id, project_id) do
    blocks = Sheets.list_blocks(sheet_id)

    Enum.map(blocks, fn block ->
      if block.type == "reference" do
        target_type = get_in(block.value, ["target_type"])
        target_id = get_in(block.value, ["target_id"])
        reference_target = Sheets.get_reference_target(target_type, target_id, project_id)
        Map.put(block, :reference_target, reference_target)
      else
        Map.put(block, :reference_target, nil)
      end
    end)
  end

  # ===========================================================================
  # Value-returning functions for LiveComponent usage
  # ===========================================================================

  @doc """
  Selects a reference target.
  Returns {:ok, blocks} or {:error, message}.
  """
  def select_reference_value(socket, block_id, target_type, target_id) do
    block_id = parse_id(block_id)
    project_id = socket.assigns.project.id
    sheet_id = socket.assigns.sheet.id
    block = Sheets.get_block_in_project!(block_id, project_id)

    with {target_id_int, ""} <- Integer.parse(target_id),
         {:ok, _target} <- Sheets.validate_reference_target(target_type, target_id_int, project_id),
         {:ok, _block} <-
           Sheets.update_block_value(block, %{
             "target_type" => target_type,
             "target_id" => target_id_int
           }) do
      blocks = load_blocks_with_references(sheet_id, project_id)
      {:ok, blocks}
    else
      :error ->
        {:error, gettext("Invalid reference ID.")}

      {:error, :not_found} ->
        {:error, gettext("Reference target not found.")}

      {:error, :invalid_type} ->
        {:error, gettext("Invalid reference type.")}

      {:error, _} ->
        {:error, gettext("Could not set reference.")}
    end
  end

  @doc """
  Clears a reference.
  Returns {:ok, blocks} or {:error, message}.
  """
  def clear_reference_value(socket, block_id) do
    block_id = parse_id(block_id)
    project_id = socket.assigns.project.id
    sheet_id = socket.assigns.sheet.id
    block = Sheets.get_block_in_project!(block_id, project_id)

    case Sheets.update_block_value(block, %{"target_type" => nil, "target_id" => nil}) do
      {:ok, _block} ->
        blocks = load_blocks_with_references(sheet_id, project_id)
        {:ok, blocks}

      {:error, _} ->
        {:error, gettext("Could not clear reference.")}
    end
  end

  # Private functions

  defp schedule_save_status_reset(socket) do
    Process.send_after(self(), :reset_save_status, 4000)
    socket
  end

  defp parse_id(id) when is_binary(id), do: String.to_integer(id)
  defp parse_id(id) when is_integer(id), do: id
end
