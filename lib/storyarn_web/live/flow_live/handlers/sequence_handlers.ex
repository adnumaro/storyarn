defmodule StoryarnWeb.FlowLive.Handlers.SequenceHandlers do
  @moduledoc """
  Event handlers for Sequence lifecycle on the flow editor:

  - `create_sequence_from_node` — right-click menu on a node. Creates a
    new Sequence anchored at that node, sets the node's `sequence_directive`,
    and opens the bottom-docked editor panel.
  - `open_sequence_panel` — opens the panel for an existing Sequence by id.
  - `close_sequence_panel` — collapses the panel.
  - `update_sequence_name` — renames the currently-open sequence (inline
    editable header in the panel).
  """

  use Gettext, backend: Storyarn.Gettext

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Storyarn.Flows
  alias StoryarnWeb.Helpers.Authorize

  @doc "Creates a Sequence from a right-clicked node and opens the editor panel."
  def handle_create_sequence_from_node(%{"node_id" => node_id_param}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      flow = socket.assigns.flow

      with {node_id, _} <- parse_id(node_id_param),
           node when not is_nil(node) <- Flows.get_node(flow.id, node_id),
           {:ok, sequence} <-
             Flows.create_sequence_from_node(node, %{
               "name" => default_sequence_name(node)
             }) do
        {:noreply,
         socket
         |> assign(:active_sequence, sequence)
         |> assign(:sequence_panel_open, true)
         |> put_flash(:info, dgettext("flows", "Sequence created"))}
      else
        _ ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Could not create sequence"))}
      end
    end)
  end

  @doc "Opens the panel for an existing Sequence."
  def handle_open_sequence_panel(%{"sequence_id" => id_param}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      flow = socket.assigns.flow

      with {id, _} <- parse_id(id_param),
           %{} = sequence <- Flows.get_sequence(flow.id, id) do
        {:noreply,
         socket
         |> assign(:active_sequence, sequence)
         |> assign(:sequence_panel_open, true)}
      else
        _ ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Sequence not found"))}
      end
    end)
  end

  @doc "Closes the panel and clears the active sequence."
  def handle_close_sequence_panel(_params, socket) do
    {:noreply,
     socket
     |> assign(:sequence_panel_open, false)
     |> assign(:active_sequence, nil)}
  end

  @doc "Updates the name of the currently-open sequence."
  def handle_update_sequence_name(%{"name" => name}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      case socket.assigns[:active_sequence] do
        nil ->
          {:noreply, socket}

        sequence ->
          case Flows.update_sequence(sequence, %{"name" => name}) do
            {:ok, updated} ->
              {:noreply, assign(socket, :active_sequence, updated)}

            {:error, _changeset} ->
              {:noreply, put_flash(socket, :error, dgettext("flows", "Invalid sequence name"))}
          end
      end
    end)
  end

  # -- Private helpers --

  defp parse_id(value) when is_integer(value), do: {value, ""}

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, rest} -> {id, rest}
      :error -> :error
    end
  end

  defp parse_id(_), do: :error

  defp default_sequence_name(node) do
    case node_label(node) do
      nil -> dgettext("flows", "Sequence")
      label -> dgettext("flows", "Sequence at %{node}", node: label)
    end
  end

  defp node_label(%{type: "dialogue", data: %{"technical_id" => tid}}) when is_binary(tid) and tid != "", do: tid

  defp node_label(%{type: "hub", data: %{"label" => label}}) when is_binary(label) and label != "", do: label

  defp node_label(%{type: "exit", data: %{"label" => label}}) when is_binary(label) and label != "", do: label

  defp node_label(_), do: nil
end
