defmodule StoryarnWeb.SheetLive.Components.AudioTab do
  @moduledoc """
  LiveComponent for the Audio tab in the sheet editor.
  Shows all dialogue nodes where this sheet is the speaker, with audio status.
  """

  use StoryarnWeb, :live_component

  alias Storyarn.Assets
  alias Storyarn.Flows

  @impl true
  def render(assigns) do
    ~H"""
    <section>
      <h2 class="text-lg font-semibold mb-4 flex items-center gap-2">
        <.icon name="volume-2" class="size-5" />
        {gettext("Voice Lines")}
        <%= if @voice_lines != [] do %>
          <span class="badge badge-sm">{length(@voice_lines)}</span>
        <% end %>
      </h2>

      <%= if @voice_lines == [] do %>
        <.empty_voice_lines_state />
      <% else %>
        <div class="space-y-4">
          <.flow_group
            :for={{flow, lines} <- @grouped_lines}
            flow={flow}
            lines={lines}
            workspace={@workspace}
            project={@project}
          />
        </div>
      <% end %>
    </section>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    voice_lines = load_voice_lines(socket.assigns.project, socket.assigns.sheet)

    grouped_lines =
      voice_lines
      |> Enum.group_by(& &1.flow)
      |> Enum.sort_by(fn {flow, _} -> flow.name end)

    {:ok, assign(socket, voice_lines: voice_lines, grouped_lines: grouped_lines)}
  end

  # ===========================================================================
  # Private: Data Loading
  # ===========================================================================

  defp load_voice_lines(project, sheet) do
    nodes = Flows.list_dialogue_nodes_by_speaker(project.id, sheet.id)

    Enum.map(nodes, fn node ->
      audio_asset = resolve_audio_asset(project.id, node.data["audio_asset_id"])

      %{
        node: node,
        flow: node.flow,
        text: node.data["text"] || "",
        audio_asset: audio_asset
      }
    end)
  end

  defp resolve_audio_asset(_project_id, nil), do: nil
  defp resolve_audio_asset(_project_id, ""), do: nil

  defp resolve_audio_asset(project_id, asset_id) do
    Assets.get_asset(project_id, asset_id)
  end

  # ===========================================================================
  # Function Components
  # ===========================================================================

  defp empty_voice_lines_state(assigns) do
    ~H"""
    <div class="bg-base-200/50 rounded-lg p-8 text-center">
      <.icon name="volume-x" class="size-12 mx-auto text-base-content/30 mb-4" />
      <p class="text-base-content/70 mb-2">{gettext("No voice lines")}</p>
      <p class="text-sm text-base-content/50">
        {gettext("Dialogue nodes using this sheet as speaker will appear here.")}
      </p>
    </div>
    """
  end

  attr :flow, :map, required: true
  attr :lines, :list, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true

  defp flow_group(assigns) do
    ~H"""
    <div>
      <.link
        navigate={
          ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows/#{@flow.id}"
        }
        class="flex items-center gap-2 mb-2 text-sm font-medium text-primary hover:underline"
      >
        <.icon name="git-branch" class="size-4" />
        {@flow.name}
        <%= if @flow.shortcut do %>
          <span class="text-xs text-base-content/50">#{@flow.shortcut}</span>
        <% end %>
      </.link>
      <div class="space-y-2 ml-6">
        <.voice_line_row :for={line <- @lines} line={line} />
      </div>
    </div>
    """
  end

  attr :line, :map, required: true

  defp voice_line_row(assigns) do
    text_preview = truncate_html(assigns.line.text, 80)
    assigns = assign(assigns, :text_preview, text_preview)

    ~H"""
    <div class="p-3 bg-base-200/50 rounded-lg">
      <p :if={@text_preview != ""} class="text-sm text-base-content/80 mb-2">
        {@text_preview}
      </p>
      <p :if={@text_preview == ""} class="text-sm text-base-content/40 italic mb-2">
        {gettext("(empty dialogue)")}
      </p>

      <%= if @line.audio_asset do %>
        <div class="flex items-center gap-2 text-xs text-base-content/60">
          <.icon name="volume-2" class="size-3" />
          <span class="truncate">{@line.audio_asset.filename}</span>
        </div>
        <audio controls class="w-full h-8 mt-1">
          <source src={@line.audio_asset.url} type={@line.audio_asset.content_type} />
        </audio>
      <% else %>
        <div class="flex items-center gap-2 text-xs text-base-content/40">
          <.icon name="volume-x" class="size-3" />
          <span>{gettext("No audio")}</span>
        </div>
      <% end %>
    </div>
    """
  end

  defp truncate_html(nil, _max), do: ""
  defp truncate_html("", _max), do: ""

  defp truncate_html(html, max) do
    text =
      html
      |> String.replace(~r/<[^>]+>/, "")
      |> String.replace(~r/&nbsp;/, " ")
      |> String.trim()

    if String.length(text) > max do
      String.slice(text, 0, max) <> "..."
    else
      text
    end
  end
end
