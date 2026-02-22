defmodule StoryarnWeb.FlowLive.Components.ScreenplayEditor do
  @moduledoc """
  Fullscreen two-panel editor for dialogue nodes.

  A LiveComponent that provides:
  - Left panel: Screenplay-style writing (speaker, stage directions, TipTap text editor)
  - Right panel: Tabbed interface (Responses tab with editable cards, Settings tab)

  ## Usage

      <.live_component
        module={ScreenplayEditor}
        id="screenplay-editor"
        node={@selected_node}
        all_sheets={@all_sheets}
        can_edit={@can_edit}
        project_variables={@project_variables}
        on_close={JS.push("close_editor")}
      />

  ## Events sent to parent

  - `{:node_updated, node}` - When node data changes
  - `{:mention_suggestions, query, cid}` - Mention autocomplete proxy
  """

  use StoryarnWeb, :live_component

  import StoryarnWeb.Components.ExpressionEditor

  alias Storyarn.Flows
  alias StoryarnWeb.FlowLive.Components.NodeTypeHelpers

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
          <button type="button" class="btn btn-ghost btn-sm gap-2" phx-click={@on_close}>
            <.icon name="arrow-left" class="size-4" />
            {dgettext("flows", "Back to canvas")}
          </button>
        </div>
        <div class="flex-1"></div>
        <div class="flex-none">
          <button type="button" class="btn btn-ghost btn-sm btn-square" phx-click={@on_close}>
            <.icon name="x" class="size-5" />
          </button>
        </div>
      </header>

      <%!-- Main Content - Two Panel Layout --%>
      <div class="flex-1 overflow-hidden grid grid-cols-1 lg:grid-cols-2">
        <%!-- Left Panel: Screenplay --%>
        <div class="overflow-y-auto screenplay-container border-r border-base-300">
          <div class="screenplay-page">
            <%!-- Speaker Selector --%>
            <div class={["sp-character", @speaker_name && "sp-character-ref"]}>
              <%= if @can_edit do %>
                <.form
                  for={@form}
                  phx-change="update_speaker"
                  phx-target={@myself}
                  class="inline-block"
                >
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

            <%!-- Dialogue Text Editor --%>
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
                data-variables-enabled="true"
                class="min-h-[200px] focus:outline-none"
              >
              </div>
            </div>
          </div>
        </div>

        <%!-- Right Panel: Tabs --%>
        <div class="flex flex-col overflow-hidden">
          <div role="tablist" class="tabs tabs-bordered shrink-0 px-4 pt-2">
            <button
              type="button"
              role="tab"
              class={"tab #{if @active_tab == "responses", do: "tab-active"}"}
              phx-click="switch_tab"
              phx-value-tab="responses"
              phx-target={@myself}
            >
              {dgettext("flows", "Responses")}
              <span
                :if={length(@form[:responses].value || []) > 0}
                class="badge badge-xs badge-ghost ml-1"
              >
                {length(@form[:responses].value || [])}
              </span>
            </button>
            <button
              type="button"
              role="tab"
              class={"tab #{if @active_tab == "settings", do: "tab-active"}"}
              phx-click="switch_tab"
              phx-value-tab="settings"
              phx-target={@myself}
            >
              {dgettext("flows", "Settings")}
            </button>
          </div>

          <div class="flex-1 overflow-y-auto p-4">
            {render_tab(@active_tab, assigns)}
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
          <span :if={@audio_filename}>
            <.icon name="volume-2" class="size-3 inline mr-1" />
            {@audio_filename}
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

  # ---- Tabs ----

  defp render_tab("responses", assigns) do
    ~H"""
    <div class="space-y-3">
      <div
        :for={response <- @form[:responses].value || []}
        class="border border-base-300 rounded-lg p-3"
      >
        <div class="flex items-start gap-2">
          <.icon name="corner-down-right" class="size-4 mt-1 opacity-50 shrink-0" />
          <div class="flex-1 min-w-0">
            <input
              :if={@can_edit}
              type="text"
              value={response["text"] || ""}
              placeholder={dgettext("flows", "Response text… (use $ref for variables)")}
              phx-blur="update_response_text"
              phx-value-response-id={response["id"]}
              phx-value-node-id={@node.id}
              class="input input-sm input-bordered w-full"
            />
            <span :if={!@can_edit} class="text-sm">
              {response["text"] || dgettext("flows", "(empty response)")}
            </span>
          </div>
          <button
            :if={@can_edit}
            type="button"
            phx-click="remove_response"
            phx-value-response-id={response["id"]}
            phx-value-node-id={@node.id}
            class="btn btn-ghost btn-xs btn-square text-error"
          >
            <.icon name="trash-2" class="size-3.5" />
          </button>
        </div>

        <%!-- Advanced section (condition + instruction) --%>
        <details
          :if={@can_edit}
          class="mt-2"
          open={has_advanced?(response)}
        >
          <summary class="text-xs cursor-pointer select-none flex items-center gap-1 opacity-60 hover:opacity-100">
            <span
              :if={has_advanced?(response)}
              class="inline-block w-1.5 h-1.5 rounded-full bg-warning"
            >
            </span>
            {dgettext("flows", "Advanced")}
          </summary>
          <div class="mt-2 space-y-2 pl-6">
            <div>
              <label class="label text-xs">{dgettext("flows", "Condition")}</label>
              <.expression_editor
                id={"response-cond-expr-#{response["id"]}"}
                mode="condition"
                condition={response["condition"] || %{}}
                variables={@project_variables}
                can_edit={@can_edit}
                context={%{"response-id" => response["id"], "node-id" => to_string(@node.id)}}
                active_tab={
                  Map.get(@panel_sections, "tab_response-cond-expr-#{response["id"]}", "builder")
                }
              />
            </div>
            <div>
              <label class="label text-xs">{dgettext("flows", "Instruction")}</label>
              <.expression_editor
                id={"response-inst-expr-#{response["id"]}"}
                mode="instruction"
                assignments={response["instruction_assignments"] || []}
                variables={@project_variables}
                can_edit={@can_edit}
                context={%{"response-id" => response["id"], "node-id" => to_string(@node.id)}}
                event_name="update_response_instruction_builder"
                active_tab={
                  Map.get(@panel_sections, "tab_response-inst-expr-#{response["id"]}", "builder")
                }
              />
            </div>
          </div>
        </details>
      </div>

      <button
        :if={@can_edit}
        type="button"
        phx-click="add_response"
        phx-value-node-id={@node.id}
        class="btn btn-ghost btn-sm gap-1 w-full"
      >
        <.icon name="plus" class="size-4" />
        {dgettext("flows", "Add response")}
      </button>
    </div>
    """
  end

  defp render_tab("settings", assigns) do
    ~H"""
    <div class="space-y-4">
      <%!-- Menu Text --%>
      <div>
        <label class="label text-sm font-medium">{dgettext("flows", "Menu Text")}</label>
        <.form
          :if={@can_edit}
          for={@form}
          phx-change="update_menu_text"
          phx-debounce="500"
          phx-target={@myself}
        >
          <input
            type="text"
            name="menu_text"
            value={@form[:menu_text].value || ""}
            placeholder={dgettext("flows", "Short text shown in menus…")}
            class="input input-sm input-bordered w-full"
          />
        </.form>
        <span :if={!@can_edit} class="text-sm opacity-60">
          {@form[:menu_text].value || "-"}
        </span>
      </div>

      <%!-- Audio --%>
      <div>
        <label class="label text-sm font-medium">{dgettext("flows", "Audio")}</label>
        <.live_component
          module={StoryarnWeb.Components.AudioPicker}
          id={"screenplay-audio-picker-#{@node.id}"}
          asset_id={@node.data["audio_asset_id"]}
          project={@project}
          current_user={@current_user}
          can_edit={@can_edit}
        />
      </div>

      <%!-- Technical ID --%>
      <div>
        <label class="label text-sm font-medium">{dgettext("flows", "Technical ID")}</label>
        <div class="flex items-center gap-2">
          <.form
            :if={@can_edit}
            for={@form}
            phx-change="update_technical_id"
            phx-debounce="500"
            phx-target={@myself}
            class="flex-1"
          >
            <input
              type="text"
              name="technical_id"
              value={@form[:technical_id].value || ""}
              placeholder={dgettext("flows", "Auto-generated or custom")}
              class="input input-sm input-bordered w-full font-mono text-xs"
            />
          </.form>
          <button
            :if={@can_edit}
            type="button"
            phx-click="generate_technical_id"
            class="btn btn-ghost btn-sm btn-square"
            title={dgettext("flows", "Generate technical ID")}
          >
            <.icon name="refresh-cw" class="size-3.5" />
          </button>
        </div>
      </div>

      <%!-- Localization ID --%>
      <div>
        <label class="label text-sm font-medium">{dgettext("flows", "Localization ID")}</label>
        <div class="flex items-center gap-2">
          <.form
            :if={@can_edit}
            for={@form}
            phx-change="update_localization_id"
            phx-debounce="500"
            phx-target={@myself}
            class="flex-1"
          >
            <input
              type="text"
              name="localization_id"
              value={@form[:localization_id].value || ""}
              placeholder={dgettext("flows", "Localization key")}
              class="input input-sm input-bordered w-full font-mono text-xs"
            />
          </.form>
          <button
            :if={@form[:localization_id].value && @form[:localization_id].value != ""}
            type="button"
            class="btn btn-ghost btn-sm btn-square"
            data-copy-text={@form[:localization_id].value}
            title={dgettext("flows", "Copy to clipboard")}
          >
            <.icon name="copy" class="size-3.5" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp render_tab(_, assigns) do
    ~H""
  end

  # ---- Lifecycle ----

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:active_tab, fn -> "responses" end)
      |> assign_derived()

    {:ok, socket}
  end

  # ---- Events ----

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

  def handle_event("update_menu_text", %{"menu_text" => menu_text}, socket) do
    update_node_field(socket, "menu_text", menu_text)
  end

  def handle_event("update_technical_id", %{"technical_id" => technical_id}, socket) do
    update_node_field(socket, "technical_id", technical_id)
  end

  def handle_event("update_localization_id", %{"localization_id" => localization_id}, socket) do
    update_node_field(socket, "localization_id", localization_id)
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  # Proxy mention suggestions to parent (needs project context)
  def handle_event("mention_suggestions", %{"query" => query}, socket) do
    send(self(), {:mention_suggestions, query, socket.assigns.myself})
    {:noreply, socket}
  end

  # Proxy variable suggestions to parent (needs project context)
  def handle_event("variable_suggestions", %{"query" => query}, socket) do
    send(self(), {:variable_suggestions, query, socket.assigns.myself})
    {:noreply, socket}
  end

  # Proxy variable defaults resolution to parent
  def handle_event("resolve_variable_defaults", %{"refs" => refs}, socket) do
    send(self(), {:resolve_variable_defaults, refs, socket.assigns.myself})
    {:noreply, socket}
  end

  # ---- Private ----

  defp assign_derived(socket) do
    node = socket.assigns.node
    all_sheets = socket.assigns.all_sheets

    form = build_form(node)
    speaker_name = get_speaker_name(node, all_sheets)
    word_count = NodeTypeHelpers.word_count(node.data["text"])
    speaker_options = build_speaker_options(all_sheets)
    audio_filename = get_audio_filename(node)

    socket
    |> assign(:form, form)
    |> assign(:speaker_name, speaker_name)
    |> assign(:word_count, word_count)
    |> assign(:speaker_options, speaker_options)
    |> assign(:audio_filename, audio_filename)
  end

  defp build_form(node) do
    data = %{
      "speaker_sheet_id" => node.data["speaker_sheet_id"] || "",
      "text" => node.data["text"] || "",
      "stage_directions" => node.data["stage_directions"] || "",
      "menu_text" => node.data["menu_text"] || "",
      "technical_id" => node.data["technical_id"] || "",
      "localization_id" => node.data["localization_id"] || "",
      "responses" => node.data["responses"] || []
    }

    to_form(data, as: :screenplay)
  end

  defp update_node_field(%{assigns: %{can_edit: false}} = socket, _field, _value) do
    {:noreply, socket}
  end

  defp update_node_field(socket, field, value) do
    # Always read fresh from DB to avoid overwriting concurrent changes
    node = Flows.get_node!(socket.assigns.node.flow_id, socket.assigns.node.id)
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
    case Enum.find(all_sheets, fn sheet ->
           to_string(sheet.id) == to_string(speaker_sheet_id)
         end) do
      nil -> nil
      sheet -> sheet.name
    end
  end

  defp get_audio_filename(node) do
    case node.data["audio_asset_id"] do
      nil -> nil
      "" -> nil
      _id -> dgettext("flows", "Audio attached")
    end
  end

  defp has_advanced?(response), do: NodeTypeHelpers.response_has_advanced?(response)
end
