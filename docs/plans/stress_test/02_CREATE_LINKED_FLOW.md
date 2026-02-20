# Create Linked Flow from Exit/Subflow Nodes

> **Gap Reference:** Gap 3 QoL from `docs/plans/COMPLEX_NARRATIVE_STRESS_TEST.md`
>
> **Priority:** MEDIUM
>
> **Effort:** Low-Medium
>
> **Dependencies:** None
>
> **Previous:** [`01_NESTED_CONDITIONS.md`](./01_NESTED_CONDITIONS.md)
>
> **Next:** [`03_DIALOGUE_UX.md`](./03_DIALOGUE_UX.md)
>
> **Last Updated:** February 20, 2026

---

## Context and Current State

When building router-flow patterns (e.g., Annah's dialogue with 186 entry points routing to phase sub-flows), users currently need 6 manual steps to link exit/subflow nodes to new flows: create the flow separately in the sidebar tree, navigate back to the editor, select the node, open the sidebar, pick the flow from the dropdown, confirm. This should be a single-click operation.

### Current exit node workflow

1. User creates an exit node and sets `exit_mode` to `flow_reference`
2. Sidebar shows a `<select>` dropdown with all available flows in the project
3. User picks a flow from the dropdown
4. Exit node's `referenced_flow_id` is set
5. "Open Flow" button appears to navigate

**Problem:** There is no "Create new flow" option. If the target flow does not exist yet, the user must leave the editor, create the flow elsewhere, come back, and then assign it.

### Current subflow node workflow

1. User creates a subflow node
2. Sidebar shows a `<select>` dropdown with all available flows
3. User picks a flow
4. Subflow node's `referenced_flow_id` is set
5. "Open Subflow" button appears

Same problem: no inline flow creation.

### Key files (current state)

| File                                                                | Role                                                                                                                                                                                    |
|---------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `lib/storyarn_web/live/flow_live/nodes/exit/config_sidebar.ex`      | Exit node sidebar HEEx. Shows exit_mode radios, flow dropdown, "Open Flow" button. No "Create" button.                                                                                  |
| `lib/storyarn_web/live/flow_live/nodes/exit/node.ex`                | Exit node logic. `handle_update_exit_reference/2` validates flow ID, checks self-reference and circular reference. `on_select/2` loads `available_flows` when in `flow_reference` mode. |
| `lib/storyarn_web/live/flow_live/nodes/subflow/config_sidebar.ex`   | Subflow node sidebar HEEx. Shows flow dropdown, "Open Subflow" button. No "Create" button.                                                                                              |
| `lib/storyarn_web/live/flow_live/nodes/subflow/node.ex`             | Subflow node logic. `handle_update_reference/2` validates (no self-ref, no circular), persists, reloads `subflow_exits`. `on_select/2` loads `available_flows`.                         |
| `lib/storyarn/flows/flow_crud.ex`                                   | `create_flow/2` takes `%Project{}` + attrs (name, shortcut, description, parent_id, position). Auto-generates shortcut, auto-creates Entry+Exit nodes. Returns `{:ok, flow}`.           |
| `lib/storyarn_web/live/flow_live/handlers/generic_node_handlers.ex` | Generic event handlers. No `"create_linked_flow"` handler exists.                                                                                                                       |
| `lib/storyarn_web/live/flow_live/show.ex`                           | Event routing. Delegates exit events to `ExitNode.Node`, subflow events to `Subflow.Node`. Navigation via `NavigationHandlers.handle_navigate_to_flow/2`.                               |
| `lib/storyarn_web/live/flow_live/handlers/navigation_handlers.ex`   | `handle_navigate_to_flow/2` -- validates flow exists, then `push_navigate` with `?from=` param.                                                                                         |
| `lib/storyarn/flows.ex`                                             | Context facade. `defdelegate create_flow(project, attrs), to: FlowCrud`.                                                                                                                |

---

## Subtask 1: Backend -- `create_linked_flow/4` in `flow_crud.ex`

### Description

Add a new function to `FlowCrud` that creates a flow as a child of the current flow in the tree and immediately assigns it to a node's `referenced_flow_id`. This is a single-transaction operation that ensures atomicity: if the flow creation succeeds but the node update fails, neither persists.

### Files Affected

- `lib/storyarn/flows/flow_crud.ex` -- add `create_linked_flow/4`
- `lib/storyarn/flows.ex` -- add `defdelegate`

### Implementation Steps

**1.1. Add `create_linked_flow/4` to `flow_crud.ex`**

```elixir
@doc """
Creates a new flow as a child of parent_flow and assigns it to a node.

The new flow is created with:
- `parent_id` set to the parent flow's ID (child in tree)
- `name` derived from the node's label or a default
- Auto-generated shortcut and position

The node's `referenced_flow_id` is set to the new flow's ID.

Returns `{:ok, %{flow: flow, node: node}}` or `{:error, changeset}`.
"""
@spec create_linked_flow(Project.t(), Flow.t(), FlowNode.t(), map()) ::
        {:ok, %{flow: Flow.t(), node: FlowNode.t()}} | {:error, any()}
def create_linked_flow(%Project{} = project, %Flow{} = parent_flow, %FlowNode{} = node, attrs \\ %{}) do
  attrs = stringify_keys(attrs)

  # Derive name: use provided name, or node label, or parent flow name + suffix
  name = derive_linked_flow_name(attrs, node, parent_flow)
  attrs = Map.put(attrs, "name", name)

  # Set parent_id to current flow (child in the tree hierarchy)
  attrs = Map.put(attrs, "parent_id", parent_flow.id)

  Repo.transaction(fn ->
    # Create the flow (auto-generates shortcut, Entry+Exit nodes)
    case create_flow(project, attrs) do
      {:ok, new_flow} ->
        # Update the node's referenced_flow_id
        case node
             |> Ecto.Changeset.change(%{data: Map.put(node.data || %{}, "referenced_flow_id", new_flow.id)})
             |> Repo.update() do
          {:ok, updated_node} ->
            %{flow: new_flow, node: updated_node}

          {:error, changeset} ->
            Repo.rollback(changeset)
        end

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end)
end

defp derive_linked_flow_name(attrs, node, parent_flow) do
  cond do
    # Explicit name provided
    attrs["name"] && attrs["name"] != "" ->
      attrs["name"]

    # Use node label if present
    label = node.data["label"] ->
      if label != "", do: label, else: "#{parent_flow.name} - Sub"

    # Fallback: parent flow name + suffix
    true ->
      "#{parent_flow.name} - Sub"
  end
end
```

**1.2. Add delegate to `flows.ex`**

Add after the existing `create_flow` delegate:

```elixir
@doc """
Creates a new flow linked to a node. See `FlowCrud.create_linked_flow/4`.
"""
defdelegate create_linked_flow(project, parent_flow, node, attrs \\ %{}), to: FlowCrud
```

### Test Battery

Create `test/storyarn/flows/flow_crud_test.exs`:

```elixir
defmodule Storyarn.Flows.FlowCrudTest do
  use Storyarn.DataCase

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.FlowsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.FlowCrud

  describe "create_linked_flow/4" do
    setup do
      user = user_fixture()
      workspace = workspace_fixture(user)
      project = project_fixture(workspace)
      flow = flow_fixture(project)
      {:ok, project: project, flow: flow}
    end

    test "creates child flow and assigns to exit node", %{project: project, flow: flow} do
      # Create an exit node in flow_reference mode
      {:ok, node} = Flows.create_node(flow, %{
        type: "exit",
        position_x: 500.0,
        position_y: 300.0,
        data: %{"exit_mode" => "flow_reference", "referenced_flow_id" => nil, "label" => "Victory"}
      })

      assert {:ok, %{flow: new_flow, node: updated_node}} =
               FlowCrud.create_linked_flow(project, flow, node)

      # New flow is a child of the parent flow
      assert new_flow.parent_id == flow.id

      # New flow name derived from node label
      assert new_flow.name == "Victory"

      # Node references the new flow
      assert updated_node.data["referenced_flow_id"] == new_flow.id

      # New flow has Entry + Exit nodes (auto-created)
      nodes = Flows.list_nodes(new_flow.id)
      assert length(nodes) == 2
      types = Enum.map(nodes, & &1.type) |> Enum.sort()
      assert types == ["entry", "exit"]
    end

    test "uses fallback name when node has no label", %{project: project, flow: flow} do
      {:ok, node} = Flows.create_node(flow, %{
        type: "subflow",
        position_x: 300.0,
        position_y: 300.0,
        data: %{"referenced_flow_id" => nil}
      })

      assert {:ok, %{flow: new_flow}} =
               FlowCrud.create_linked_flow(project, flow, node)

      assert new_flow.name == "#{flow.name} - Sub"
    end

    test "uses explicit name when provided", %{project: project, flow: flow} do
      {:ok, node} = Flows.create_node(flow, %{
        type: "exit",
        position_x: 500.0,
        position_y: 300.0,
        data: %{"exit_mode" => "flow_reference", "label" => "Victory"}
      })

      assert {:ok, %{flow: new_flow}} =
               FlowCrud.create_linked_flow(project, flow, node, %{"name" => "Custom Name"})

      assert new_flow.name == "Custom Name"
    end

    test "auto-generates shortcut for new flow", %{project: project, flow: flow} do
      {:ok, node} = Flows.create_node(flow, %{
        type: "exit",
        position_x: 500.0,
        position_y: 300.0,
        data: %{"exit_mode" => "flow_reference", "label" => "Phase One"}
      })

      assert {:ok, %{flow: new_flow}} =
               FlowCrud.create_linked_flow(project, flow, node)

      assert new_flow.shortcut != nil
      assert new_flow.shortcut != ""
    end
  end
end
```

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 2: Event Handler in `show.ex`

### Description

Add a `"create_linked_flow"` event handler that creates the linked flow via the backend function and either navigates to the new flow or stays on the current canvas (user's choice communicated via a param). This handler is used by both exit and subflow sidebar buttons.

### Files Affected

- `lib/storyarn_web/live/flow_live/show.ex` -- add `handle_event("create_linked_flow", ...)`

### Implementation Steps

**2.1. Add event handler to `show.ex`**

Add after the existing exit node events block (around line 564):

```elixir
def handle_event("create_linked_flow", %{"node-id" => node_id_str} = params, socket) do
  with_auth(:edit_content, socket, fn ->
    handle_create_linked_flow(node_id_str, params, socket)
  end)
end
```

**2.2. Implement `handle_create_linked_flow/3` as a private function in `show.ex`**

```elixir
defp handle_create_linked_flow(node_id_str, params, socket) do
  case Integer.parse(node_id_str) do
    {node_id, ""} ->
      node = Flows.get_node!(socket.assigns.flow.id, node_id)
      project = socket.assigns.project
      flow = socket.assigns.flow

      # Optional name override from params
      attrs = if params["name"] && params["name"] != "", do: %{"name" => params["name"]}, else: %{}

      case Flows.create_linked_flow(project, flow, node, attrs) do
        {:ok, %{flow: new_flow, node: updated_node}} ->
          navigate? = params["navigate"] != "false"

          if navigate? do
            {:noreply,
             push_navigate(socket,
               to:
                 ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{new_flow.id}?from=#{socket.assigns.flow.id}"
             )}
          else
            # Stay on canvas, refresh sidebar
            form = FormHelpers.node_data_to_form(updated_node)

            socket =
              socket
              |> reload_flow_data()
              |> assign(:selected_node, updated_node)
              |> assign(:node_form, form)
              |> assign(:save_status, :saved)
              |> put_flash(:info, dgettext("flows", "Flow \"%{name}\" created.", name: new_flow.name))

            # Reload available_flows for the sidebar dropdown
            available_flows =
              Flows.list_flows(project.id)
              |> Enum.reject(&(&1.id == flow.id))

            socket = assign(socket, :available_flows, available_flows)

            # For subflow nodes, also reload exit nodes
            socket =
              if updated_node.type == "subflow" do
                exit_nodes = Flows.list_exit_nodes_for_flow(new_flow.id)
                assign(socket, :subflow_exits, exit_nodes)
              else
                socket
              end

            {:noreply, socket}
          end

        {:error, changeset} ->
          error_msg =
            case changeset do
              %Ecto.Changeset{} -> dgettext("flows", "Could not create flow.")
              _ -> dgettext("flows", "Could not create flow.")
            end

          {:noreply, put_flash(socket, :error, error_msg)}
      end

    _ ->
      {:noreply, put_flash(socket, :error, dgettext("flows", "Invalid node ID."))}
  end
end
```

**2.3. Import `reload_flow_data` if not already available**

The `show.ex` already imports `StoryarnWeb.FlowLive.Helpers.SocketHelpers` (which contains `reload_flow_data/1`) via the generic node handlers. Verify this is available in the private function scope. If not, add `import StoryarnWeb.FlowLive.Helpers.SocketHelpers` at the module level.

### Test Battery

Add to `test/storyarn_web/live/flow_live/show_events_test.exs`:

```elixir
describe "create_linked_flow handler" do
  test "show.ex handles 'create_linked_flow' event" do
    # Verify the event is routed (structural test)
    # The actual integration test would require a full LiveView mount
    module = StoryarnWeb.FlowLive.Show
    Code.ensure_loaded!(module)

    # Verify the module compiles with the new handler
    assert {:module, ^module} = Code.ensure_compiled(module)
  end
end
```

A full LiveView integration test (mounting the LiveView, creating a node, clicking the button) is valuable but requires project/workspace/flow fixtures with a mounted LiveView. Follow the pattern in existing tests if fixtures are available.

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 3: Exit Node Sidebar -- "Create New Flow" Button

### Description

Add a "Create new flow" button to the exit node sidebar. It appears when `exit_mode` is `flow_reference` and no flow is currently selected. After clicking, the server creates a child flow and navigates the user to it.

### Files Affected

- `lib/storyarn_web/live/flow_live/nodes/exit/config_sidebar.ex` -- add button

### Implementation Steps

**3.1. Add the button to the sidebar HEEx**

Insert after the `<select>` dropdown and before the stale reference alert. The button appears when:
- `exit_mode == "flow_reference"` (already inside the `:if` guard)
- No flow is selected (`@current_ref_str == ""`)
- User can edit (`@can_edit`)

In `config_sidebar.ex`, inside the `<div :if={@exit_mode == "flow_reference"}>` block, after the `</form>` for the select, add:

```heex
<%!-- Create New Flow button (when no flow selected) --%>
<button
  :if={@can_edit && @current_ref_str == ""}
  type="button"
  class="btn btn-ghost btn-xs w-full mt-2 border border-dashed border-base-300"
  phx-click="create_linked_flow"
  phx-value-node-id={@node.id}
  phx-value-navigate="true"
>
  <.icon name="plus" class="size-3 mr-1" />
  {dgettext("flows", "Create new flow")}
</button>
```

**3.2. The button uses the exit node's label as the flow name**

The `create_linked_flow` handler in show.ex already derives the name from the node's label (`node.data["label"]`). If the exit node has a label like "Victory", the new flow will be named "Victory". If no label, it falls back to "Parent Flow Name - Sub".

**3.3. After creation, user navigates to the new flow**

The `navigate="true"` param tells the handler to `push_navigate`. When the user returns (via the "Back" button or `?from=` param), the exit node will already have `referenced_flow_id` set, and the sidebar will show the dropdown with the new flow selected plus the "Open Flow" button.

### Test Battery

Manual verification:

1. Create an exit node
2. Set exit_mode to "flow_reference"
3. Verify "Create new flow" button appears below the empty dropdown
4. Click the button
5. Verify navigation to the new flow
6. Verify the new flow is a child of the original flow in the sidebar tree
7. Click "Back" to return to the original flow
8. Verify the exit node now shows the new flow selected in the dropdown
9. Verify "Create new flow" button is now hidden (flow is selected)
10. Verify "Open Flow" button is visible

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 4: Subflow Node Sidebar -- "Create New Flow" Button

### Description

Add the same "Create new flow" button to the subflow node sidebar. It appears when no flow is currently selected. Follows the same pattern as the exit node button.

### Files Affected

- `lib/storyarn_web/live/flow_live/nodes/subflow/config_sidebar.ex` -- add button

### Implementation Steps

**4.1. Add the button to the sidebar HEEx**

In `config_sidebar.ex`, after the `</form>` for the select dropdown and the help text paragraph, add:

```heex
<%!-- Create New Flow button (when no flow selected) --%>
<button
  :if={@can_edit && @current_ref_str == ""}
  type="button"
  class="btn btn-ghost btn-xs w-full mt-2 border border-dashed border-base-300"
  phx-click="create_linked_flow"
  phx-value-node-id={@node.id}
  phx-value-navigate="true"
>
  <.icon name="plus" class="size-3 mr-1" />
  {dgettext("flows", "Create new flow")}
</button>
```

**4.2. Name derivation for subflow nodes**

Subflow nodes have `default_data` of `%{"referenced_flow_id" => nil}` -- they do not have a `"label"` field. The `derive_linked_flow_name/3` function in `flow_crud.ex` will fall through to the `node.data["label"]` check (which returns `nil`), and then to the fallback `"#{parent_flow.name} - Sub"`. This is acceptable. Users can rename the flow after creation.

**4.3. After creation + navigation**

When the user returns from the new flow, the subflow node will have `referenced_flow_id` set, and the sidebar will show:
- The dropdown with the new flow selected
- Exit nodes section (initially just the auto-created Exit node)
- "Open Subflow" button
- "Create new flow" button hidden (flow is selected)

### Test Battery

Manual verification:

1. Create a subflow node
2. Verify "Create new flow" button appears below the dropdown
3. Click the button
4. Verify navigation to the new flow
5. Verify the new flow is a child of the original flow in the tree
6. Return to the original flow
7. Verify the subflow node now shows the new flow selected
8. Verify "Create new flow" button is hidden
9. Verify "Open Subflow" button is visible
10. Verify exit nodes section shows the default Exit node

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 5: Gettext + Sidebar Tree Refresh

### Description

Ensure all new strings are extracted for i18n, and that the sidebar flow tree updates after a linked flow is created (so the new child flow appears immediately in the tree without a page refresh).

### Files Affected

- `priv/gettext/en/LC_MESSAGES/flows.po` -- new strings
- `priv/gettext/es/LC_MESSAGES/flows.po` -- new strings (translations can be added later)
- `lib/storyarn_web/live/flow_live/show.ex` -- sidebar tree refresh

### Implementation Steps

**5.1. Extract gettext strings**

Run:
```bash
mix gettext.extract --merge
```

New strings to expect:
- `"Create new flow"` -- button label on exit and subflow sidebars
- `"Flow \"%{name}\" created."` -- flash message on non-navigate create

**5.2. Sidebar tree refresh after linked flow creation**

When `navigate="true"`, the user navigates away and the target page loads a fresh tree. No refresh needed.

When `navigate="false"` (if we add that option later), the sidebar tree on the current page should update. The existing `reload_flow_data/1` in `SocketHelpers` reloads the flow and its nodes but not the sidebar tree. To refresh the sidebar tree, we would need to broadcast a `project_updated` event or re-assign `flows_tree`. For now, since the default behavior is to navigate, this is not needed. If the non-navigate path is used in the future, add:

```elixir
# In the navigate=false branch of handle_create_linked_flow:
|> assign(:flows_tree, Flows.list_flows_tree(project.id))
```

**5.3. Verify tree position**

The new flow is created as a child of the current flow. `create_flow/2` calls `maybe_assign_position/3` which uses `TreeOperations.next_position/2` to place it after the last sibling. This works automatically.

### Test Battery

```elixir
# In flow_crud_test.exs, add:
test "linked flow gets correct tree position", %{project: project, flow: flow} do
  {:ok, node} = Flows.create_node(flow, %{
    type: "exit",
    position_x: 500.0,
    position_y: 300.0,
    data: %{"exit_mode" => "flow_reference", "label" => "First"}
  })

  {:ok, node2} = Flows.create_node(flow, %{
    type: "exit",
    position_x: 700.0,
    position_y: 300.0,
    data: %{"exit_mode" => "flow_reference", "label" => "Second"}
  })

  {:ok, %{flow: flow1}} = FlowCrud.create_linked_flow(project, flow, node)
  {:ok, %{flow: flow2}} = FlowCrud.create_linked_flow(project, flow, node2)

  # Both are children of the parent flow
  assert flow1.parent_id == flow.id
  assert flow2.parent_id == flow.id

  # Second has a higher position
  assert flow2.position > flow1.position
end
```

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Summary of All Files Affected

### Backend (Elixir)

| File                                                              | Change Type                                                                   |
|-------------------------------------------------------------------|-------------------------------------------------------------------------------|
| `lib/storyarn/flows/flow_crud.ex`                                 | Modified -- add `create_linked_flow/4` and `derive_linked_flow_name/3`        |
| `lib/storyarn/flows.ex`                                           | Modified -- add `defdelegate create_linked_flow`                              |
| `lib/storyarn_web/live/flow_live/show.ex`                         | Modified -- add `handle_event("create_linked_flow", ...)` and private handler |
| `lib/storyarn_web/live/flow_live/nodes/exit/config_sidebar.ex`    | Modified -- add "Create new flow" button                                      |
| `lib/storyarn_web/live/flow_live/nodes/subflow/config_sidebar.ex` | Modified -- add "Create new flow" button                                      |

### Tests

| File                                                    | Change Type                                 |
|---------------------------------------------------------|---------------------------------------------|
| `test/storyarn/flows/flow_crud_test.exs`                | New -- tests for `create_linked_flow/4`     |
| `test/storyarn_web/live/flow_live/show_events_test.exs` | Modified -- structural test for new handler |

### Gettext

| File                                   | Change Type                      |
|----------------------------------------|----------------------------------|
| `priv/gettext/en/LC_MESSAGES/flows.po` | Modified -- new translation keys |
| `priv/gettext/es/LC_MESSAGES/flows.po` | Modified -- new translation keys |

### Files NOT Changed

| File                                                                | Reason                                                                                                      |
|---------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------|
| `lib/storyarn_web/live/flow_live/nodes/exit/node.ex`                | No new handlers needed -- existing `handle_update_exit_reference/2` handles the post-creation state         |
| `lib/storyarn_web/live/flow_live/nodes/subflow/node.ex`             | Same -- existing `handle_update_reference/2` handles post-creation state                                    |
| `lib/storyarn_web/live/flow_live/handlers/generic_node_handlers.ex` | Handler lives in `show.ex` directly (it uses navigation + socket assigns not available in generic handlers) |
| `lib/storyarn_web/live/flow_live/handlers/navigation_handlers.ex`   | Existing `handle_navigate_to_flow/2` is reused (same navigation pattern)                                    |

---

**Next:** [`03_DIALOGUE_UX.md`](./03_DIALOGUE_UX.md)
