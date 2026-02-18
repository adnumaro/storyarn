defmodule StoryarnWeb.FlowLive.Components.ScreenplayEditor do
  @moduledoc """
  Fullscreen screenplay-style editor for dialogue nodes.

  A LiveComponent that provides a distraction-free writing environment with
  screenplay formatting:
  - Speaker selector with name display
  - Stage directions in italics (parenthetical)
  - Clean text editor without toolbar
  - Response list

  ## Usage

      <.live_component
        module={ScreenplayEditor}
        id="screenplay-editor"
        node={@selected_node}
        all_sheets={@all_sheets}
        can_edit={@can_edit}
        on_close={JS.push("close_editor")}
        on_open_sidebar={JS.push("open_sidebar")}
      />

  ## Events sent to parent

  - `{:node_updated, node}` - When node data changes (speaker, stage directions)
  - `{:node_text_updated, node_id, content}` - When text content changes via TipTap
  """

  use StoryarnWeb, :live_component

  alias Storyarn.Flows

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="dialogue-screenplay-editor"
      phx-hook="DialogueScreenplayEditor"
      phx-target={@myself}
      class="fixed inset-0 z-50 bg-base-100 flex flex-col"
    >
      <%!-- Header --%>
      <header class="navbar bg-base-100 border-b border-base-300 px-4 shrink-0">
        <div class="flex-none">
          <button type="button" class="btn btn-ghost btn-sm gap-2" phx-click={@on_open_sidebar}>
            <.icon name="panel-right" class="size-4" />
            {dgettext("flows", "Open Sidebar")}
          </button>
        </div>
        <div class="flex-1"></div>
        <div class="flex-none">
          <button type="button" class="btn btn-ghost btn-sm btn-square" phx-click={@on_close}>
            <.icon name="x" class="size-5" />
          </button>
        </div>
      </header>

      <%!-- Main Content - Screenplay Paper Layout --%>
      <div class="flex-1 overflow-y-auto screenplay-container">
        <div class="screenplay-page">
          <%!-- Speaker Selector --%>
          <div class={["sp-character", @speaker_name && "sp-character-ref"]}>
            <%= if @can_edit do %>
              <.form for={@form} phx-change="update_speaker" phx-target={@myself} class="inline-block">
                <select name="speaker_sheet_id" class="dialogue-sp-select">
                  <option value="" selected={@form[:speaker_sheet_id].value in [nil, ""]}>
                    {dgettext("flows", "SELECT SPEAKER")}
                  </option>
                  <option
                    :for={{name, id} <- @speaker_options}
                    value={id}
                    selected={to_string(@form[:speaker_sheet_id].value) == to_string(id)}
                  >
                    {String.upcase(name)}
                  </option>
                </select>
              </.form>
            <% else %>
              <span class="sp-character-content">
                {@speaker_name || dgettext("flows", "SPEAKER")}
              </span>
            <% end %>
          </div>

          <%!-- Stage Directions --%>
          <div class="sp-parenthetical">
            <%= if @can_edit do %>
              <.form
                for={@form}
                phx-change="update_stage_directions"
                phx-debounce="500"
                phx-target={@myself}
              >
                <input
                  type="text"
                  id="screenplay-stage-directions"
                  name="stage_directions"
                  value={@form[:stage_directions].value || ""}
                  placeholder={dgettext("flows", "(stage directions)")}
                  class="dialogue-sp-input"
                />
              </.form>
            <% else %>
              <span :if={@form[:stage_directions].value && @form[:stage_directions].value != ""}>
                ({@form[:stage_directions].value})
              </span>
            <% end %>
          </div>

          <%!-- Dialogue Text Editor (no toolbar) --%>
          <div class="sp-dialogue">
            <div
              id={"screenplay-text-editor-#{@node.id}"}
              phx-hook="TiptapEditor"
              phx-update="ignore"
              data-phx-target={@myself}
              data-node-id={@node.id}
              data-content={@form[:text].value || ""}
              data-editable={to_string(@can_edit)}
              data-placeholder={dgettext("flows", "Enter dialogue text...")}
              data-mode="dialogue-screenplay"
              class="min-h-[200px] focus:outline-none"
            >
            </div>
          </div>

          <%!-- Responses Section --%>
          <div
            :if={(@form[:responses].value || []) != []}
            class="sp-interactive-block sp-interactive-response"
            style="margin-top: 32px;"
          >
            <div class="sp-interactive-header">
              <span class="sp-interactive-label">{dgettext("flows", "Responses")}</span>
            </div>
            <div
              :for={response <- @form[:responses].value || []}
              class="sp-choice-row"
            >
              <span class="sp-choice-number">
                <.icon name="corner-down-right" class="size-3" />
              </span>
              <span class="sp-choice-text">
                {response["text"] || dgettext("flows", "(empty response)")}
              </span>
            </div>
            <p class="sp-choice-empty" style="margin-top: 8px;">
              {dgettext("flows", "Edit responses in the sidebar panel.")}
            </p>
          </div>
        </div>
      </div>

      <%!-- Footer Status Bar --%>
      <footer class="bg-base-100 border-t border-base-300 px-4 py-2 flex items-center justify-between text-xs text-base-content/50">
        <div class="flex items-center gap-4">
          <span :if={@speaker_name}>
            <.icon name="user" class="size-3 inline mr-1" />
            {@speaker_name}
          </span>
          <span>
            <.icon name="file-text" class="size-3 inline mr-1" />
            {dngettext("flows", "%{count} word", "%{count} words", @word_count, count: @word_count)}
          </span>
        </div>
        <div class="flex items-center gap-2">
          <span class="kbd kbd-xs">Esc</span>
          <span>{dgettext("flows", "to close")}</span>
        </div>
      </footer>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_derived()

    {:ok, socket}
  end

  @impl true
  def handle_event("update_speaker", %{"speaker_sheet_id" => speaker_sheet_id}, socket) do
    update_node_field(socket, "speaker_sheet_id", speaker_sheet_id)
  end

  def handle_event("update_stage_directions", %{"stage_directions" => stage_directions}, socket) do
    update_node_field(socket, "stage_directions", stage_directions)
  end

  def handle_event("update_node_text", %{"id" => _node_id, "content" => content}, socket) do
    update_node_field(socket, "text", content)
  end

  # Proxy mention suggestions to parent (needs project context)
  def handle_event("mention_suggestions", %{"query" => query}, socket) do
    send(self(), {:mention_suggestions, query, socket.assigns.myself})
    {:noreply, socket}
  end

  # Private functions

  defp assign_derived(socket) do
    node = socket.assigns.node
    all_sheets = socket.assigns.all_sheets

    form = build_form(node)
    speaker_name = get_speaker_name(node, all_sheets)
    word_count = count_words(node.data["text"])
    speaker_options = build_speaker_options(all_sheets)

    socket
    |> assign(:form, form)
    |> assign(:speaker_name, speaker_name)
    |> assign(:word_count, word_count)
    |> assign(:speaker_options, speaker_options)
  end

  defp build_form(node) do
    data = %{
      "speaker_sheet_id" => node.data["speaker_sheet_id"] || "",
      "text" => node.data["text"] || "",
      "stage_directions" => node.data["stage_directions"] || "",
      "responses" => node.data["responses"] || []
    }

    to_form(data, as: :screenplay)
  end

  defp update_node_field(socket, field, value) do
    node = socket.assigns.node
    updated_data = Map.put(node.data, field, value)

    case Flows.update_node_data(node, updated_data) do
      {:ok, updated_node, _meta} ->
        send(self(), {:node_updated, updated_node})

        socket =
          socket
          |> assign(:node, updated_node)
          |> assign_derived()

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  defp build_speaker_options(all_sheets) do
    Enum.map(all_sheets, fn sheet -> {sheet.name, sheet.id} end)
  end

  defp get_speaker_name(node, all_sheets) do
    speaker_sheet_id = node.data["speaker_sheet_id"]
    find_sheet_name(speaker_sheet_id, all_sheets)
  end

  defp find_sheet_name(nil, _all_sheets), do: nil

  defp find_sheet_name(speaker_sheet_id, all_sheets) do
    case Enum.find(all_sheets, fn sheet -> sheet.id == speaker_sheet_id end) do
      nil -> nil
      sheet -> sheet.name
    end
  end

  defp count_words(nil), do: 0
  defp count_words(""), do: 0

  defp count_words(html) when is_binary(html) do
    html
    |> String.replace(~r/<[^>]*>/, " ")
    |> String.split(~r/\s+/, trim: true)
    |> length()
  end
end
