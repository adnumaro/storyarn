# 09 Cross-flow Navigation History

> **Gap:** 6d -- Cross-flow Navigation History
> **Priority:** MEDIUM | **Effort:** Low
> **Dependencies:** Flow editor (implemented), Navigation handlers (implemented)
> **Previous:** `08_VARIABLE_USAGE_INDEX.md` | **Next:** `10_DEBUGGER_STEP_LIMIT.md`
> **Last Updated:** February 20, 2026

---

## Context and Current State

### What exists today

**Navigation between flows** currently uses `push_navigate` with a `from` query parameter that stores the previous flow's ID. This enables a single-step "back" link in the flow header.

Key files and patterns:

- **Show LiveView:** `/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn_web/live/flow_live/show.ex`
  - `handle_params/3` (line 260) calls `maybe_set_from_flow(params["from"])` which resolves the `from` ID into a flow struct and assigns it as `@from_flow`.
  - Mount assigns `from_flow: nil` (line 198).

- **Flow Header:** `/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn_web/live/flow_live/components/flow_header.ex`
  - Lines 36--44: Renders a "back" link when `@from_flow` is set:
    ```elixir
    <.link :if={@from_flow}
      navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows/#{@from_flow.id}"}
      class="btn btn-ghost btn-sm gap-1 text-base-content/60">
      <.icon name="corner-up-left" class="size-3" />
      {@from_flow.name}
    </.link>
    ```

- **Navigation Handlers:** `/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn_web/live/flow_live/handlers/navigation_handlers.ex`
  - `handle_navigate_to_flow/2` (line 18) uses `push_navigate` with `?from=#{socket.assigns.flow.id}`.

- **Generic Node Handlers:** `/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn_web/live/flow_live/handlers/generic_node_handlers.ex`
  - `handle_node_double_clicked/2` (line 155) handles `{:navigate, flow_id}` by calling `push_navigate` with `?from=#{socket.assigns.flow.id}`.

- **Debug Execution Handlers:** `/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn_web/live/flow_live/handlers/debug_execution_handlers.ex`
  - `store_and_navigate/2` (line 137) navigates to a target flow during debug sessions (no `from` param -- debug has its own call_stack breadcrumb).

### What is missing

1. **No navigation history stack.** The `from` parameter only tracks one level back. If a designer navigates: Flow A -> Flow B -> Flow C, clicking "back" from C goes to B, but there is no way to continue back to A.

2. **No forward navigation.** After going back, the designer cannot go forward again.

3. **No breadcrumb trail.** The designer sees only the immediate previous flow name, not the full path they took.

4. **No keyboard shortcuts.** Narrative designers expect Alt+Left/Alt+Right (or Cmd+[ / Cmd+]) for back/forward, similar to browser navigation or IDE behavior.

### Design

Add a navigation history stack stored in socket assigns. The stack is a list of `%{flow_id, flow_name}` tuples with a cursor index. Back/forward buttons in the flow header. Optional breadcrumb display. Keyboard shortcuts via a JS hook. Maximum 20 entries to prevent unbounded growth.

The history persists within the LiveView session but is not stored in the database. Closing the flow editor discards the history (same pattern as `debug_state`).

---

## Subtask 1: Backend -- Navigation History Stack in Socket Assigns

### Description

Add navigation history tracking to the flow editor's socket assigns. The history is a simple list-with-cursor data structure: `nav_history` (list of `%{flow_id, flow_name}` maps) and `nav_history_index` (current position in the list, 0-based).

### Files Affected

| File                                                                   | Action            |
|------------------------------------------------------------------------|-------------------|
| `lib/storyarn_web/live/flow_live/helpers/navigation_history.ex`        | Create new module |
| `test/storyarn_web/live/flow_live/helpers/navigation_history_test.exs` | Create tests      |

### Implementation Steps

1. **Create `navigation_history.ex`** -- a pure functional module (no DB, no socket, just data):

```elixir
defmodule StoryarnWeb.FlowLive.Helpers.NavigationHistory do
  @moduledoc """
  Pure functional navigation history stack for the flow editor.

  Stores a list of visited flows and a cursor index. Supports push,
  back, and forward operations. Maximum 20 entries.
  """

  @max_entries 20

  @type entry :: %{flow_id: integer(), flow_name: String.t()}
  @type t :: %{entries: [entry()], index: non_neg_integer()}

  @doc """
  Creates a new history with the initial flow as the only entry.
  """
  @spec new(integer(), String.t()) :: t()
  def new(flow_id, flow_name) do
    %{
      entries: [%{flow_id: flow_id, flow_name: flow_name}],
      index: 0
    }
  end

  @doc """
  Push a new flow onto the history.

  If the cursor is not at the end (i.e., user went back), the forward
  entries are discarded (same as browser navigation). The list is
  truncated to @max_entries from the front if it exceeds the limit.
  """
  @spec push(t(), integer(), String.t()) :: t()
  def push(history, flow_id, flow_name) do
    # Don't push if it's the same flow we're currently on
    current = Enum.at(history.entries, history.index)

    if current && current.flow_id == flow_id do
      history
    else
      # Discard forward entries
      entries = Enum.take(history.entries, history.index + 1)
      new_entry = %{flow_id: flow_id, flow_name: flow_name}
      entries = entries ++ [new_entry]

      # Truncate from the front if too long
      entries =
        if length(entries) > @max_entries do
          Enum.drop(entries, length(entries) - @max_entries)
        else
          entries
        end

      %{entries: entries, index: length(entries) - 1}
    end
  end

  @doc """
  Move back one entry. Returns `{:ok, entry, updated_history}` or `:at_start`.
  """
  @spec back(t()) :: {:ok, entry(), t()} | :at_start
  def back(%{index: 0}), do: :at_start

  def back(%{entries: entries, index: index} = history) do
    new_index = index - 1
    entry = Enum.at(entries, new_index)
    {:ok, entry, %{history | index: new_index}}
  end

  @doc """
  Move forward one entry. Returns `{:ok, entry, updated_history}` or `:at_end`.
  """
  @spec forward(t()) :: {:ok, entry(), t()} | :at_end
  def forward(%{entries: entries, index: index}) when index >= length(entries) - 1 do
    :at_end
  end

  def forward(%{entries: entries, index: index} = history) do
    new_index = index + 1
    entry = Enum.at(entries, new_index)
    {:ok, entry, %{history | index: new_index}}
  end

  @doc """
  Returns true if back navigation is possible.
  """
  @spec can_go_back?(t()) :: boolean()
  def can_go_back?(%{index: 0}), do: false
  def can_go_back?(_), do: true

  @doc """
  Returns true if forward navigation is possible.
  """
  @spec can_go_forward?(t()) :: boolean()
  def can_go_forward?(%{entries: entries, index: index}) do
    index < length(entries) - 1
  end

  @doc """
  Returns the current entry.
  """
  @spec current(t()) :: entry()
  def current(%{entries: entries, index: index}) do
    Enum.at(entries, index)
  end

  @doc """
  Returns the entries as a breadcrumb list up to the current index.
  """
  @spec breadcrumbs(t()) :: [entry()]
  def breadcrumbs(%{entries: entries, index: index}) do
    Enum.take(entries, index + 1)
  end
end
```

### Test Battery

```elixir
defmodule StoryarnWeb.FlowLive.Helpers.NavigationHistoryTest do
  use ExUnit.Case, async: true

  alias StoryarnWeb.FlowLive.Helpers.NavigationHistory

  describe "new/2" do
    test "creates history with single entry" do
      history = NavigationHistory.new(1, "Flow A")
      assert history.index == 0
      assert length(history.entries) == 1
      assert NavigationHistory.current(history).flow_id == 1
    end
  end

  describe "push/3" do
    test "appends new entry" do
      history = NavigationHistory.new(1, "Flow A")
      history = NavigationHistory.push(history, 2, "Flow B")

      assert history.index == 1
      assert length(history.entries) == 2
      assert NavigationHistory.current(history).flow_id == 2
    end

    test "does not duplicate current flow" do
      history = NavigationHistory.new(1, "Flow A")
      history = NavigationHistory.push(history, 1, "Flow A")

      assert history.index == 0
      assert length(history.entries) == 1
    end

    test "discards forward entries when pushing after back" do
      history = NavigationHistory.new(1, "A")
      history = NavigationHistory.push(history, 2, "B")
      history = NavigationHistory.push(history, 3, "C")

      {:ok, _entry, history} = NavigationHistory.back(history)
      # Now at B, push D -- C should be discarded
      history = NavigationHistory.push(history, 4, "D")

      assert length(history.entries) == 3
      ids = Enum.map(history.entries, & &1.flow_id)
      assert ids == [1, 2, 4]
      assert history.index == 2
    end

    test "truncates to 20 entries" do
      history = NavigationHistory.new(0, "F0")

      history =
        Enum.reduce(1..25, history, fn i, h ->
          NavigationHistory.push(h, i, "F#{i}")
        end)

      assert length(history.entries) == 20
      assert history.index == 19
      # Oldest entries should have been dropped
      assert hd(history.entries).flow_id == 6
    end
  end

  describe "back/1" do
    test "moves cursor back" do
      history = NavigationHistory.new(1, "A")
      history = NavigationHistory.push(history, 2, "B")

      {:ok, entry, history} = NavigationHistory.back(history)

      assert entry.flow_id == 1
      assert history.index == 0
    end

    test "returns :at_start when already at beginning" do
      history = NavigationHistory.new(1, "A")
      assert :at_start = NavigationHistory.back(history)
    end
  end

  describe "forward/1" do
    test "moves cursor forward" do
      history = NavigationHistory.new(1, "A")
      history = NavigationHistory.push(history, 2, "B")
      {:ok, _entry, history} = NavigationHistory.back(history)

      {:ok, entry, history} = NavigationHistory.forward(history)

      assert entry.flow_id == 2
      assert history.index == 1
    end

    test "returns :at_end when already at end" do
      history = NavigationHistory.new(1, "A")
      assert :at_end = NavigationHistory.forward(history)
    end
  end

  describe "can_go_back?/1 and can_go_forward?/1" do
    test "reports availability correctly" do
      history = NavigationHistory.new(1, "A")
      refute NavigationHistory.can_go_back?(history)
      refute NavigationHistory.can_go_forward?(history)

      history = NavigationHistory.push(history, 2, "B")
      assert NavigationHistory.can_go_back?(history)
      refute NavigationHistory.can_go_forward?(history)

      {:ok, _entry, history} = NavigationHistory.back(history)
      refute NavigationHistory.can_go_back?(history)
      assert NavigationHistory.can_go_forward?(history)
    end
  end

  describe "breadcrumbs/1" do
    test "returns entries up to current index" do
      history = NavigationHistory.new(1, "A")
      history = NavigationHistory.push(history, 2, "B")
      history = NavigationHistory.push(history, 3, "C")

      {:ok, _entry, history} = NavigationHistory.back(history)

      crumbs = NavigationHistory.breadcrumbs(history)
      assert length(crumbs) == 2
      assert Enum.map(crumbs, & &1.flow_name) == ["A", "B"]
    end
  end
end
```

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 2: Push to History on Every Flow Navigation

### Description

Integrate the `NavigationHistory` module into the flow editor's socket lifecycle. Initialize the history on mount, push to it on every flow navigation, and keep `from_flow` working as before for backward compatibility.

### Files Affected

| File                                                                | Action                                 |
|---------------------------------------------------------------------|----------------------------------------|
| `lib/storyarn_web/live/flow_live/show.ex`                           | Add `nav_history` assign, push on load |
| `lib/storyarn_web/live/flow_live/handlers/navigation_handlers.ex`   | Update navigation to use history       |
| `lib/storyarn_web/live/flow_live/handlers/generic_node_handlers.ex` | Update double-click navigate           |
| `test/storyarn_web/live/flow_live/show_events_test.exs`             | Add navigation history tests           |

### Implementation Steps

1. **Initialize `nav_history` in `handle_async(:load_flow_data, ...)`** in `show.ex` (around line 705):

```elixir
alias StoryarnWeb.FlowLive.Helpers.NavigationHistory

# After assign(:loading, false):
|> assign(:nav_history, NavigationHistory.new(flow.id, flow.name))
```

2. **Add `handle_event("nav_back", ...)` and `handle_event("nav_forward", ...)` in `show.ex`:**

```elixir
def handle_event("nav_back", _params, socket) do
  case NavigationHistory.back(socket.assigns.nav_history) do
    {:ok, entry, updated_history} ->
      {:noreply,
       socket
       |> assign(:nav_history, updated_history)
       |> push_navigate(
           to: ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{entry.flow_id}"
         )}

    :at_start ->
      {:noreply, socket}
  end
end

def handle_event("nav_forward", _params, socket) do
  case NavigationHistory.forward(socket.assigns.nav_history) do
    {:ok, entry, updated_history} ->
      {:noreply,
       socket
       |> assign(:nav_history, updated_history)
       |> push_navigate(
           to: ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{entry.flow_id}"
         )}

    :at_end ->
      {:noreply, socket}
  end
end
```

3. **Update `handle_params/3`** to push the current flow into `nav_history` when navigating (only if `nav_history` is already initialized and the flow changed):

```elixir
def handle_params(params, _url, socket) do
  socket =
    socket
    |> maybe_navigate_to_node(params["node"])
    |> maybe_set_from_flow(params["from"])
    |> maybe_push_to_nav_history()

  {:noreply, socket}
end

defp maybe_push_to_nav_history(%{assigns: %{nav_history: history, flow: flow}} = socket) do
  assign(socket, :nav_history, NavigationHistory.push(history, flow.id, flow.name))
end

defp maybe_push_to_nav_history(socket), do: socket
```

4. **Pass `nav_history` to `flow_header`** (see Subtask 3 for UI).

### Test Battery

Add to an existing or new test file testing socket-level behavior. Since navigation triggers a full LiveView remount via `push_navigate`, the unit tests for `NavigationHistory` (Subtask 1) cover the logic. Integration tests should verify the assigns are set correctly:

```elixir
describe "navigation history assigns" do
  test "nav_history is initialized on flow load" do
    # After mounting a flow, nav_history should contain the current flow
    # (verified via the assign, not via rendered HTML)
  end
end
```

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 3: UI -- Back/Forward Buttons and Breadcrumb in Flow Header

### Description

Add back/forward navigation buttons to the flow editor header. Show a breadcrumb trail when the history has more than one entry. The buttons are disabled when at the start/end of the history.

### Files Affected

| File                                                        | Action                                |
|-------------------------------------------------------------|---------------------------------------|
| `lib/storyarn_web/live/flow_live/components/flow_header.ex` | Add back/forward buttons + breadcrumb |
| `lib/storyarn_web/live/flow_live/show.ex`                   | Pass new assigns to flow_header       |

### Implementation Steps

1. **Add new attrs to `flow_header`** in `flow_header.ex`:

```elixir
attr :nav_history, :map, default: nil
```

2. **Add back/forward buttons** in the `<div class="flex-none flex items-center gap-1">` section, alongside the existing "Flows" link and `from_flow` link. Replace the existing `from_flow` link with the new back/forward buttons:

```elixir
<%!-- Navigation history buttons --%>
<button
  :if={@nav_history}
  type="button"
  class="btn btn-ghost btn-sm btn-square"
  phx-click="nav_back"
  disabled={!NavigationHistory.can_go_back?(@nav_history)}
  title={dgettext("flows", "Back (Alt+Left)")}
>
  <.icon name="arrow-left" class="size-4" />
</button>
<button
  :if={@nav_history}
  type="button"
  class="btn btn-ghost btn-sm btn-square"
  phx-click="nav_forward"
  disabled={!NavigationHistory.can_go_forward?(@nav_history)}
  title={dgettext("flows", "Forward (Alt+Right)")}
>
  <.icon name="arrow-right" class="size-4" />
</button>
```

3. **Keep the existing `from_flow` link** as-is for backward compatibility (it shows the name of the flow you came from). The back button provides the same functionality but with full history support.

4. **Add breadcrumb** (optional, below the header or as a tooltip):

```elixir
<%!-- Breadcrumb trail --%>
<div
  :if={@nav_history && length(NavigationHistory.breadcrumbs(@nav_history)) > 1}
  class="flex items-center gap-1 text-xs text-base-content/40"
>
  <span
    :for={crumb <- NavigationHistory.breadcrumbs(@nav_history)}
    class="flex items-center gap-0.5"
  >
    <.icon name="chevron-right" class="size-2.5" />
    <span class={if crumb.flow_id == @flow.id, do: "text-base-content font-medium", else: ""}>
      {crumb.flow_name}
    </span>
  </span>
</div>
```

5. **Pass `nav_history` from `show.ex` render to the component:**

```elixir
<.flow_header
  ...existing attrs...
  nav_history={@nav_history}
/>
```

### Test Battery

Test the component rendering with various history states. These are render tests (no DB needed):

```elixir
describe "flow_header with navigation history" do
  test "renders back button disabled when at start" do
    # Build assigns with a single-entry history
    # Assert the back button has disabled attribute
  end

  test "renders forward button disabled when at end" do
    # Build assigns with history at the last entry
    # Assert the forward button has disabled attribute
  end

  test "renders breadcrumb when multiple entries exist" do
    # Build assigns with 3-entry history
    # Assert breadcrumb contains all flow names
  end
end
```

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 4: Keyboard Shortcuts -- Alt+Left/Alt+Right

### Description

Add keyboard shortcuts for back/forward navigation. Alt+Left triggers `nav_back`, Alt+Right triggers `nav_forward`. Implemented via a JS hook on the flow canvas container.

### Files Affected

| File                                      | Action                                      |
|-------------------------------------------|---------------------------------------------|
| `assets/js/hooks/flow_canvas.js`          | Add keydown listener for Alt+Arrow          |
| `lib/storyarn_web/live/flow_live/show.ex` | Already has `nav_back`/`nav_forward` events |

### Implementation Steps

1. **Add keydown listener in `flow_canvas.js`** (or create a small dedicated hook `NavShortcuts` if separation is preferred). In the `mounted()` lifecycle:

```javascript
// Navigation shortcuts: Alt+Left / Alt+Right
this._navKeyHandler = (e) => {
  if (!e.altKey) return;
  if (e.key === "ArrowLeft") {
    e.preventDefault();
    this.pushEvent("nav_back", {});
  } else if (e.key === "ArrowRight") {
    e.preventDefault();
    this.pushEvent("nav_forward", {});
  }
};
document.addEventListener("keydown", this._navKeyHandler);
```

2. **Clean up in `destroyed()`:**

```javascript
if (this._navKeyHandler) {
  document.removeEventListener("keydown", this._navKeyHandler);
}
```

3. **Ensure no conflict** with existing canvas keyboard shortcuts. The existing flow canvas hook likely handles keyboard events already (e.g., Delete key for node deletion). Alt+Arrow should not conflict since the canvas typically uses plain keys or Ctrl modifiers.

### Test Battery

Keyboard shortcuts are best tested via E2E tests (Playwright). For unit coverage, verify the event handlers exist and respond correctly:

```elixir
describe "keyboard navigation events" do
  test "nav_back event is handled" do
    # Mount flow, trigger "nav_back" event, verify no crash
    # (actual navigation tested in Subtask 1 unit tests)
  end

  test "nav_forward event is handled" do
    # Mount flow, trigger "nav_forward" event, verify no crash
  end
end
```

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 5: Integration Tests

### Description

End-to-end integration tests that verify the full navigation history cycle: navigate to multiple flows, go back, go forward, verify breadcrumb rendering.

### Files Affected

| File                                                                       | Action                       |
|----------------------------------------------------------------------------|------------------------------|
| `test/storyarn_web/live/flow_live/navigation_history_integration_test.exs` | Create integration test file |

### Implementation Steps

1. **Create test file** with ConnCase setup.

2. **Test the full cycle:**

```elixir
defmodule StoryarnWeb.FlowLive.NavigationHistoryIntegrationTest do
  use StoryarnWeb.ConnCase

  import Phoenix.LiveViewTest
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  describe "navigation history" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Storyarn.Repo.preload(:workspace)
      flow_a = flow_fixture(project, %{name: "Flow A"})
      flow_b = flow_fixture(project, %{name: "Flow B"})
      flow_c = flow_fixture(project, %{name: "Flow C"})

      %{project: project, flow_a: flow_a, flow_b: flow_b, flow_c: flow_c}
    end

    test "back button is disabled on initial load",
         %{conn: conn, project: project, flow_a: flow_a} do
      {:ok, view, html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow_a.id}")

      # Wait for async load
      assert render_async(view) =~ "Flow A"
      # Back button should be disabled
      assert has_element?(view, "button[phx-click='nav_back'][disabled]")
    end

    test "nav_back and nav_forward events do not crash",
         %{conn: conn, project: project, flow_a: flow_a} do
      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow_a.id}")

      render_async(view)

      # nav_back at start should be a no-op
      render_click(view, "nav_back", %{})

      # nav_forward at end should be a no-op
      render_click(view, "nav_forward", %{})
    end
  end
end
```

### Test Battery

The tests above cover the integration points. The pure logic is thoroughly tested in Subtask 1's `NavigationHistoryTest`.

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Summary

| Subtask                    | What it delivers                                           | Key files                           |
|----------------------------|------------------------------------------------------------|-------------------------------------|
| 1. History module          | Pure functional `NavigationHistory` with push/back/forward | `navigation_history.ex`             |
| 2. Socket integration      | History tracked in assigns, pushed on navigation           | `show.ex`, `navigation_handlers.ex` |
| 3. UI buttons + breadcrumb | Back/forward buttons in header, breadcrumb trail           | `flow_header.ex`                    |
| 4. Keyboard shortcuts      | Alt+Left/Alt+Right for back/forward                        | `flow_canvas.js`                    |
| 5. Integration tests       | Full cycle verification                                    | Integration test file               |

**Next:** [10_DEBUGGER_STEP_LIMIT.md](../stress_test/10_DEBUGGER_STEP_LIMIT.md)
