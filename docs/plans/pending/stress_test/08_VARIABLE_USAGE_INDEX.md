# 08 Variable Usage Index

> **Gap:** 6c -- Variable Usage Index
> **Priority:** MEDIUM | **Effort:** Low
> **Dependencies:** Variable reference tracking (already implemented)
> **Previous:** `07_BETTER_SEARCH.md` | **Next:** `09_CROSS_FLOW_NAVIGATION.md`
> **Last Updated:** February 20, 2026

---

## Context and Current State

### What exists today

The `variable_references` table is already populated by `Storyarn.Flows.VariableReferenceTracker`. Every time a condition or instruction node is saved, the tracker extracts read/write references and upserts them into the database. The schema lives at:

- **Schema:** `/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/flows/variable_reference.ex`
  - `belongs_to :flow_node` / `belongs_to :block`
  - Fields: `kind` ("read" | "write"), `source_sheet`, `source_variable`
  - Unique constraint on `[:flow_node_id, :block_id, :kind]`

- **Tracker:** `/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/flows/variable_reference_tracker.ex`
  - `update_references/1` -- called after every node data save
  - `get_variable_usage/2` -- returns refs for a single block with flow/node info
  - `count_variable_usage/1` -- returns `%{"read" => N, "write" => M}` for a block
  - `check_stale_references/2` -- returns refs with `:stale` boolean
  - `repair_stale_references/1` -- bulk repairs stale node JSON across a project

- **Facade:** `/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/flows.ex` (lines 318--354)
  - Already exposes `get_variable_usage/2`, `count_variable_usage/1`, `check_stale_references/2`, `repair_stale_references/1`, `list_stale_node_ids/1`

- **Sheet editor integration:** The sheet editor's "References" tab already shows per-block variable usage via `ReferencesTab` LiveComponent at `/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn_web/live/sheet_live/show.ex` (line 150). This shows which flows read/write each variable on the currently open sheet.

- **Tests:**
  - `/Users/adnumaro/Work/Personal/Code/storyarn/test/storyarn/flows/variable_reference_tracker_test.exs` (1275 lines, comprehensive)
  - `/Users/adnumaro/Work/Personal/Code/storyarn/test/storyarn_web/live/sheet_live/variable_usage_test.exs` (171 lines, integration tests)

### What is missing

1. **No project-wide variable usage view.** The current sheet editor shows usage for variables on one sheet at a time. There is no way to see a complete index of "all variables in the project and which flows read/write them."

2. **No query to list all variable references grouped by variable across the project.** The existing `get_variable_usage/2` takes a single `block_id`. A project-wide query grouped by block (variable) does not exist.

3. **No UI accessible from the project level.** The sheet editor's references tab is per-sheet. A narrative designer working on a project with 50+ sheets and 200+ variables has no single-page overview.

### Design

Create a **Variable Usage Browser** -- a panel accessible from both the sheet editor (per-variable drill-down) and from the project sidebar as a global "Variables" view. The browser queries `variable_references` grouped by block_id, shows variable names, and lists which flows READ and WRITE each variable. Each reference is a clickable link to the flow editor with `?node=<node_id>`.

---

## Subtask 1: Backend Query -- Project-wide Variable Usage Index

### Description

Add a new function `list_project_variable_usage/1` to `VariableReferenceTracker` that returns all variable references for a project grouped by variable (block). This is the data backbone for the UI.

### Files Affected

| File                                                      | Action                              |
|-----------------------------------------------------------|-------------------------------------|
| `lib/storyarn/flows/variable_reference_tracker.ex`        | Add `list_project_variable_usage/1` |
| `lib/storyarn/flows.ex`                                   | Add facade `defdelegate`            |
| `test/storyarn/flows/variable_reference_tracker_test.exs` | Add tests                           |

### Implementation Steps

1. **Add `list_project_variable_usage/1` to `VariableReferenceTracker`:**

```elixir
@doc """
Returns all variable references for a project, grouped by variable.

Each entry contains the variable identity (sheet_shortcut, variable_name,
block_type, block_id, sheet_id) and a list of references (kind, flow_id,
flow_name, node_id, node_type).

Results are ordered by sheet name then variable name.
"""
@spec list_project_variable_usage(integer()) :: [map()]
def list_project_variable_usage(project_id) do
  from(vr in VariableReference,
    join: n in FlowNode, on: n.id == vr.flow_node_id,
    join: f in Flow, on: f.id == n.flow_id,
    join: b in Block, on: b.id == vr.block_id,
    join: s in Sheet, on: s.id == b.sheet_id,
    where: f.project_id == ^project_id,
    where: is_nil(f.deleted_at),
    where: is_nil(s.deleted_at),
    where: is_nil(b.deleted_at),
    select: %{
      block_id: b.id,
      sheet_id: s.id,
      sheet_name: s.name,
      sheet_shortcut: coalesce(s.shortcut, fragment("CAST(? AS TEXT)", s.id)),
      variable_name: b.variable_name,
      block_type: b.type,
      kind: vr.kind,
      flow_id: f.id,
      flow_name: f.name,
      flow_shortcut: f.shortcut,
      node_id: n.id,
      node_type: n.type
    },
    order_by: [asc: s.name, asc: b.variable_name, asc: vr.kind, asc: f.name]
  )
  |> Repo.all()
  |> group_by_variable()
end

defp group_by_variable(rows) do
  rows
  |> Enum.group_by(fn r -> r.block_id end)
  |> Enum.map(fn {_block_id, refs} ->
    first = hd(refs)

    %{
      block_id: first.block_id,
      sheet_id: first.sheet_id,
      sheet_name: first.sheet_name,
      sheet_shortcut: first.sheet_shortcut,
      variable_name: first.variable_name,
      block_type: first.block_type,
      references: Enum.map(refs, fn r ->
        %{
          kind: r.kind,
          flow_id: r.flow_id,
          flow_name: r.flow_name,
          flow_shortcut: r.flow_shortcut,
          node_id: r.node_id,
          node_type: r.node_type
        }
      end)
    }
  end)
  |> Enum.sort_by(fn v -> {v.sheet_name, v.variable_name} end)
end
```

2. **Add facade delegation in `flows.ex`:**

```elixir
@doc """
Returns all variable references for a project, grouped by variable.
"""
@spec list_project_variable_usage(integer()) :: [map()]
defdelegate list_project_variable_usage(project_id), to: VariableReferenceTracker
```

### Test Battery

Add to `test/storyarn/flows/variable_reference_tracker_test.exs`:

```elixir
describe "list_project_variable_usage/1" do
  test "returns variables grouped with their references", ctx do
    # Create instruction that writes health
    instruction_node = node_fixture(ctx.flow, %{
      type: "instruction",
      data: %{
        "assignments" => [
          %{"id" => "a1", "sheet" => "mc.jaime", "variable" => "health",
            "operator" => "set", "value" => "100", "value_type" => "literal"}
        ]
      }
    })
    VariableReferenceTracker.update_references(instruction_node)

    # Create condition that reads health
    condition_node = node_fixture(ctx.flow, %{
      type: "condition",
      data: %{
        "condition" => %{
          "logic" => "all",
          "rules" => [
            %{"id" => "r1", "sheet" => "mc.jaime", "variable" => "health",
              "operator" => "greater_than", "value" => "50"}
          ]
        }
      }
    })
    VariableReferenceTracker.update_references(condition_node)

    result = VariableReferenceTracker.list_project_variable_usage(ctx.project.id)
    assert length(result) == 1  # one variable: health

    [variable] = result
    assert variable.variable_name == "health"
    assert variable.sheet_shortcut == "mc.jaime"
    assert length(variable.references) == 2

    kinds = Enum.map(variable.references, & &1.kind) |> Enum.sort()
    assert kinds == ["read", "write"]
  end

  test "returns multiple variables from different sheets", ctx do
    # Write to health
    n1 = node_fixture(ctx.flow, %{
      type: "instruction",
      data: %{
        "assignments" => [
          %{"id" => "a1", "sheet" => "mc.jaime", "variable" => "health",
            "operator" => "set", "value" => "100", "value_type" => "literal"}
        ]
      }
    })
    VariableReferenceTracker.update_references(n1)

    # Write to quest variable
    n2 = node_fixture(ctx.flow, %{
      type: "instruction",
      data: %{
        "assignments" => [
          %{"id" => "a2", "sheet" => "global.quests", "variable" => "sword_done",
            "operator" => "set_true", "value_type" => "literal"}
        ]
      }
    })
    VariableReferenceTracker.update_references(n2)

    result = VariableReferenceTracker.list_project_variable_usage(ctx.project.id)
    assert length(result) == 2

    names = Enum.map(result, & &1.variable_name) |> Enum.sort()
    assert "health" in names
    assert "sword_done" in names
  end

  test "returns empty list when no references exist", ctx do
    result = VariableReferenceTracker.list_project_variable_usage(ctx.project.id)
    assert result == []
  end

  test "excludes references from deleted flows", ctx do
    node = node_fixture(ctx.flow, %{
      type: "instruction",
      data: %{
        "assignments" => [
          %{"id" => "a1", "sheet" => "mc.jaime", "variable" => "health",
            "operator" => "set", "value" => "100", "value_type" => "literal"}
        ]
      }
    })
    VariableReferenceTracker.update_references(node)

    Flows.delete_flow(ctx.flow)

    result = VariableReferenceTracker.list_project_variable_usage(ctx.project.id)
    assert result == []
  end
end
```

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 2: UI Component -- Variable Usage Browser Panel

### Description

Create a LiveComponent that displays the project-wide variable usage index. Shows a collapsible list of variables grouped by sheet, with read/write indicators and clickable flow links. This component can be rendered as a modal or as a dedicated panel.

### Files Affected

| File                                                                          | Action               |
|-------------------------------------------------------------------------------|----------------------|
| `lib/storyarn_web/live/flow_live/components/variable_usage_browser.ex`        | Create new component |
| `test/storyarn_web/live/flow_live/components/variable_usage_browser_test.exs` | Create tests         |

### Implementation Steps

1. **Create `variable_usage_browser.ex`:**

```elixir
defmodule StoryarnWeb.FlowLive.Components.VariableUsageBrowser do
  @moduledoc """
  Variable Usage Browser component.

  Displays a project-wide index of all variables that are referenced
  by flow nodes (conditions read, instructions write). Each variable
  shows which flows interact with it, with clickable links.
  """

  use StoryarnWeb, :live_component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents

  alias Storyarn.Flows

  @impl true
  def update(assigns, socket) do
    usage = Flows.list_project_variable_usage(assigns.project_id)

    # Group by sheet for display
    by_sheet =
      usage
      |> Enum.group_by(fn v -> {v.sheet_id, v.sheet_name, v.sheet_shortcut} end)
      |> Enum.sort_by(fn {{_, name, _}, _} -> name end)

    socket =
      socket
      |> assign(:project_id, assigns.project_id)
      |> assign(:workspace_slug, assigns.workspace_slug)
      |> assign(:project_slug, assigns.project_slug)
      |> assign(:by_sheet, by_sheet)
      |> assign(:filter, assigns[:filter] || "")

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full">
      <div class="px-4 py-3 border-b border-base-300">
        <h2 class="text-sm font-semibold flex items-center gap-2">
          <.icon name="database" class="size-4" />
          {dgettext("flows", "Variable Usage Index")}
        </h2>
        <input
          type="text"
          placeholder={dgettext("flows", "Filter variables...")}
          value={@filter}
          phx-change="filter_variables"
          phx-target={@myself}
          name="filter"
          class="input input-bordered input-xs w-full mt-2"
        />
      </div>

      <div class="flex-1 overflow-y-auto p-2">
        <div :if={@by_sheet == []} class="text-center text-sm text-base-content/40 py-8">
          {dgettext("flows", "No variable references found in this project.")}
        </div>

        <div :for={{{sheet_id, sheet_name, sheet_shortcut}, variables} <- filter_sheets(@by_sheet, @filter)}>
          <div class="flex items-center gap-2 px-2 py-1 mt-2 first:mt-0">
            <.icon name="file-text" class="size-3 text-base-content/50" />
            <span class="text-xs font-medium text-base-content/70">{sheet_name}</span>
            <span :if={sheet_shortcut} class="text-xs text-base-content/30">
              #{sheet_shortcut}
            </span>
          </div>

          <div
            :for={variable <- filter_variables(variables, @filter)}
            class="ml-4 mb-2 border border-base-200 rounded-lg bg-base-50"
          >
            <div class="flex items-center gap-2 px-3 py-1.5 border-b border-base-200">
              <span class="text-xs font-mono font-medium">
                {variable.variable_name}
              </span>
              <span class="badge badge-xs badge-ghost">{variable.block_type}</span>
              <.usage_counts references={variable.references} />
            </div>

            <div class="px-3 py-1 space-y-0.5">
              <.reference_row
                :for={ref <- variable.references}
                ref={ref}
                workspace_slug={@workspace_slug}
                project_slug={@project_slug}
              />
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("filter_variables", %{"filter" => filter}, socket) do
    {:noreply, assign(socket, :filter, filter)}
  end

  # -- Private components --

  defp usage_counts(assigns) do
    reads = Enum.count(assigns.references, &(&1.kind == "read"))
    writes = Enum.count(assigns.references, &(&1.kind == "write"))
    assigns = assign(assigns, :reads, reads) |> assign(:writes, writes)

    ~H"""
    <span class="ml-auto flex items-center gap-2 text-xs text-base-content/40">
      <span :if={@reads > 0} class="flex items-center gap-0.5" title={dgettext("flows", "Read by")}>
        <.icon name="eye" class="size-2.5" /> {@reads}
      </span>
      <span :if={@writes > 0} class="flex items-center gap-0.5" title={dgettext("flows", "Written by")}>
        <.icon name="pencil" class="size-2.5" /> {@writes}
      </span>
    </span>
    """
  end

  defp reference_row(assigns) do
    icon = if assigns.ref.kind == "read", do: "eye", else: "pencil"
    badge_class = if assigns.ref.kind == "read", do: "badge-info", else: "badge-warning"
    assigns = assign(assigns, :icon, icon) |> assign(:badge_class, badge_class)

    ~H"""
    <.link
      navigate={
        ~p"/workspaces/#{@workspace_slug}/projects/#{@project_slug}/flows/#{@ref.flow_id}?node=#{@ref.node_id}"
      }
      class="flex items-center gap-2 py-0.5 px-1 rounded hover:bg-base-200 text-xs group"
    >
      <span class={"badge badge-xs #{@badge_class}"}>{@ref.kind}</span>
      <.icon name={@icon} class="size-2.5 text-base-content/30" />
      <span class="text-base-content/60">{@ref.flow_name}</span>
      <span class="text-base-content/30 group-hover:text-primary">
        {String.capitalize(@ref.node_type)}
      </span>
    </.link>
    """
  end

  defp filter_sheets(by_sheet, ""), do: by_sheet
  defp filter_sheets(by_sheet, filter) do
    q = String.downcase(filter)
    Enum.filter(by_sheet, fn {{_, sheet_name, sheet_shortcut}, variables} ->
      String.contains?(String.downcase(sheet_name), q) or
        (sheet_shortcut && String.contains?(String.downcase(sheet_shortcut), q)) or
        Enum.any?(variables, fn v ->
          String.contains?(String.downcase(v.variable_name), q)
        end)
    end)
  end

  defp filter_variables(variables, ""), do: variables
  defp filter_variables(variables, filter) do
    q = String.downcase(filter)
    Enum.filter(variables, fn v ->
      String.contains?(String.downcase(v.variable_name), q)
    end)
  end
end
```

2. **Create test file** at `test/storyarn_web/live/flow_live/components/variable_usage_browser_test.exs` with component render tests checking for correct grouping, filtering, and link generation.

### Test Battery

```elixir
defmodule StoryarnWeb.FlowLive.Components.VariableUsageBrowserTest do
  use StoryarnWeb.ConnCase

  import Phoenix.LiveViewTest
  import Storyarn.FlowsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows.VariableReferenceTracker

  # These tests verify the component renders correctly within a LiveView.
  # Full integration testing of the query is covered in
  # variable_reference_tracker_test.exs.

  describe "variable usage browser rendering" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Storyarn.Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Player", shortcut: "player"})
      health_block = block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health", "placeholder" => "0"}
      })
      flow = flow_fixture(project, %{name: "Main Quest"})

      %{project: project, sheet: sheet, health_block: health_block, flow: flow}
    end

    test "displays empty state when no references exist", %{project: project} do
      # The component should render "No variable references found"
      usage = Storyarn.Flows.list_project_variable_usage(project.id)
      assert usage == []
    end

    test "groups variables by sheet", %{flow: flow, project: project} do
      node = node_fixture(flow, %{
        type: "instruction",
        data: %{
          "assignments" => [
            %{"id" => "a1", "sheet" => "player", "variable" => "health",
              "operator" => "set", "value" => "100", "value_type" => "literal"}
          ]
        }
      })
      VariableReferenceTracker.update_references(node)

      usage = Storyarn.Flows.list_project_variable_usage(project.id)
      assert length(usage) == 1
      assert hd(usage).sheet_name == "Player"
    end
  end
end
```

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 3: Integration -- Accessible from Sheet Editor and Project Navigation

### Description

Wire the Variable Usage Browser into two access points:
1. **Sheet editor** -- a button on the "References" tab that opens the project-wide browser (modal overlay).
2. **Project sidebar** -- a "Variables" menu item that opens a dedicated route or modal showing the full variable usage index.

### Files Affected

| File                                                        | Action                                          |
|-------------------------------------------------------------|-------------------------------------------------|
| `lib/storyarn_web/live/sheet_live/show.ex`                  | Add event handler + modal for project-wide view |
| `lib/storyarn_web/live/project_live/components/sidebar.ex`  | Add "Variables" link (if sidebar exists)        |
| `test/storyarn_web/live/sheet_live/variable_usage_test.exs` | Add integration tests for modal trigger         |

### Implementation Steps

1. **Add a modal to the sheet editor that hosts the `VariableUsageBrowser` component.** In `show.ex`, add a `<.modal>` at the bottom of the render function and a `handle_event("open_variable_browser", ...)` that sets an assign to show it.

2. **Add a button on the References tab header** that reads `dgettext("sheets", "View all project variables")` and triggers `phx-click="open_variable_browser"`.

3. **Add the event handler in `show.ex`:**

```elixir
def handle_event("open_variable_browser", _params, socket) do
  {:noreply, assign(socket, :variable_browser_open, true)}
end

def handle_event("close_variable_browser", _params, socket) do
  {:noreply, assign(socket, :variable_browser_open, false)}
end
```

4. **Add the assign initialization** in the mount function: `assign(socket, :variable_browser_open, false)`.

5. **Render the modal conditionally:**

```elixir
<.modal :if={@variable_browser_open} id="variable-browser-modal" on_cancel={JS.push("close_variable_browser")}>
  <.live_component
    module={VariableUsageBrowser}
    id="variable-usage-browser"
    project_id={@project.id}
    workspace_slug={@workspace.slug}
    project_slug={@project.slug}
  />
</.modal>
```

6. **Project sidebar integration** (if a sidebar component exists): Add a menu item that navigates to the sheet list with a query param like `?tab=variables` or opens the same modal pattern. Keep this lightweight -- just a link, no new route.

### Test Battery

Add to `test/storyarn_web/live/sheet_live/variable_usage_test.exs`:

```elixir
describe "project-wide variable browser" do
  setup :register_and_log_in_user

  setup %{user: user} do
    project = project_fixture(user) |> Storyarn.Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "Player", shortcut: "player"})
    health_block = block_fixture(sheet, %{
      type: "number",
      config: %{"label" => "Health", "placeholder" => "0"}
    })
    flow = flow_fixture(project, %{name: "Main Quest"})

    %{project: project, sheet: sheet, health_block: health_block, flow: flow}
  end

  test "opens variable browser modal from references tab",
       %{conn: conn, project: project, sheet: sheet, flow: flow} do
    node = node_fixture(flow, %{
      type: "instruction",
      data: %{
        "assignments" => [
          %{"id" => "a1", "sheet" => "player", "variable" => "health",
            "operator" => "set", "value" => "100", "value_type" => "literal"}
        ]
      }
    })
    VariableReferenceTracker.update_references(node)

    {:ok, view, _html} =
      live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}")

    # Switch to references tab
    render_click(view, "switch_tab", %{"tab" => "references"})

    # Open the project-wide variable browser
    html = render_click(view, "open_variable_browser", %{})

    assert html =~ "Variable Usage Index"
    assert html =~ "Main Quest"
    assert html =~ "health"
  end
end
```

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Summary

| Subtask          | What it delivers                                                                     | Key files                                   |
|------------------|--------------------------------------------------------------------------------------|---------------------------------------------|
| 1. Backend query | `list_project_variable_usage/1` -- all variables with their flow references, grouped | `variable_reference_tracker.ex`, `flows.ex` |
| 2. UI component  | `VariableUsageBrowser` LiveComponent with grouping, filtering, and flow links        | `variable_usage_browser.ex`                 |
| 3. Integration   | Accessible from sheet editor and project sidebar via modal                           | `sheet_live/show.ex`, test files            |

**Next:** [09_CROSS_FLOW_NAVIGATION.md](../../stress_test/09_CROSS_FLOW_NAVIGATION.md)
