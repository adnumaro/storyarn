# 07 — Better Search

> **Gap Reference:** Gap 6a from `COMPLEX_NARRATIVE_STRESS_TEST.md`
> **Priority:** MEDIUM
> **Effort:** Low
> **Dependencies:** None (Subtask 3 benefits from Gap 6b / Flow Tags if implemented first)
> **Previous:** `06_AUTO_LAYOUT.md`
> **Next:** `08_VARIABLE_USAGE_INDEX.md`
> **Last Updated:** February 20, 2026

---

## Context

With 806 flows in the Planescape: Torment scenario, the current search is too limited. Users searching for "Annah" may get 10 results when there are 20+ Annah-related flows. There is no way to paginate past the first 10. There is also no way to search inside node content (dialogue text, technical IDs, condition labels) across flows.

## Current State

### `lib/storyarn/flows/flow_crud.ex` — `search_flows/2`

```elixir
def search_flows(project_id, query) when is_binary(query) do
  query = String.trim(query)

  if query == "" do
    from(f in Flow,
      where: f.project_id == ^project_id and is_nil(f.deleted_at),
      order_by: [desc: f.updated_at],
      limit: 10
    )
    |> Repo.all()
  else
    search_term = "%#{query}%"

    from(f in Flow,
      where: f.project_id == ^project_id and is_nil(f.deleted_at),
      where: ilike(f.name, ^search_term) or ilike(f.shortcut, ^search_term),
      order_by: [asc: f.name],
      limit: 10
    )
    |> Repo.all()
  end
end
```

Key limitations:
- Hard limit of 10 results.
- No offset/pagination.
- Only searches `name` and `shortcut` fields.
- No node content search.

### Sidebar Flow Tree — `lib/storyarn_web/components/sidebar/flow_tree.ex`

- Uses `TreeSearch` hook for **client-side** filtering of the visible tree by name.
- This is separate from `search_flows` which is used for flow reference selection (e.g., in subflow/exit node pickers).

### Flow Reference Pickers

Several places use `search_flows/2`:
- Subflow node sidebar: select a flow to reference.
- Exit node sidebar: select a flow to link.
- Entry node sidebar: shows referencing flows (uses a different query).

These are the primary consumers of the paginated search improvement.

### Node Content Structure — `flow_nodes.data` (JSONB)

Node data is stored as JSONB. Relevant searchable fields by type:

| Node Type     | Searchable Fields in `data`                                                                    |
|---------------|------------------------------------------------------------------------------------------------|
| `dialogue`    | `text`, `stage_directions`, `menu_text`, `technical_id`, `localization_id`, `responses[].text` |
| `condition`   | `expression`, `cases[].label`, `cases[].value`                                                 |
| `instruction` | `assignments[].sheet`, `assignments[].variable`                                                |
| `hub`         | `label`, `hub_id`                                                                              |
| `exit`        | `label`, `technical_id`                                                                        |
| `scene`       | `location`, `time`, `description`                                                              |
| `entry`       | (no searchable content)                                                                        |
| `jump`        | (target_hub_id only)                                                                           |

---

## Subtask 1: Increase Limit + Add Offset to `search_flows`

**Goal:** Change `search_flows` to accept an options keyword list with configurable `:limit` and `:offset`. Default limit increases from 10 to 25. This enables "load more" pagination.

### Files Affected

| File                              | Action                                                  |
|-----------------------------------|---------------------------------------------------------|
| `lib/storyarn/flows/flow_crud.ex` | Update `search_flows/2`, add `search_flows/3` with opts |
| `lib/storyarn/flows.ex`           | Update `@spec` for delegation                           |

### Implementation Steps

1. **Update `search_flows` in `flow_crud.ex`:**

Keep the existing `search_flows/2` for backward compatibility but route it through the new implementation:

```elixir
@default_search_limit 25

@doc """
Searches flows by name or shortcut for reference selection.
Returns flows matching the query with configurable limit and offset.
Excludes soft-deleted flows.

## Options
  - `:limit` - Max results (default 25)
  - `:offset` - Skip N results (default 0)
  - `:tag` - Filter by tag (optional, from 05_FLOW_TAGS if implemented)
"""
def search_flows(project_id, query, opts \\ []) when is_binary(query) do
  limit = Keyword.get(opts, :limit, @default_search_limit)
  offset = Keyword.get(opts, :offset, 0)
  tag = Keyword.get(opts, :tag)
  query_str = String.trim(query)

  base =
    from(f in Flow,
      where: f.project_id == ^project_id and is_nil(f.deleted_at)
    )

  # Apply tag filter if provided and tags field exists
  base = maybe_filter_by_tag(base, tag)

  if query_str == "" do
    from(f in base,
      order_by: [desc: f.updated_at],
      limit: ^limit,
      offset: ^offset
    )
    |> Repo.all()
  else
    search_term = "%#{query_str}%"

    from(f in base,
      where: ilike(f.name, ^search_term) or ilike(f.shortcut, ^search_term),
      order_by: [asc: f.name],
      limit: ^limit,
      offset: ^offset
    )
    |> Repo.all()
  end
end

# If tags are implemented (05_FLOW_TAGS), filter by tag.
# If not yet implemented, this is a no-op.
defp maybe_filter_by_tag(query, nil), do: query
defp maybe_filter_by_tag(query, ""), do: query

defp maybe_filter_by_tag(query, tag) when is_binary(tag) do
  from(f in query, where: ^tag in f.tags)
end
```

Note: If Flow Tags (document 05) is not yet implemented, the `^tag in f.tags` will fail at compile time because `:tags` field does not exist. In that case, remove the `maybe_filter_by_tag` clause for the binary tag and simply return the base query. When tags are added later, re-enable this clause.

For a safe implementation before tags exist:

```elixir
defp maybe_filter_by_tag(query, _tag), do: query
```

Then update it when the tags migration is applied.

2. **Update the facade `lib/storyarn/flows.ex`:**

Replace the existing delegation:

```elixir
@doc """
Searches flows by name or shortcut for reference selection.
Returns flows matching the query. Accepts opts: [limit: 25, offset: 0, tag: nil].
"""
@spec search_flows(integer(), String.t(), keyword()) :: [flow()]
defdelegate search_flows(project_id, query, opts \\ []), to: FlowCrud
```

### Test Battery

**File:** `test/storyarn/flows/search_flows_test.exs`

```elixir
defmodule Storyarn.Flows.SearchFlowsTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Flows

  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  setup do
    project = project_fixture()

    # Create 30 flows with alphabetical names
    for i <- 1..30 do
      name = "Flow #{String.pad_leading(to_string(i), 2, "0")}"
      flow_fixture(project, %{name: name})
    end

    %{project: project}
  end

  describe "search_flows/3 pagination" do
    test "default limit is 25", %{project: project} do
      results = Flows.search_flows(project.id, "Flow")
      assert length(results) == 25
    end

    test "custom limit", %{project: project} do
      results = Flows.search_flows(project.id, "Flow", limit: 5)
      assert length(results) == 5
    end

    test "offset skips results", %{project: project} do
      page1 = Flows.search_flows(project.id, "Flow", limit: 10, offset: 0)
      page2 = Flows.search_flows(project.id, "Flow", limit: 10, offset: 10)

      assert length(page1) == 10
      assert length(page2) == 10

      # No overlap
      page1_ids = MapSet.new(Enum.map(page1, & &1.id))
      page2_ids = MapSet.new(Enum.map(page2, & &1.id))
      assert MapSet.disjoint?(page1_ids, page2_ids)
    end

    test "offset beyond results returns empty", %{project: project} do
      results = Flows.search_flows(project.id, "Flow", offset: 100)
      assert results == []
    end

    test "empty query returns recent flows with pagination", %{project: project} do
      results = Flows.search_flows(project.id, "", limit: 5, offset: 0)
      assert length(results) == 5

      results2 = Flows.search_flows(project.id, "", limit: 5, offset: 5)
      assert length(results2) == 5
    end

    test "backward compatible: search_flows/2 still works", %{project: project} do
      results = Flows.search_flows(project.id, "Flow")
      assert length(results) == 25
    end
  end
end
```

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 2: "Show More" UI for Search Results

**Goal:** Add a "Show more" button (or scroll-to-load) to the flow reference picker components that use `search_flows`. When clicked, load the next page of results and append them.

### Files Affected

| File                                                                | Action                                  |
|---------------------------------------------------------------------|-----------------------------------------|
| `lib/storyarn_web/live/flow_live/nodes/subflow/config_sidebar.ex`   | Add "Show more" button to flow picker   |
| `lib/storyarn_web/live/flow_live/nodes/exit/config_sidebar.ex`      | Same pattern                            |
| `lib/storyarn_web/live/flow_live/handlers/generic_node_handlers.ex` | Update search handler to support offset |
| `lib/storyarn_web/live/flow_live/show.ex`                           | Wire the `"search_flows_more"` event    |

### Implementation Steps

1. **Update the search state in socket assigns:**

When search results are loaded, also track the current offset and whether more results may exist:

In the handler that processes flow search (find the existing `handle_event("search_flows", ...)` or equivalent):

```elixir
# In the search handler, update assigns:
results = Flows.search_flows(project_id, query, limit: 25, offset: 0)
has_more = length(results) == 25  # If we got exactly the limit, there may be more

socket
|> assign(:flow_search_results, results)
|> assign(:flow_search_query, query)
|> assign(:flow_search_offset, 25)
|> assign(:flow_search_has_more, has_more)
```

2. **Add "Show more" handler:**

```elixir
def handle_event("search_flows_more", _params, socket) do
  query = socket.assigns[:flow_search_query] || ""
  offset = socket.assigns[:flow_search_offset] || 0
  project_id = socket.assigns.project.id

  more_results = Flows.search_flows(project_id, query, limit: 25, offset: offset)
  has_more = length(more_results) == 25

  all_results = (socket.assigns[:flow_search_results] || []) ++ more_results

  {:noreply,
   socket
   |> assign(:flow_search_results, all_results)
   |> assign(:flow_search_offset, offset + 25)
   |> assign(:flow_search_has_more, has_more)}
end
```

3. **Add "Show more" button to the picker component:**

In the flow picker dropdown/list (wherever search results are rendered), add at the bottom:

```elixir
<button
  :if={@flow_search_has_more}
  type="button"
  phx-click="search_flows_more"
  class="btn btn-ghost btn-xs btn-block mt-1"
>
  {dgettext("flows", "Show more...")}
</button>
```

4. **Reset offset on new search:**

When the search query changes (user types a new query), reset offset to 0:

```elixir
# In the search handler, always reset:
|> assign(:flow_search_offset, 25)
```

### Test Battery

**File:** `test/storyarn_web/live/flow_live/search_pagination_test.exs`

```elixir
defmodule StoryarnWeb.FlowLive.SearchPaginationTest do
  use StoryarnWeb.ConnCase, async: true

  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  setup do
    user = user_fixture()
    workspace = workspace_fixture(user)
    project = project_fixture(workspace)

    # Create 30 flows
    for i <- 1..30 do
      flow_fixture(project, %{name: "SearchTest Flow #{i}"})
    end

    flow = flow_fixture(project, %{name: "Active Flow"})
    %{user: user, workspace: workspace, project: project, flow: flow}
  end

  describe "flow search pagination" do
    test "initial search returns up to 25 results", %{
      conn: conn, user: user, workspace: workspace, project: project, flow: flow
    } do
      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/flows/#{flow.id}")

      # Trigger search (adapt event name to actual implementation)
      # This test verifies the backend pagination; exact LiveView event names
      # depend on the component that calls search_flows
      results = Storyarn.Flows.search_flows(project.id, "SearchTest", limit: 25, offset: 0)
      assert length(results) == 25

      more = Storyarn.Flows.search_flows(project.id, "SearchTest", limit: 25, offset: 25)
      assert length(more) == 5
    end
  end
end
```

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 3: Node Content Search (Optional Enhancement)

**Goal:** Extend search to optionally search inside flow node content (dialogue text, labels, technical IDs) via the `flow_nodes.data` JSONB column. This enables finding flows that contain specific dialogue text even when the flow name does not match.

This subtask is **optional** and can be deferred. The core search improvement (Subtasks 1-2) delivers the primary value.

### Files Affected

| File                              | Action                                               |
|-----------------------------------|------------------------------------------------------|
| `lib/storyarn/flows/flow_crud.ex` | Add `search_flows_deep/3` (or extend `search_flows`) |
| `lib/storyarn/flows.ex`           | Expose via `defdelegate`                             |
| Caller components                 | Wire a "Search in content" toggle                    |

### Implementation Steps

1. **Add `search_flows_deep/3` to `flow_crud.ex`:**

```elixir
@doc """
Deep search: searches flow names/shortcuts AND node content (dialogue text,
labels, technical IDs). Returns flows that match, with a reason indicator.

Uses JSONB text search on the flow_nodes.data column.

## Options
  - `:limit` - Max results (default 25)
  - `:offset` - Skip N results (default 0)
"""
def search_flows_deep(project_id, query, opts \\ []) when is_binary(query) do
  query_str = String.trim(query)

  if query_str == "" do
    # Empty query: fall back to regular search
    search_flows(project_id, query_str, opts)
  else
    limit = Keyword.get(opts, :limit, @default_search_limit)
    offset = Keyword.get(opts, :offset, 0)
    search_term = "%#{query_str}%"

    from(f in Flow,
      where: f.project_id == ^project_id and is_nil(f.deleted_at),
      where:
        ilike(f.name, ^search_term) or
        ilike(f.shortcut, ^search_term) or
        f.id in subquery(
          from(n in FlowNode,
            join: fl in Flow, on: n.flow_id == fl.id,
            where: fl.project_id == ^project_id and is_nil(fl.deleted_at) and is_nil(n.deleted_at),
            where:
              ilike(fragment("?->>'text'", n.data), ^search_term) or
              ilike(fragment("?->>'label'", n.data), ^search_term) or
              ilike(fragment("?->>'technical_id'", n.data), ^search_term) or
              ilike(fragment("?->>'hub_id'", n.data), ^search_term) or
              ilike(fragment("?->>'expression'", n.data), ^search_term) or
              ilike(fragment("?->>'stage_directions'", n.data), ^search_term) or
              ilike(fragment("?->>'menu_text'", n.data), ^search_term) or
              ilike(fragment("?->>'location'", n.data), ^search_term),
            select: n.flow_id
          )
        ),
      order_by: [asc: f.name],
      limit: ^limit,
      offset: ^offset
    )
    |> Repo.all()
  end
end
```

Performance note: This query uses a subquery with multiple `ILIKE` on JSONB fields. For projects with < 50,000 nodes, this is acceptable (PostgreSQL can handle it in < 100ms). For extreme scale, consider a materialized view or pg_trgm GIN indexes on commonly searched JSONB paths. YAGNI for now.

2. **Add delegation in `flows.ex`:**

```elixir
@doc """
Deep search: searches flow names/shortcuts and node content.
"""
@spec search_flows_deep(integer(), String.t(), keyword()) :: [flow()]
defdelegate search_flows_deep(project_id, query, opts \\ []), to: FlowCrud
```

3. **Wire a toggle in the search UI:**

In the component that shows search results, add a checkbox or toggle:

```elixir
<label class="label cursor-pointer gap-2">
  <span class="label-text text-xs">{dgettext("flows", "Search in content")}</span>
  <input
    type="checkbox"
    class="toggle toggle-xs"
    phx-click="toggle_deep_search"
    checked={@deep_search}
  />
</label>
```

The toggle sets `@deep_search` in assigns. The search handler checks this flag:

```elixir
results =
  if socket.assigns[:deep_search] do
    Flows.search_flows_deep(project_id, query, limit: 25, offset: 0)
  else
    Flows.search_flows(project_id, query, limit: 25, offset: 0)
  end
```

### Test Battery

**File:** `test/storyarn/flows/deep_search_test.exs`

```elixir
defmodule Storyarn.Flows.DeepSearchTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Flows

  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  setup do
    project = project_fixture()

    # Flow with matching name
    flow_by_name = flow_fixture(project, %{name: "Annah Dialogue"})

    # Flow with matching node content but different name
    flow_by_content = flow_fixture(project, %{name: "Hive Scene 7"})
    node_fixture(flow_by_content, %{
      type: "dialogue",
      data: %{"text" => "Annah whispers something about the Hive."}
    })

    # Flow with no match
    _unrelated = flow_fixture(project, %{name: "Morte Intro"})

    %{project: project, flow_by_name: flow_by_name, flow_by_content: flow_by_content}
  end

  describe "search_flows_deep/3" do
    test "finds flows by name", %{project: project, flow_by_name: flow} do
      results = Flows.search_flows_deep(project.id, "Annah")
      ids = Enum.map(results, & &1.id)
      assert flow.id in ids
    end

    test "finds flows by node content", %{project: project, flow_by_content: flow} do
      results = Flows.search_flows_deep(project.id, "Annah whispers")
      ids = Enum.map(results, & &1.id)
      assert flow.id in ids
    end

    test "returns both name and content matches", %{
      project: project,
      flow_by_name: flow_name,
      flow_by_content: flow_content
    } do
      results = Flows.search_flows_deep(project.id, "Annah")
      ids = Enum.map(results, & &1.id)
      assert flow_name.id in ids
      assert flow_content.id in ids
    end

    test "does not return unrelated flows", %{project: project} do
      results = Flows.search_flows_deep(project.id, "Annah")
      names = Enum.map(results, & &1.name)
      refute "Morte Intro" in names
    end

    test "empty query returns recent flows", %{project: project} do
      results = Flows.search_flows_deep(project.id, "")
      assert length(results) > 0
    end

    test "respects limit and offset", %{project: project} do
      results = Flows.search_flows_deep(project.id, "", limit: 1, offset: 0)
      assert length(results) == 1
    end

    test "searches hub_id in node data", %{project: project} do
      flow = flow_fixture(project, %{name: "Hub Flow"})
      node_fixture(flow, %{
        type: "hub",
        data: %{"hub_id" => "central-plaza", "label" => "Central Plaza"}
      })

      results = Flows.search_flows_deep(project.id, "central-plaza")
      ids = Enum.map(results, & &1.id)
      assert flow.id in ids
    end

    test "searches technical_id in node data", %{project: project} do
      flow = flow_fixture(project, %{name: "Tech ID Flow"})
      node_fixture(flow, %{
        type: "dialogue",
        data: %{"text" => "Hello", "technical_id" => "dlg_annah_01"}
      })

      results = Flows.search_flows_deep(project.id, "dlg_annah_01")
      ids = Enum.map(results, & &1.id)
      assert flow.id in ids
    end
  end
end
```

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Summary

| Subtask                | What it delivers                         | Can be used independently?                    |
|------------------------|------------------------------------------|-----------------------------------------------|
| 1. Limit + Offset      | More results, pagination support         | Yes (backend ready, consumers get 25 results) |
| 2. "Show More" UI      | Users can paginate through results       | Yes (visible UX improvement)                  |
| 3. Node Content Search | Find flows by dialogue text, labels, IDs | Yes (power user feature, optional)            |

### Performance Considerations

- **Subtask 1:** Adding `offset` to existing indexed queries has negligible cost. The limit increase from 10 to 25 adds minimal overhead (PostgreSQL fetches at most 25 rows).
- **Subtask 3:** The JSONB ILIKE queries can be slow on very large datasets. For the Torment scenario (~16,000 nodes), PostgreSQL handles this in < 100ms. If it becomes slow:
  - Add a GIN trigram index: `CREATE INDEX idx_flow_nodes_data_text ON flow_nodes USING GIN ((data->>'text') gin_trgm_ops);`
  - Or maintain a denormalized search text column on the flows table.
  - Both are future optimizations, not needed now (YAGNI).

### Interaction with Flow Tags (Document 05)

If Flow Tags are implemented first, the `search_flows/3` function already accepts a `:tag` option. The "Show more" UI can include a tag filter dropdown alongside the search input, combining text search with tag filtering for powerful navigation across 800+ flows.

**Next document:** [08_VARIABLE_USAGE_INDEX.md](./08_VARIABLE_USAGE_INDEX.md)
