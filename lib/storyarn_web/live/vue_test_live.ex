defmodule StoryarnWeb.VueTestLive do
  use StoryarnWeb, :live_view

  @variables [
    %{sheet_shortcut: "main-characters", sheet_name: "Main Characters", variable_name: "health_points", block_type: "number", options: nil},
    %{sheet_shortcut: "main-characters", sheet_name: "Main Characters", variable_name: "faction", block_type: "select", options: [%{key: "alliance", value: "Alliance"}, %{key: "horde", value: "Horde"}, %{key: "neutral", value: "Neutral"}]},
    %{sheet_shortcut: "main-characters", sheet_name: "Main Characters", variable_name: "is_alive", block_type: "boolean", options: nil},
    %{sheet_shortcut: "main-characters", sheet_name: "Main Characters", variable_name: "bio", block_type: "text", options: nil},
    %{sheet_shortcut: "world-state", sheet_name: "World State", variable_name: "chapter", block_type: "number", options: nil},
    %{sheet_shortcut: "world-state", sheet_name: "World State", variable_name: "quest_status", block_type: "text", options: nil},
    %{sheet_shortcut: "world-state", sheet_name: "World State", variable_name: "difficulty", block_type: "select", options: [%{key: "easy", value: "Easy"}, %{key: "normal", value: "Normal"}, %{key: "hard", value: "Hard"}]}
  ]

  # Fake project/workspace for layout demo
  @demo_project %{name: "Veilbreak", slug: "veilbreak", settings: %{}}
  @demo_workspace %{name: "My Workspace", slug: "my-workspace"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket,
      count: 0,
      variables: @variables,
      tree_panel_open: false,
      tree_panel_pinned: false,
      condition: %{
        logic: "all",
        blocks: [
          %{
            id: "block_1",
            type: "block",
            logic: "all",
            rules: [
              %{id: "rule_1", sheet: "main-characters", variable: "health_points", operator: "greater_than", value: "50"},
              %{id: "rule_2", sheet: "main-characters", variable: "is_alive", operator: "is_true", value: nil}
            ]
          },
          %{
            id: "block_2",
            type: "block",
            logic: "all",
            rules: [
              %{id: "rule_3", sheet: "world-state", variable: "chapter", operator: "equals", value: "3"}
            ]
          }
        ]
      },
      assignments: [
        %{operator: "add", sheet: "main-characters", variable: "health_points", value_type: "literal", value: "10", value_sheet: nil},
        %{operator: "set", sheet: "world-state", variable: "chapter", value_type: "literal", value: "3", value_sheet: nil},
        %{operator: "set_true", sheet: "main-characters", variable: "is_alive", value_type: "literal", value: nil, value_sheet: nil}
      ]
    )}
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:project, @demo_project)
      |> assign(:workspace, @demo_workspace)

    ~H"""
    <Layouts.focus_v2
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      active_tool={:sheets}
      has_tree={true}
      tree_panel_open={@tree_panel_open}
      tree_panel_pinned={@tree_panel_pinned}
      can_edit={true}
      online_users={[]}
    >
      <:tree_content>
        <div class="text-sm text-muted-foreground p-2">
          <p class="font-medium text-foreground mb-2">Tree content placeholder</p>
          <p>Sheet tree, flow tree, etc. will go here.</p>
        </div>
      </:tree_content>

      <div class="max-w-2xl mx-auto space-y-10">
        <h1 class="text-2xl font-bold">Vue Component Showcase</h1>

        <%!-- LiveView reactivity test --%>
        <section class="space-y-2">
          <h2 class="text-lg font-semibold border-b border-border pb-2">LiveView Reactivity</h2>
          <p class="text-sm text-muted-foreground">Server count: {@count}</p>
          <.vue v-component="HelloVue" message={"Count is #{@count}"} v-socket={@socket} id="hello-vue" />
          <button phx-click="inc" class="mt-2 px-3 py-1.5 text-sm bg-primary text-primary-foreground rounded">
            Increment from server
          </button>
        </section>

        <%!-- ExpressionEditor: Condition (Builder + Code tabs) --%>
        <section class="space-y-4">
          <h2 class="text-lg font-semibold border-b border-border pb-2">Condition Builder</h2>
          <div style="max-width: 520px; margin: 0 auto;" class="space-y-8">
            <div class="rounded-lg border border-border p-4">
              <h3 class="text-sm font-medium text-muted-foreground mb-3">Empty</h3>
              <.vue v-component="ExpressionEditor" v-socket={@socket} id="ce-empty"
                mode="condition" condition={nil} variables={@variables} disabled={false} />
            </div>
            <div class="rounded-lg border border-border p-4">
              <h3 class="text-sm font-medium text-muted-foreground mb-3">With rules</h3>
              <.vue v-component="ExpressionEditor" v-socket={@socket} id="ce-rules"
                mode="condition" condition={@condition} variables={@variables} disabled={false} />
            </div>
            <div class="rounded-lg border border-border p-4">
              <h3 class="text-sm font-medium text-muted-foreground mb-3">Disabled</h3>
              <.vue v-component="ExpressionEditor" v-socket={@socket} id="ce-disabled"
                mode="condition" condition={@condition} variables={@variables} disabled={true} />
            </div>
          </div>
        </section>

        <%!-- ExpressionEditor: Instruction (Builder + Code tabs) --%>
        <section class="space-y-4">
          <h2 class="text-lg font-semibold border-b border-border pb-2">Instruction Builder</h2>
          <div style="max-width: 520px; margin: 0 auto;" class="space-y-8">
            <div class="rounded-lg border border-border p-4">
              <h3 class="text-sm font-medium text-muted-foreground mb-3">Empty</h3>
              <.vue v-component="ExpressionEditor" v-socket={@socket} id="ie-empty"
                mode="instruction" assignments={[]} variables={@variables} disabled={false} />
            </div>
            <div class="rounded-lg border border-border p-4">
              <h3 class="text-sm font-medium text-muted-foreground mb-3">With assignments</h3>
              <.vue v-component="ExpressionEditor" v-socket={@socket} id="ie-assignments"
                mode="instruction" assignments={@assignments} variables={@variables} disabled={false} />
            </div>
            <div class="rounded-lg border border-border p-4">
              <h3 class="text-sm font-medium text-muted-foreground mb-3">Disabled</h3>
              <.vue v-component="ExpressionEditor" v-socket={@socket} id="ie-disabled"
                mode="instruction" assignments={@assignments} variables={@variables} disabled={true} />
            </div>
          </div>
        </section>
      </div>
    </Layouts.focus_v2>
    """
  end

  @impl true
  def handle_event("inc", _params, socket) do
    {:noreply, assign(socket, :count, socket.assigns.count + 1)}
  end

  def handle_event("tree_panel_toggle", _params, socket) do
    {:noreply, assign(socket, :tree_panel_open, !socket.assigns.tree_panel_open)}
  end

  def handle_event("tree_panel_pin", _params, socket) do
    {:noreply, assign(socket, :tree_panel_pinned, !socket.assigns.tree_panel_pinned)}
  end

  def handle_event("tree_panel_init", %{"pinned" => pinned}, socket) do
    open = pinned || socket.assigns.tree_panel_open

    {:noreply,
     socket
     |> assign(:tree_panel_pinned, pinned)
     |> assign(:tree_panel_open, open)}
  end
end
