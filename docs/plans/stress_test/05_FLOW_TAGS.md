# 05 — Flow Tags

> **Gap Reference:** Gap 6b from `COMPLEX_NARRATIVE_STRESS_TEST.md`
> **Priority:** MEDIUM
> **Effort:** Low
> **Dependencies:** None
> **Previous:** `04_EXPRESSION_SYSTEM.md`
> **Next:** `06_AUTO_LAYOUT.md`
> **Last Updated:** February 20, 2026

---

## Context

With 806 flows in the Planescape: Torment import scenario, users need a way to categorize and filter flows beyond name/shortcut search. Tags provide a lightweight, freeform taxonomy: `area:mortuary`, `area:hive`, `companion`, `merchant`, `quest:main`, etc.

## Current State

### Schema: `lib/storyarn/flows/flow.ex`

The Flow schema has these fields:

```elixir
schema "flows" do
  field :name, :string
  field :shortcut, :string
  field :description, :string
  field :position, :integer, default: 0
  field :is_main, :boolean, default: false
  field :settings, :map, default: %{}
  field :deleted_at, :utc_datetime
  # ... associations
end
```

No `tags` field exists. The `settings` map is used for per-flow configuration (not tags).

### CRUD: `lib/storyarn/flows/flow_crud.ex`

- `search_flows/2` queries by name and shortcut via `ILIKE`, returns max 10 results. No tag filtering.
- `create_flow/2` and `update_flow/2` pass attrs through `create_changeset/2` and `update_changeset/2`.

### Sidebar: `lib/storyarn_web/components/sidebar/flow_tree.ex`

- Renders the flow tree with a `TreeSearch` hook for client-side filtering by name.
- No tag display or filtering.

### Migration history: `priv/repo/migrations/`

- Most recent migration timestamp: `20260219132640`. New migrations should use a timestamp after this.

### Shortcut format (for reference): `~r/^[a-z0-9][a-z0-9.\-]*[a-z0-9]$|^[a-z0-9]$/`

---

## Subtask 1: Migration + Schema

**Goal:** Add a `tags` column to the `flows` table and update the Ecto schema and changesets.

### Files Affected

| File | Action |
|------|--------|
| `priv/repo/migrations/YYYYMMDDHHMMSS_add_tags_to_flows.exs` | New migration |
| `lib/storyarn/flows/flow.ex` | Add field, update changesets, add tag validations |

### Implementation Steps

1. **Generate migration:**

```bash
mix ecto.gen.migration add_tags_to_flows
```

2. **Write migration** (in the generated file):

```elixir
defmodule Storyarn.Repo.Migrations.AddTagsToFlows do
  use Ecto.Migration

  def change do
    alter table(:flows) do
      add :tags, {:array, :string}, default: [], null: false
    end

    # GIN index for fast array containment queries (@> operator)
    create index(:flows, [:tags], using: "GIN")
  end
end
```

3. **Update `lib/storyarn/flows/flow.ex`:**

Add the field to the schema block:

```elixir
field :tags, {:array, :string}, default: []
```

Add to the `@type t` spec:

```elixir
tags: [String.t()]
```

Update `create_changeset/2` and `update_changeset/2` to cast `:tags`:

```elixir
|> cast(attrs, [:name, :shortcut, :description, :is_main, :settings, :parent_id, :position, :tags])
```

Add tag validation (after the existing validations):

```elixir
|> validate_tags()
```

Add private validation function:

```elixir
@max_tags 20
@max_tag_length 50
@tag_format ~r/^[a-z0-9][a-z0-9:\-_.]*[a-z0-9]$|^[a-z0-9]$/

defp validate_tags(changeset) do
  changeset
  |> validate_length(:tags, max: @max_tags, message: "cannot have more than %{count} tags")
  |> validate_change(:tags, fn :tags, tags ->
    tags
    |> Enum.with_index()
    |> Enum.flat_map(fn {tag, _idx} ->
      cond do
        String.length(tag) > @max_tag_length ->
          [tags: "tag \"#{tag}\" is too long (max #{@max_tag_length} characters)"]
        not Regex.match?(@tag_format, tag) ->
          [tags: "tag \"#{tag}\" must be lowercase alphanumeric with colons, hyphens, dots, or underscores"]
        true ->
          []
      end
    end)
  end)
end
```

Tag format rationale: similar to the shortcut format but also allows colons (for namespaced tags like `area:mortuary`) and underscores. All lowercase, no spaces.

4. **Run migration:**

```bash
mix ecto.migrate
```

### Test Battery

**File:** `test/storyarn/flows/flow_tag_test.exs`

```elixir
defmodule Storyarn.Flows.FlowTagTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Flows.Flow

  describe "create_changeset/2 tags" do
    test "accepts empty tags" do
      changeset = Flow.create_changeset(%Flow{}, %{name: "Test", tags: []})
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :tags) == []
    end

    test "accepts valid tags" do
      tags = ["area:mortuary", "companion", "quest.main", "npc-merchant"]
      changeset = Flow.create_changeset(%Flow{}, %{name: "Test", tags: tags})
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :tags) == tags
    end

    test "rejects tags with spaces" do
      changeset = Flow.create_changeset(%Flow{}, %{name: "Test", tags: ["bad tag"]})
      refute changeset.valid?
    end

    test "rejects tags with uppercase" do
      changeset = Flow.create_changeset(%Flow{}, %{name: "Test", tags: ["BadTag"]})
      refute changeset.valid?
    end

    test "rejects more than 20 tags" do
      tags = Enum.map(1..21, &"tag#{&1}")
      changeset = Flow.create_changeset(%Flow{}, %{name: "Test", tags: tags})
      refute changeset.valid?
    end

    test "rejects tags longer than 50 characters" do
      long_tag = String.duplicate("a", 51)
      changeset = Flow.create_changeset(%Flow{}, %{name: "Test", tags: [long_tag]})
      refute changeset.valid?
    end

    test "defaults to empty list when tags not provided" do
      changeset = Flow.create_changeset(%Flow{}, %{name: "Test"})
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :tags) == []
    end
  end

  describe "update_changeset/2 tags" do
    test "updates tags" do
      flow = %Flow{name: "Test", tags: ["old"]}
      changeset = Flow.update_changeset(flow, %{tags: ["new", "tags"]})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :tags) == ["new", "tags"]
    end

    test "clears tags with empty list" do
      flow = %Flow{name: "Test", tags: ["existing"]}
      changeset = Flow.update_changeset(flow, %{tags: []})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :tags) == []
    end
  end
end
```

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 2: CRUD Operations for Tags

**Goal:** Add tag management functions to `FlowCrud` and expose them through the `Flows` facade. Include `list_project_tags/1` for autocomplete.

### Files Affected

| File | Action |
|------|--------|
| `lib/storyarn/flows/flow_crud.ex` | Add `add_tags/2`, `remove_tag/2`, `list_project_tags/1` |
| `lib/storyarn/flows.ex` | Expose new functions via `defdelegate` |

### Implementation Steps

1. **Add to `lib/storyarn/flows/flow_crud.ex`:**

```elixir
@doc """
Adds tags to a flow. Merges with existing tags, deduplicates.
"""
def add_tags(%Flow{} = flow, new_tags) when is_list(new_tags) do
  merged = Enum.uniq(flow.tags ++ new_tags)

  flow
  |> Flow.update_changeset(%{tags: merged})
  |> Repo.update()
end

@doc """
Removes a single tag from a flow.
"""
def remove_tag(%Flow{} = flow, tag) when is_binary(tag) do
  updated_tags = Enum.reject(flow.tags, &(&1 == tag))

  flow
  |> Flow.update_changeset(%{tags: updated_tags})
  |> Repo.update()
end

@doc """
Lists all unique tags used across non-deleted flows in a project.
Returns sorted list of tag strings. Used for autocomplete.
"""
def list_project_tags(project_id) do
  from(f in Flow,
    where: f.project_id == ^project_id and is_nil(f.deleted_at),
    select: f.tags
  )
  |> Repo.all()
  |> List.flatten()
  |> Enum.uniq()
  |> Enum.sort()
end
```

Note: `list_project_tags/1` uses a simple approach that loads all tag arrays and flattens in Elixir. For < 1,000 flows this is fine. If performance becomes an issue, switch to `unnest(tags)` in raw SQL. YAGNI for now.

2. **Add delegations to `lib/storyarn/flows.ex`:**

Under the Flows CRUD section, add:

```elixir
@doc """
Adds tags to a flow. Merges with existing tags, deduplicates.
"""
@spec add_tags(flow(), [String.t()]) :: {:ok, flow()} | {:error, changeset()}
defdelegate add_tags(flow, tags), to: FlowCrud

@doc """
Removes a single tag from a flow.
"""
@spec remove_tag(flow(), String.t()) :: {:ok, flow()} | {:error, changeset()}
defdelegate remove_tag(flow, tag), to: FlowCrud

@doc """
Lists all unique tags used across flows in a project. For autocomplete.
"""
@spec list_project_tags(integer()) :: [String.t()]
defdelegate list_project_tags(project_id), to: FlowCrud
```

### Test Battery

**File:** `test/storyarn/flows/flow_tags_crud_test.exs`

```elixir
defmodule Storyarn.Flows.FlowTagsCrudTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Flows

  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  setup do
    project = project_fixture()
    %{project: project}
  end

  describe "add_tags/2" do
    test "adds tags to a flow with no existing tags", %{project: project} do
      flow = flow_fixture(project)
      assert flow.tags == []

      {:ok, updated} = Flows.add_tags(flow, ["companion", "area:hive"])
      assert "companion" in updated.tags
      assert "area:hive" in updated.tags
    end

    test "merges with existing tags and deduplicates", %{project: project} do
      flow = flow_fixture(project, %{tags: ["existing"]})

      {:ok, updated} = Flows.add_tags(flow, ["existing", "new"])
      assert length(updated.tags) == 2
      assert "existing" in updated.tags
      assert "new" in updated.tags
    end

    test "rejects invalid tags", %{project: project} do
      flow = flow_fixture(project)
      {:error, changeset} = Flows.add_tags(flow, ["Invalid Tag"])
      assert changeset.errors[:tags]
    end
  end

  describe "remove_tag/2" do
    test "removes a tag from a flow", %{project: project} do
      flow = flow_fixture(project, %{tags: ["keep", "remove"]})

      {:ok, updated} = Flows.remove_tag(flow, "remove")
      assert updated.tags == ["keep"]
    end

    test "no-op when tag does not exist", %{project: project} do
      flow = flow_fixture(project, %{tags: ["existing"]})

      {:ok, updated} = Flows.remove_tag(flow, "nonexistent")
      assert updated.tags == ["existing"]
    end
  end

  describe "list_project_tags/1" do
    test "returns all unique tags across project flows", %{project: project} do
      flow_fixture(project, %{tags: ["companion", "area:hive"]})
      flow_fixture(project, %{tags: ["area:hive", "quest:main"]})
      flow_fixture(project, %{tags: ["merchant"]})

      tags = Flows.list_project_tags(project.id)
      assert tags == ["area:hive", "companion", "merchant", "quest:main"]
    end

    test "returns empty list when no flows have tags", %{project: project} do
      flow_fixture(project)
      assert Flows.list_project_tags(project.id) == []
    end

    test "excludes deleted flows", %{project: project} do
      flow = flow_fixture(project, %{tags: ["should-exclude"]})
      Flows.delete_flow(flow)

      assert Flows.list_project_tags(project.id) == []
    end
  end
end
```

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 3: Tag Editor UI in Flow Settings

**Goal:** Add a tag editor to the flow header area (inline, accessible from the flow editor view). Tags are displayed as badges below the flow name/shortcut. Clicking a badge removes it. A combobox input allows adding new tags with autocomplete from existing project tags.

### Files Affected

| File                                                                | Action                                                             |
|---------------------------------------------------------------------|--------------------------------------------------------------------|
| `lib/storyarn_web/live/flow_live/components/flow_header.ex`         | Add tag badges + tag input                                         |
| `lib/storyarn_web/live/flow_live/show.ex`                           | Load `project_tags` on mount, handle `add_tag`/`remove_tag` events |
| `lib/storyarn_web/live/flow_live/handlers/generic_node_handlers.ex` | Add `handle_add_tag/2`, `handle_remove_tag/2`                      |
| `assets/js/hooks/tag_input.js`                                      | New hook for tag autocomplete input                                |
| `assets/js/hooks/index.js`                                          | Register TagInput hook                                             |

### Implementation Steps

1. **Update `show.ex` mount** to load project tags:

In the `handle_params` or the data loading function (wherever `flow` is loaded), add:

```elixir
|> assign(:project_tags, Flows.list_project_tags(project.id))
```

Pass `project_tags` and `flow.tags` (via the `flow` assign) to the flow header component.

2. **Add tag display and input to `flow_header.ex`:**

Add a new attr:

```elixir
attr :project_tags, :list, default: []
```

Below the flow name/shortcut section, add a tags row:

```elixir
<%!-- Tags --%>
<div :if={@can_edit} class="flex items-center gap-1 flex-wrap">
  <span
    :for={tag <- @flow.tags}
    class="badge badge-sm badge-outline gap-1 cursor-pointer hover:badge-error"
    phx-click="remove_tag"
    phx-value-tag={tag}
  >
    {tag}
    <.icon name="x" class="size-3" />
  </span>
  <div
    id="flow-tag-input"
    phx-hook="TagInput"
    phx-update="ignore"
    data-tags={Jason.encode!(@project_tags)}
    class="inline-block"
  >
    <input
      type="text"
      placeholder={dgettext("flows", "Add tag...")}
      class="input input-xs input-ghost w-24 focus:w-40 transition-all"
      data-tag-input
    />
    <ul data-tag-suggestions class="hidden dropdown-content menu menu-xs bg-base-100 rounded-box shadow-lg border border-base-300 w-48 z-50 absolute"></ul>
  </div>
</div>
```

3. **Add event handlers to `show.ex`:**

```elixir
def handle_event("add_tag", %{"tag" => tag}, socket) do
  with_auth(:edit_content, socket, fn ->
    GenericNodeHandlers.handle_add_tag(%{"tag" => tag}, socket)
  end)
end

def handle_event("remove_tag", %{"tag" => tag}, socket) do
  with_auth(:edit_content, socket, fn ->
    GenericNodeHandlers.handle_remove_tag(%{"tag" => tag}, socket)
  end)
end
```

4. **Add handler functions in `generic_node_handlers.ex`:**

```elixir
@spec handle_add_tag(map(), Phoenix.LiveView.Socket.t()) ::
        {:noreply, Phoenix.LiveView.Socket.t()}
def handle_add_tag(%{"tag" => tag}, socket) do
  flow = socket.assigns.flow
  tag = tag |> String.trim() |> String.downcase()

  if tag == "" do
    {:noreply, socket}
  else
    case Flows.add_tags(flow, [tag]) do
      {:ok, updated_flow} ->
        project_tags = Flows.list_project_tags(updated_flow.project_id)
        schedule_save_status_reset()

        {:noreply,
         socket
         |> assign(:flow, updated_flow)
         |> assign(:project_tags, project_tags)
         |> assign(:save_status, :saved)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, dgettext("flows", "Invalid tag format."))}
    end
  end
end

@spec handle_remove_tag(map(), Phoenix.LiveView.Socket.t()) ::
        {:noreply, Phoenix.LiveView.Socket.t()}
def handle_remove_tag(%{"tag" => tag}, socket) do
  flow = socket.assigns.flow

  case Flows.remove_tag(flow, tag) do
    {:ok, updated_flow} ->
      schedule_save_status_reset()

      {:noreply,
       socket
       |> assign(:flow, updated_flow)
       |> assign(:save_status, :saved)}

    {:error, _changeset} ->
      {:noreply, socket}
  end
end
```

5. **Create `assets/js/hooks/tag_input.js`:**

```javascript
/**
 * TagInput hook — autocomplete for flow tags.
 *
 * Reads existing project tags from data-tags attribute.
 * On input, filters and shows suggestions dropdown.
 * On Enter or suggestion click, pushes "add_tag" event to server.
 */
export const TagInput = {
  mounted() {
    this.allTags = JSON.parse(this.el.dataset.tags || "[]");
    this.input = this.el.querySelector("[data-tag-input]");
    this.suggestions = this.el.querySelector("[data-tag-suggestions]");

    this.input.addEventListener("input", () => this.onInput());
    this.input.addEventListener("keydown", (e) => this.onKeydown(e));
    this.input.addEventListener("blur", () => {
      // Delay to allow click on suggestion
      setTimeout(() => this.hideSuggestions(), 150);
    });
  },

  onInput() {
    const query = this.input.value.trim().toLowerCase();
    if (query.length === 0) {
      this.hideSuggestions();
      return;
    }

    const matches = this.allTags
      .filter((tag) => tag.includes(query))
      .slice(0, 8);

    if (matches.length === 0) {
      this.hideSuggestions();
      return;
    }

    this.suggestions.innerHTML = matches
      .map((tag) => `<li><button type="button" data-tag="${tag}">${tag}</button></li>`)
      .join("");

    this.suggestions.querySelectorAll("button").forEach((btn) => {
      btn.addEventListener("mousedown", (e) => {
        e.preventDefault();
        this.submitTag(btn.dataset.tag);
      });
    });

    this.suggestions.classList.remove("hidden");
  },

  onKeydown(e) {
    if (e.key === "Enter") {
      e.preventDefault();
      const tag = this.input.value.trim().toLowerCase();
      if (tag) this.submitTag(tag);
    }
    if (e.key === "Escape") {
      this.hideSuggestions();
      this.input.blur();
    }
  },

  submitTag(tag) {
    this.pushEvent("add_tag", { tag });
    this.input.value = "";
    this.hideSuggestions();
  },

  hideSuggestions() {
    this.suggestions.classList.add("hidden");
  },

  updated() {
    // Re-read tags when server pushes updates
    this.allTags = JSON.parse(this.el.dataset.tags || "[]");
  },
};
```

6. **Register hook in `assets/js/hooks/index.js`:**

```javascript
import { TagInput } from "./tag_input.js";
// ... in the hooks object:
TagInput,
```

### Test Battery

**File:** `test/storyarn_web/live/flow_live/flow_tags_test.exs`

```elixir
defmodule StoryarnWeb.FlowLive.FlowTagsTest do
  use StoryarnWeb.ConnCase, async: true

  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  # Integration test for tag events via LiveView
  # Tests the handle_event -> handler -> context -> DB round trip

  setup do
    user = user_fixture()
    workspace = workspace_fixture(user)
    project = project_fixture(workspace)
    flow = flow_fixture(project)
    %{user: user, workspace: workspace, project: project, flow: flow}
  end

  describe "add_tag event" do
    test "adds a tag and updates assigns", %{
      conn: conn, user: user, workspace: workspace, project: project, flow: flow
    } do
      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/flows/#{flow.id}")

      view |> render_hook("add_tag", %{"tag" => "companion"})

      updated_flow = Storyarn.Flows.get_flow(project.id, flow.id)
      assert "companion" in updated_flow.tags
    end
  end

  describe "remove_tag event" do
    test "removes a tag", %{
      conn: conn, user: user, workspace: workspace, project: project, flow: flow
    } do
      {:ok, _} = Storyarn.Flows.add_tags(flow, ["remove-me"])

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/flows/#{flow.id}")

      view |> render_hook("remove_tag", %{"tag" => "remove-me"})

      updated_flow = Storyarn.Flows.get_flow(project.id, flow.id)
      refute "remove-me" in updated_flow.tags
    end
  end
end
```

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 4: Tag Badges in Flow Tree Sidebar

**Goal:** Display tag badges on flows in the sidebar tree, and allow filtering the tree by tag.

### Files Affected

| File                                                                          | Action                                                |
|-------------------------------------------------------------------------------|-------------------------------------------------------|
| `lib/storyarn_web/components/sidebar/flow_tree.ex`                            | Add tag badges to tree nodes, add tag filter dropdown |
| `lib/storyarn_web/live/project_live/show.ex` (or wherever sidebar is mounted) | Load project tags, handle `filter_by_tag` event       |

### Implementation Steps

1. **Add tag badges to `flow_tree.ex`:**

In the `flow_tree_items` component, after the flow name in both `tree_node` and `tree_leaf`, add a tag display:

```elixir
<span :for={tag <- Enum.take(@flow.tags, 2)} class="badge badge-xs badge-ghost ml-1 opacity-60">
  {tag}
</span>
<span :if={length(@flow.tags) > 2} class="text-xs opacity-40 ml-1">
  +{length(@flow.tags) - 2}
</span>
```

The tree node only shows the first 2 tags to avoid overflow. The `+N` indicator shows if there are more.

2. **Add tag filter to `flows_section`:**

Above the search input, add a tag filter dropdown:

```elixir
<div :if={@project_tags != []} class="mb-1">
  <select
    class="select select-xs select-bordered w-full"
    phx-change="filter_flows_by_tag"
    name="tag"
  >
    <option value="">{dgettext("flows", "All tags")}</option>
    <option :for={tag <- @project_tags} value={tag}>{tag}</option>
  </select>
</div>
```

Add the `project_tags` attr:

```elixir
attr :project_tags, :list, default: []
```

3. **Handle tag filtering:**

In the parent LiveView that renders the sidebar, handle the `filter_flows_by_tag` event:

```elixir
def handle_event("filter_flows_by_tag", %{"tag" => ""}, socket) do
  # Clear filter, show full tree
  flows_tree = Flows.list_flows_tree(socket.assigns.project.id)
  {:noreply, assign(socket, :flows_tree, flows_tree)}
end

def handle_event("filter_flows_by_tag", %{"tag" => tag}, socket) do
  flows_tree = Flows.list_flows_tree(socket.assigns.project.id)
  filtered = filter_tree_by_tag(flows_tree, tag)
  {:noreply, assign(socket, :flows_tree, filtered)}
end

defp filter_tree_by_tag(flows, tag) do
  Enum.flat_map(flows, fn flow ->
    has_tag = tag in (flow.tags || [])
    children = filter_tree_by_tag(flow.children, tag)

    if has_tag or children != [] do
      [%{flow | children: children}]
    else
      []
    end
  end)
end
```

This preserves tree structure: parent flows are kept if any descendant matches the tag, even if the parent itself does not have the tag.

### Test Battery

**File:** `test/storyarn/flows/flow_tag_filter_test.exs`

```elixir
defmodule Storyarn.Flows.FlowTagFilterTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Flows

  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  setup do
    project = project_fixture()
    %{project: project}
  end

  describe "list_flows_tree/1 with tags" do
    test "flows include tags in tree", %{project: project} do
      flow_fixture(project, %{tags: ["companion", "area:hive"]})

      [flow | _] = Flows.list_flows_tree(project.id)
      assert is_list(flow.tags)
      assert "companion" in flow.tags
    end
  end

  describe "tag filtering logic" do
    test "filters tree to only flows with matching tag", %{project: project} do
      flow_fixture(project, %{name: "Annah", tags: ["companion"]})
      flow_fixture(project, %{name: "Merchant", tags: ["merchant"]})

      tree = Flows.list_flows_tree(project.id)

      # Simulate the filter function
      filtered =
        Enum.filter(tree, fn flow ->
          "companion" in (flow.tags || [])
        end)

      assert length(filtered) == 1
      assert hd(filtered).name == "Annah"
    end
  end
end
```

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 5: Search Flows by Tag

**Goal:** Extend `search_flows/2` to accept an optional tag filter, so the search can narrow results by tag in addition to name/shortcut matching.

### Files Affected

| File                              | Action                                                  |
|-----------------------------------|---------------------------------------------------------|
| `lib/storyarn/flows/flow_crud.ex` | Extend `search_flows` to accept opts with `:tag` filter |
| `lib/storyarn/flows.ex`           | Update delegation if signature changes                  |

### Implementation Steps

1. **Add `search_flows/3` overload to `flow_crud.ex`:**

```elixir
@doc """
Searches flows by name or shortcut, with optional tag filter.
Accepts opts: [tag: "companion"]
"""
def search_flows(project_id, query, opts) when is_binary(query) and is_list(opts) do
  tag = Keyword.get(opts, :tag)
  query_str = String.trim(query)

  base_query =
    from(f in Flow,
      where: f.project_id == ^project_id and is_nil(f.deleted_at)
    )

  # Apply tag filter if provided
  base_query =
    if tag && tag != "" do
      from(f in base_query, where: ^tag in f.tags)
    else
      base_query
    end

  if query_str == "" do
    from(f in base_query,
      order_by: [desc: f.updated_at],
      limit: 10
    )
    |> Repo.all()
  else
    search_term = "%#{query_str}%"

    from(f in base_query,
      where: ilike(f.name, ^search_term) or ilike(f.shortcut, ^search_term),
      order_by: [asc: f.name],
      limit: 10
    )
    |> Repo.all()
  end
end
```

Note: The `^tag in f.tags` syntax uses PostgreSQL's `= ANY()` operator through Ecto. For the GIN-indexed `@>` operator, use `fragment("? @> ?", f.tags, ^[tag])` instead if performance requires it. The simpler syntax is correct for now.

2. **Keep the existing `search_flows/2` as-is** (no breaking change). The new overload is additive.

3. **Add delegation in `flows.ex`:**

```elixir
@doc """
Searches flows by name or shortcut, with optional tag filter.
"""
@spec search_flows(integer(), String.t(), keyword()) :: [flow()]
defdelegate search_flows(project_id, query, opts), to: FlowCrud
```

### Test Battery

**File:** `test/storyarn/flows/flow_tag_search_test.exs`

```elixir
defmodule Storyarn.Flows.FlowTagSearchTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Flows

  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  setup do
    project = project_fixture()

    flow_fixture(project, %{name: "Annah Companion", tags: ["companion", "area:hive"]})
    flow_fixture(project, %{name: "Hive Merchant", tags: ["merchant", "area:hive"]})
    flow_fixture(project, %{name: "Morte Companion", tags: ["companion", "area:mortuary"]})
    flow_fixture(project, %{name: "No Tags Flow"})

    %{project: project}
  end

  describe "search_flows/3 with tag filter" do
    test "filters by tag only (empty query)", %{project: project} do
      results = Flows.search_flows(project.id, "", tag: "companion")
      assert length(results) == 2
      names = Enum.map(results, & &1.name)
      assert "Annah Companion" in names
      assert "Morte Companion" in names
    end

    test "combines text search with tag filter", %{project: project} do
      results = Flows.search_flows(project.id, "Annah", tag: "companion")
      assert length(results) == 1
      assert hd(results).name == "Annah Companion"
    end

    test "returns empty when tag matches but text does not", %{project: project} do
      results = Flows.search_flows(project.id, "Nonexistent", tag: "companion")
      assert results == []
    end

    test "returns all matching text when tag is nil", %{project: project} do
      results = Flows.search_flows(project.id, "Companion", tag: nil)
      assert length(results) == 2
    end

    test "returns all matching text when tag is empty string", %{project: project} do
      results = Flows.search_flows(project.id, "Merchant", tag: "")
      assert length(results) == 1
    end
  end
end
```

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Summary

| Subtask                 | What it delivers                         | Can be used independently?  |
|-------------------------|------------------------------------------|-----------------------------|
| 1. Migration + Schema   | Tags stored in DB, validated on save     | Yes (data layer ready)      |
| 2. CRUD Operations      | Add/remove tags, autocomplete list       | Yes (API complete)          |
| 3. Tag Editor UI        | Users can add/remove tags in flow editor | Yes (full editing UX)       |
| 4. Tree Badges + Filter | Tags visible in sidebar, filterable      | Yes (discovery UX)          |
| 5. Search by Tag        | Search respects tag filter               | Yes (power search)          |

**Next document:** [06_AUTO_LAYOUT.md](./06_AUTO_LAYOUT.md)
