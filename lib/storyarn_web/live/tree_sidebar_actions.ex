defmodule StoryarnWeb.Live.TreeSidebarActions do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Storyarn.Shared.MapUtils

  def with_edit(socket, error_message, fun) do
    if socket.assigns.can_edit do
      fun.(socket)
    else
      {:noreply, put_flash(socket, :error, error_message)}
    end
  end

  def confirm_delete(socket, opts) do
    case socket.assigns.pending_delete_id do
      nil -> {:noreply, socket}
      id -> delete_pending(socket, id, opts)
    end
  end

  def move_to_parent(socket, %{"item_id" => id, "new_parent_id" => new_parent_id, "position" => position}, opts) do
    entity = opts.get_entity.(socket.assigns.project.id, MapUtils.parse_int(id))

    move_existing(entity, socket, new_parent_id, position, opts)
  end

  defp delete_pending(socket, id, opts) do
    # The delete itself reports the committed cascade set (collected under its
    # own lock) — broadcasting THOSE ids keeps open editors of the entity and
    # every deleted descendant in sync even under concurrent tree changes.
    with %{} = entity <- opts.get_entity.(socket.assigns.project.id, id),
         {:ok, %{deleted_ids: deleted_ids}} <- opts.delete_entity.(entity) do
      opts.broadcast_deleted.(socket, deleted_ids)

      socket =
        socket
        |> assign(:pending_delete_id, nil)
        |> put_flash(:info, opts.deleted_message)

      socket = opts.refresh_tree.(socket)

      {:noreply, socket}
    else
      _ ->
        {:noreply, put_flash(socket, :error, opts.delete_error_message)}
    end
  end

  defp move_existing(nil, socket, _new_parent_id, _position, _opts), do: {:noreply, socket}

  defp move_existing(entity, socket, new_parent_id, position, opts) do
    parsed_parent = parse_parent_id(new_parent_id)
    parsed_pos = MapUtils.parse_int(position) || 0

    case opts.move_entity.(entity, parsed_parent, parsed_pos) do
      {:ok, _} ->
        {:noreply, opts.refresh_tree.(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, opts.move_error_message)}
    end
  end

  defp parse_parent_id(parent_id) when parent_id in [nil, ""], do: nil
  defp parse_parent_id(parent_id), do: MapUtils.parse_int(parent_id)
end
