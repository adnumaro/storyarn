# Phase 7.5 - Implementation Plan for Fixes

> **Generated:** February 3, 2026
> **Source:** Comprehensive audit of Phase 7.5 Pages Enhancement
> **Purpose:** Guide for fixing all identified issues in priority order

---

## Table of Contents

1. [Critical Security Fixes (P0)](#1-critical-security-fixes-p0)
2. [High Priority Fixes (P1)](#2-high-priority-fixes-p1)
3. [Medium Priority Fixes (P2)](#3-medium-priority-fixes-p2)
4. [Low Priority Fixes (P3)](#4-low-priority-fixes-p3)
5. [Test Coverage Tasks](#5-test-coverage-tasks)
6. [Code Quality Refactoring](#6-code-quality-refactoring)

---

## 1. Critical Security Fixes (P0)

### 1.1 IDOR Vulnerability in Block Operations

**Problem:** Block operations retrieve blocks by ID without validating project ownership. Users can modify blocks in other projects.

**Files to modify:**
- `lib/storyarn/pages/block_crud.ex`
- `lib/storyarn_web/live/page_live/helpers/block_helpers.ex`

**Implementation Steps:**

1. **Add project-scoped block getter in `block_crud.ex`:**

```elixir
# Add after line 31 in lib/storyarn/pages/block_crud.ex

@doc """
Gets a block by ID, ensuring it belongs to the specified project.
Returns nil if not found or not in project.
"""
def get_block_in_project(block_id, project_id) do
  from(b in Block,
    join: p in Page,
    on: b.page_id == p.id,
    where: b.id == ^block_id and p.project_id == ^project_id and is_nil(b.deleted_at) and is_nil(p.deleted_at),
    select: b
  )
  |> Repo.one()
end

@doc """
Gets a block by ID with project validation. Raises if not found.
"""
def get_block_in_project!(block_id, project_id) do
  case get_block_in_project(block_id, project_id) do
    nil -> raise Ecto.NoResultsError, queryable: Block
    block -> block
  end
end
```

2. **Add delegation in `pages.ex` facade:**

```elixir
# Add in lib/storyarn/pages.ex under Blocks section

@doc "Gets a block by ID, ensuring it belongs to the specified project."
defdelegate get_block_in_project(block_id, project_id), to: BlockCrud

@doc "Gets a block by ID with project validation. Raises if not found."
defdelegate get_block_in_project!(block_id, project_id), to: BlockCrud
```

3. **Update all block helpers to use project-scoped getter:**

```elixir
# In lib/storyarn_web/live/page_live/helpers/block_helpers.ex
# Replace ALL occurrences of:
#   block = Pages.get_block!(block_id)
# With:
#   block = Pages.get_block_in_project!(block_id, socket.assigns.project.id)

# Functions to update (with line numbers):
# - update_block_value/3 (line 48)
# - delete_block/2 (line 72)
# - toggle_multi_select/3 (line 116)
# - handle_multi_select_enter/3 (line 146)
# - update_rich_text/3 (line 176)
# - set_boolean_block/3 (line 195)
```

**Testing:**
```elixir
# Add to test/storyarn/pages_test.exs
describe "get_block_in_project/2" do
  test "returns block when in correct project" do
    # Create project, page, block
    # Assert get_block_in_project returns block
  end

  test "returns nil when block is in different project" do
    # Create two projects with blocks
    # Assert get_block_in_project returns nil for cross-project access
  end

  test "returns nil for deleted blocks" do
    # Create soft-deleted block
    # Assert returns nil
  end
end
```

---

### 1.2 IDOR in Reference Block - Cross-Project References

**Problem:** Reference blocks accept any target_id without validating it belongs to the current project.

**Files to modify:**
- `lib/storyarn_web/live/page_live/show.ex`
- `lib/storyarn/pages/page_crud.ex`

**Implementation Steps:**

1. **Add validation function in `page_crud.ex`:**

```elixir
# Add in lib/storyarn/pages/page_crud.ex

@doc """
Validates that a reference target exists and belongs to the project.
Returns {:ok, target} or {:error, :not_found}.
"""
def validate_reference_target(target_type, target_id, project_id) do
  case target_type do
    "page" ->
      case get_page(project_id, target_id) do
        nil -> {:error, :not_found}
        page -> {:ok, page}
      end

    "flow" ->
      alias Storyarn.Flows
      case Flows.get_flow(project_id, target_id) do
        nil -> {:error, :not_found}
        flow -> {:ok, flow}
      end

    _ ->
      {:error, :invalid_type}
  end
end
```

2. **Update `select_reference` handler in `show.ex`:**

```elixir
# Replace lines 739-765 in lib/storyarn_web/live/page_live/show.ex

def handle_event(
      "select_reference",
      %{"block-id" => block_id, "type" => target_type, "id" => target_id},
      socket
    ) do
  with_authorization(socket, :edit_content, fn socket ->
    project_id = socket.assigns.project.id
    block = Pages.get_block_in_project!(block_id, project_id)

    case Integer.parse(target_id) do
      {target_id_int, ""} ->
        # Validate target belongs to this project
        case Pages.validate_reference_target(target_type, target_id_int, project_id) do
          {:ok, _target} ->
            case Pages.update_block_value(block, %{
                   "target_type" => target_type,
                   "target_id" => target_id_int
                 }) do
              {:ok, _block} ->
                blocks = Pages.list_blocks(socket.assigns.page.id)
                {:noreply, assign(socket, :blocks, blocks)}

              {:error, _changeset} ->
                {:noreply, put_flash(socket, :error, gettext("Failed to set reference"))}
            end

          {:error, :not_found} ->
            {:noreply, put_flash(socket, :error, gettext("Reference target not found"))}

          {:error, :invalid_type} ->
            {:noreply, put_flash(socket, :error, gettext("Invalid reference type"))}
        end

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Invalid reference ID"))}
    end
  end)
end
```

**Testing:**
```elixir
# Add to test/storyarn/pages_test.exs
describe "validate_reference_target/3" do
  test "returns {:ok, page} for valid page in project"
  test "returns {:ok, flow} for valid flow in project"
  test "returns {:error, :not_found} for page in different project"
  test "returns {:error, :not_found} for deleted page"
  test "returns {:error, :invalid_type} for unknown type"
end
```

---

### 1.3 XSS Vulnerability in Tiptap Mention Rendering

**Problem:** The `renderHTML` function uses unescaped attributes in HTML.

**File to modify:**
- `assets/js/hooks/tiptap_editor.js`

**Implementation Steps:**

1. **Add escape function and update renderHTML:**

```javascript
// Add after line 3 in assets/js/hooks/tiptap_editor.js

// HTML attribute escaping for security
function escapeAttr(str) {
  if (str == null) return "";
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

// Update the renderHTML function (around line 95-109)
// Replace with:
renderHTML({ node }) {
  const attrs = node.attrs;
  return [
    "span",
    {
      class:
        "mention inline-flex items-center gap-1 px-1.5 py-0.5 rounded bg-primary/10 text-primary font-medium text-sm cursor-pointer hover:bg-primary/20 transition-colors",
      "data-type": escapeAttr(attrs.type || "page"),
      "data-id": escapeAttr(attrs.id),
      "data-label": escapeAttr(attrs.label),
      contenteditable: "false",
    },
    `#${escapeHtml(attrs.label || "")}`,
  ];
},
```

**Testing:**
- Manual test: Create a page with name containing `" onclick="alert('xss')`
- Verify the mention renders safely without executing JavaScript
- Check that special characters display correctly

---

### 1.4 Missing Foreign Key Constraints on entity_references

**Problem:** No FK constraints, causing orphaned references and no cascade delete.

**File to create:**
- `priv/repo/migrations/YYYYMMDDHHMMSS_add_entity_references_cleanup.exs`

**Implementation Steps:**

1. **Create new migration:**

```elixir
# Run: mix ecto.gen.migration add_entity_references_cleanup

defmodule Storyarn.Repo.Migrations.AddEntityReferencesCleanup do
  use Ecto.Migration

  def up do
    # Add composite index for efficient deletion queries
    create_if_not_exists index(:entity_references, [:source_type, :source_id])

    # Note: We cannot add traditional FKs because source/target can be
    # different tables (pages, flows, blocks). Instead, we'll handle
    # cleanup in application code and add a periodic cleanup job.

    # Add index for faster backlink queries
    create_if_not_exists index(:entity_references, [:target_type, :target_id, :source_type])
  end

  def down do
    drop_if_exists index(:entity_references, [:source_type, :source_id])
    drop_if_exists index(:entity_references, [:target_type, :target_id, :source_type])
  end
end
```

2. **Add cleanup function in `reference_tracker.ex`:**

```elixir
# Add in lib/storyarn/pages/reference_tracker.ex

@doc """
Cleans up orphaned references where source or target no longer exists.
Should be called periodically or after bulk deletions.
"""
def cleanup_orphaned_references do
  # Clean up references where source block no longer exists
  from(r in EntityReference,
    where: r.source_type == "block",
    where: fragment("NOT EXISTS (SELECT 1 FROM blocks WHERE id = ?)", r.source_id)
  )
  |> Repo.delete_all()

  # Clean up references where target page no longer exists (hard deleted)
  from(r in EntityReference,
    where: r.target_type == "page",
    where: fragment("NOT EXISTS (SELECT 1 FROM pages WHERE id = ?)", r.target_id)
  )
  |> Repo.delete_all()

  # Clean up references where target flow no longer exists
  from(r in EntityReference,
    where: r.target_type == "flow",
    where: fragment("NOT EXISTS (SELECT 1 FROM flows WHERE id = ?)", r.target_id)
  )
  |> Repo.delete_all()

  :ok
end
```

3. **Call cleanup when permanently deleting pages:**

```elixir
# Update lib/storyarn/pages/page_crud.ex permanently_delete_page/1

def permanently_delete_page(%Page{} = page) do
  # Delete all versions first
  from(v in PageVersion, where: v.page_id == ^page.id)
  |> Repo.delete_all()

  # Delete references where this page is the target
  ReferenceTracker.delete_target_references("page", page.id)

  # Delete the page (blocks cascade via FK)
  Repo.delete(page)
end
```

4. **Add target reference deletion in `reference_tracker.ex`:**

```elixir
@doc """
Deletes all references pointing to a specific target.
"""
def delete_target_references(target_type, target_id) do
  from(r in EntityReference,
    where: r.target_type == ^target_type and r.target_id == ^target_id
  )
  |> Repo.delete_all()
end
```

---

## 2. High Priority Fixes (P1)

### 2.1 Config Panel Events Missing Authorization

**Problem:** `add_select_option`, `remove_select_option`, `update_select_option` events don't check authorization.

**File to modify:**
- `lib/storyarn_web/live/page_live/show.ex`

**Implementation:**

```elixir
# Replace lines 705-720 in show.ex

def handle_event("add_select_option", _params, socket) do
  with_authorization(socket, :edit_content, fn socket ->
    ConfigHelpers.add_select_option(socket)
  end)
end

def handle_event("remove_select_option", %{"index" => index}, socket) do
  with_authorization(socket, :edit_content, fn socket ->
    ConfigHelpers.remove_select_option(socket, index)
  end)
end

def handle_event("update_select_option", %{"index" => index, "key" => key, "value" => value}, socket) do
  with_authorization(socket, :edit_content, fn socket ->
    ConfigHelpers.update_select_option(socket, index, key, value)
  end)
end
```

---

### 2.2 Flow Node Reference Tracking Not Implemented

**Problem:** Flow nodes with rich_text or speaker references don't track entity references.

**Files to modify:**
- `lib/storyarn/flows/node_crud.ex`
- `lib/storyarn/pages/reference_tracker.ex`

**Implementation Steps:**

1. **Add flow node reference tracking in `reference_tracker.ex`:**

```elixir
# Add in lib/storyarn/pages/reference_tracker.ex

@doc """
Updates references for a flow node based on its data.
Extracts mentions from rich text fields and speaker references.
"""
def update_flow_node_references(%{id: node_id, data: data}) when is_map(data) do
  # Delete existing references from this node
  delete_flow_node_references(node_id)

  references = extract_flow_node_refs(data)

  for ref <- references do
    target_id = parse_id(ref.id)

    if target_id do
      %EntityReference{}
      |> EntityReference.changeset(%{
        source_type: "flow_node",
        source_id: node_id,
        target_type: ref.type,
        target_id: target_id,
        context: ref.context
      })
      |> Repo.insert(on_conflict: :nothing)
    end
  end

  :ok
end

def delete_flow_node_references(node_id) do
  from(r in EntityReference,
    where: r.source_type == "flow_node" and r.source_id == ^node_id
  )
  |> Repo.delete_all()
end

defp extract_flow_node_refs(data) do
  refs = []

  # Extract speaker reference
  refs =
    if speaker_id = get_in(data, ["speaker", "id"]) do
      [%{type: "page", id: speaker_id, context: "speaker"} | refs]
    else
      refs
    end

  # Extract mentions from dialogue text
  refs =
    if text = get_in(data, ["text"]) do
      mentions = extract_mentions_from_html(text)
      Enum.map(mentions, fn m -> Map.put(m, :context, "dialogue") end) ++ refs
    else
      refs
    end

  refs
end
```

2. **Update `node_crud.ex` to call reference tracking:**

```elixir
# In lib/storyarn/flows/node_crud.ex, update update_node_data/2

def update_node_data(%FlowNode{} = node, data) do
  result =
    node
    |> FlowNode.data_changeset(%{data: data})
    |> Repo.update()

  case result do
    {:ok, updated_node} ->
      # Track references in node data
      alias Storyarn.Pages.ReferenceTracker
      ReferenceTracker.update_flow_node_references(updated_node)
      {:ok, updated_node}

    error ->
      error
  end
end

# Update delete_node/1
def delete_node(%FlowNode{} = node) do
  alias Storyarn.Pages.ReferenceTracker
  ReferenceTracker.delete_flow_node_references(node.id)
  Repo.delete(node)
end
```

---

### 2.3 TreeOperations Missing deleted_at Filter

**Problem:** `list_pages_by_parent/2` and `update_position_only/2` don't filter deleted pages.

**File to modify:**
- `lib/storyarn/pages/tree_operations.ex`

**Implementation:**

```elixir
# Update list_pages_by_parent/2 (around line 102-107)

def list_pages_by_parent(project_id, parent_id) do
  from(p in Page,
    where: p.project_id == ^project_id,
    where: is_nil(p.deleted_at),  # ADD THIS LINE
    where: ^if(parent_id, do: dynamic([p], p.parent_id == ^parent_id), else: dynamic([p], is_nil(p.parent_id))),
    order_by: [asc: p.position]
  )
  |> Repo.all()
end

# Update update_position_only/2 to validate page is not deleted (around line 86)

def update_position_only(%Page{} = page, position) do
  if page.deleted_at do
    {:error, :page_deleted}
  else
    page
    |> Page.position_changeset(%{position: position})
    |> Repo.update()
  end
end
```

---

### 2.4 Block Hard-Deletes Instead of Soft-Delete

**Problem:** `delete_block/1` permanently deletes blocks instead of soft-deleting.

**File to modify:**
- `lib/storyarn/pages/block_crud.ex`
- `lib/storyarn/pages/block.ex`

**Implementation Steps:**

1. **Add soft delete changeset in `block.ex`:**

```elixir
# Add in lib/storyarn/pages/block.ex

def delete_changeset(block) do
  change(block, deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
end

def restore_changeset(block) do
  change(block, deleted_at: nil)
end
```

2. **Update `block_crud.ex`:**

```elixir
# Replace delete_block/1 (lines 90-94)

@doc """
Soft-deletes a block by setting deleted_at timestamp.
"""
def delete_block(%Block{} = block) do
  ReferenceTracker.delete_block_references(block.id)

  block
  |> Block.delete_changeset()
  |> Repo.update()
end

@doc """
Permanently deletes a block from the database.
"""
def permanently_delete_block(%Block{} = block) do
  ReferenceTracker.delete_block_references(block.id)
  Repo.delete(block)
end

@doc """
Restores a soft-deleted block.
"""
def restore_block(%Block{} = block) do
  block
  |> Block.restore_changeset()
  |> Repo.update()
end
```

3. **Add delegation in `pages.ex`:**

```elixir
@doc "Soft-deletes a block."
defdelegate delete_block(block), to: BlockCrud

@doc "Permanently deletes a block."
defdelegate permanently_delete_block(block), to: BlockCrud

@doc "Restores a soft-deleted block."
defdelegate restore_block(block), to: BlockCrud
```

---

### 2.5 N+1 Query in get_backlinks_with_sources

**Problem:** Each backlink triggers a separate database query.

**File to modify:**
- `lib/storyarn/pages/reference_tracker.ex`

**Implementation:**

```elixir
# Replace get_backlinks_with_sources/3 (lines 90-113)

def get_backlinks_with_sources(target_type, target_id, project_id) do
  # Single query to get all references with their sources
  block_refs =
    from(r in EntityReference,
      join: b in Block,
      on: r.source_type == "block" and r.source_id == b.id,
      join: p in Page,
      on: b.page_id == p.id,
      where: r.target_type == ^target_type and r.target_id == ^target_id,
      where: p.project_id == ^project_id and is_nil(p.deleted_at) and is_nil(b.deleted_at),
      select: %{
        id: r.id,
        source_type: r.source_type,
        source_id: r.source_id,
        context: r.context,
        block_type: b.type,
        block_label: fragment("?->>'label'", b.config),
        page_id: p.id,
        page_name: p.name,
        page_shortcut: p.shortcut
      }
    )
    |> Repo.all()

  flow_node_refs =
    from(r in EntityReference,
      join: n in Storyarn.Flows.FlowNode,
      on: r.source_type == "flow_node" and r.source_id == n.id,
      join: f in Storyarn.Flows.Flow,
      on: n.flow_id == f.id,
      where: r.target_type == ^target_type and r.target_id == ^target_id,
      where: f.project_id == ^project_id,
      select: %{
        id: r.id,
        source_type: r.source_type,
        source_id: r.source_id,
        context: r.context,
        node_type: n.type,
        flow_id: f.id,
        flow_name: f.name,
        flow_shortcut: f.shortcut
      }
    )
    |> Repo.all()

  # Transform to expected format
  block_backlinks =
    Enum.map(block_refs, fn ref ->
      %{
        id: ref.id,
        source_type: "block",
        source_id: ref.source_id,
        context: ref.context,
        source_info: %{
          type: :page,
          page_id: ref.page_id,
          page_name: ref.page_name,
          page_shortcut: ref.page_shortcut,
          block_type: ref.block_type,
          block_label: ref.block_label
        }
      }
    end)

  flow_backlinks =
    Enum.map(flow_node_refs, fn ref ->
      %{
        id: ref.id,
        source_type: "flow_node",
        source_id: ref.source_id,
        context: ref.context,
        source_info: %{
          type: :flow,
          flow_id: ref.flow_id,
          flow_name: ref.flow_name,
          flow_shortcut: ref.flow_shortcut,
          node_type: ref.node_type
        }
      }
    end)

  block_backlinks ++ flow_backlinks
end
```

---

## 3. Medium Priority Fixes (P2)

### 3.1 Restored Pages Don't Restore Blocks

**File to modify:**
- `lib/storyarn/pages/page_crud.ex`

**Implementation:**

```elixir
# Replace restore_page/1 (lines 171-179)

def restore_page(%Page{} = page) do
  Ecto.Multi.new()
  |> Ecto.Multi.update(:page, Page.restore_changeset(page))
  |> Ecto.Multi.run(:restore_blocks, fn repo, _changes ->
    # Restore all soft-deleted blocks for this page
    from(b in Block,
      where: b.page_id == ^page.id and not is_nil(b.deleted_at)
    )
    |> repo.update_all(set: [deleted_at: nil])

    {:ok, :restored}
  end)
  |> Repo.transaction()
  |> case do
    {:ok, %{page: page}} -> {:ok, page}
    {:error, _op, changeset, _changes} -> {:error, changeset}
  end
end
```

---

### 3.2 Soft-Deleted Source Pages Still Appear in Backlinks

**File to modify:**
- `lib/storyarn/pages/reference_tracker.ex`

Already fixed in section 2.5 - the optimized query includes `is_nil(p.deleted_at)` filter.

---

### 3.3 Thread Safety: Reference Updates Not in Transaction

**File to modify:**
- `lib/storyarn/pages/block_crud.ex`

**Implementation:**

```elixir
# Replace update_block_value/2 (lines 63-81)

def update_block_value(%Block{} = block, value) do
  Ecto.Multi.new()
  |> Ecto.Multi.update(:block, Block.value_changeset(block, %{value: value}))
  |> Ecto.Multi.run(:update_references, fn _repo, %{block: updated_block} ->
    if updated_block.type in ["reference", "rich_text"] do
      ReferenceTracker.update_block_references(updated_block)
    end
    {:ok, :done}
  end)
  |> Repo.transaction()
  |> case do
    {:ok, %{block: block}} -> {:ok, block}
    {:error, :block, changeset, _} -> {:error, changeset}
    {:error, _, reason, _} -> {:error, reason}
  end
end
```

---

### 3.4 Version Snapshot Includes Invalid Block IDs

**Problem:** Block IDs in snapshots become meaningless after restore.

**File to modify:**
- `lib/storyarn/pages/versioning.ex`

**Implementation:**

```elixir
# Update block_to_snapshot/1 (lines 264-274)
# Remove the id field from snapshot

defp block_to_snapshot(%Block{} = block) do
  %{
    # "id" removed - IDs are not preserved on restore
    "type" => block.type,
    "position" => block.position,
    "config" => block.config,
    "value" => block.value,
    "is_constant" => block.is_constant,
    "variable_name" => block.variable_name
  }
end
```

---

### 3.5 Boolean Blocks Default to false Instead of nil

**File to modify:**
- `lib/storyarn/pages/block.ex`

**Implementation:**

```elixir
# Update default_value/1 (around line 72)

defp default_value("boolean"), do: %{"content" => nil}  # Changed from false
```

---

### 3.6 Missing Query Validation on Mention Suggestions

**File to modify:**
- `lib/storyarn_web/live/page_live/show.ex`

**Implementation:**

```elixir
# Replace mention_suggestions handler (lines 659-675)

def handle_event("mention_suggestions", %{"query" => query}, socket)
    when is_binary(query) and byte_size(query) <= 100 do
  project_id = socket.assigns.project.id
  results = Pages.search_referenceable(project_id, query, ["page", "flow"])

  items =
    Enum.map(results, fn item ->
      %{
        id: item.id,
        type: item.type,
        name: item.name,
        shortcut: item.shortcut,
        label: item.shortcut || item.name
      }
    end)

  {:noreply, push_event(socket, "mention_suggestions_result", %{items: items})}
end

def handle_event("mention_suggestions", _params, socket) do
  {:noreply, push_event(socket, "mention_suggestions_result", %{items: []})}
end
```

---

### 3.7 No Debouncing on Mention Suggestions

**File to modify:**
- `assets/js/hooks/tiptap_editor.js`

**Implementation:**

```javascript
// Update the items function in suggestion config (around line 18-30)

items: async ({ query }) => {
  return new Promise((resolve) => {
    // Clear previous timeout
    if (hook.mentionTimeout) {
      clearTimeout(hook.mentionTimeout);
    }
    if (hook.mentionResolve) {
      hook.mentionResolve([]);
    }

    hook.mentionResolve = resolve;

    // Debounce: wait 300ms before making request
    hook.mentionTimeout = setTimeout(() => {
      hook.pushEvent("mention_suggestions", { query });

      // Timeout after 2 seconds
      setTimeout(() => {
        if (hook.mentionResolve === resolve) {
          hook.mentionResolve = null;
          resolve([]);
        }
      }, 2000);
    }, 300);
  });
}
```

---

### 3.8 Asset Filename Not Validated

**File to modify:**
- `lib/storyarn_web/live/page_live/show.ex`

**Implementation:**

```elixir
# Add helper function in show.ex

defp sanitize_filename(filename) do
  filename
  |> String.split(~r/[\/\\]/)
  |> List.last()
  |> String.replace(~r/[^\w\-\.]/, "_")
  |> String.slice(0, 255)
end

# Update upload_avatar_file and upload_banner_file to use it:
defp upload_avatar_file(socket, filename, content_type, binary_data) do
  safe_filename = sanitize_filename(filename)
  project = socket.assigns.project
  # ... rest of function using safe_filename
end
```

---

### 3.9 Credo: diff_snapshots/2 Complexity

**File to modify:**
- `lib/storyarn/pages/versioning.ex`

**Implementation:**

```elixir
# Refactor diff_snapshots/2 (lines 298-393)
# Extract helper functions:

defp diff_snapshots(previous_snapshot, current_snapshot) do
  changes = []

  changes = check_name_changes(changes, previous_snapshot, current_snapshot)
  changes = check_shortcut_changes(changes, previous_snapshot, current_snapshot)
  changes = check_avatar_changes(changes, previous_snapshot, current_snapshot)
  changes = check_banner_changes(changes, previous_snapshot, current_snapshot)
  changes = check_block_changes(changes, previous_snapshot, current_snapshot)

  format_change_summary(changes)
end

defp check_name_changes(changes, prev, curr) do
  if prev["name"] != curr["name"] do
    ["name changed" | changes]
  else
    changes
  end
end

defp check_shortcut_changes(changes, prev, curr) do
  cond do
    is_nil(prev["shortcut"]) and not is_nil(curr["shortcut"]) ->
      ["shortcut added" | changes]
    not is_nil(prev["shortcut"]) and is_nil(curr["shortcut"]) ->
      ["shortcut removed" | changes]
    prev["shortcut"] != curr["shortcut"] ->
      ["shortcut changed" | changes]
    true ->
      changes
  end
end

# Similar functions for avatar, banner, blocks...

defp format_change_summary([]), do: gettext("No changes")
defp format_change_summary(changes), do: Enum.join(Enum.reverse(changes), ", ")
```

---

### 3.10 JS Shortcut Sanitization Removes Spaces

**File to modify:**
- `assets/js/hooks/editable_shortcut.js`

**Implementation:**

```javascript
// Update sanitize function (lines 74-81)

sanitize(text) {
  return text
    .toLowerCase()
    .replace(/[\s_]+/g, "-")           // Convert spaces/underscores to hyphens
    .replace(/[^a-z0-9.\-]/g, "")      // Remove invalid characters
    .replace(/-+/g, "-")               // Collapse multiple hyphens
    .replace(/^[.\-]+/, "")            // Remove leading dots/hyphens
    .replace(/[.\-]+$/, "");           // Remove trailing dots/hyphens
}
```

---

### 3.11 Regex for Mention Extraction is Fragile

**File to modify:**
- `lib/storyarn/pages/reference_tracker.ex`

**Implementation:**

```elixir
# Replace extract_rich_text_refs/1 (lines 164-175)
# Use Floki for robust HTML parsing

defp extract_rich_text_refs(block) do
  content = get_in(block.value, ["content"]) || ""

  case Floki.parse_fragment(content) do
    {:ok, document} ->
      document
      |> Floki.find("span.mention")
      |> Enum.map(fn element ->
        attrs = Floki.attribute(element, "data-type") |> List.first()
        id = Floki.attribute(element, "data-id") |> List.first()

        if attrs && id do
          %{type: attrs, id: id, context: "content"}
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:error, _} ->
      []
  end
end
```

**Note:** Add `{:floki, "~> 0.35"}` to `mix.exs` dependencies if not present.

---

## 4. Low Priority Fixes (P3)

### 4.1 Missing Documentation for Edge Cases

**File to modify:**
- `lib/storyarn/pages/reference_tracker.ex`

**Implementation:**

```elixir
# Update @moduledoc (lines 2-10)

@moduledoc """
Tracks entity references between pages, flows, and blocks.

## Reference Lifecycle

- References are created when blocks are saved (reference blocks, rich_text with mentions)
- References are updated atomically when block content changes
- References are deleted when source blocks are deleted

## Edge Cases

- **Deleted sources**: References from soft-deleted blocks/pages are excluded from backlinks
- **Deleted targets**: References to deleted targets show "not found" in UI
- **Orphaned references**: Use `cleanup_orphaned_references/0` to remove stale data
- **Cross-project**: References are always scoped to a single project

## Performance

- Backlinks query is optimized with JOINs (no N+1)
- Indexes exist on (source_type, source_id) and (target_type, target_id)
"""
```

---

### 4.2 Type Mismatch: Schema vs Migration

**File to modify:**
- `lib/storyarn/pages/entity_reference.ex`

**Implementation:**

```elixir
# Update schema (lines 29-37)
# Change :integer to :id for consistency

schema "entity_references" do
  field :source_type, :string
  field :source_id, :id  # Changed from :integer
  field :target_type, :string
  field :target_id, :id  # Changed from :integer
  field :context, :string

  timestamps()
end
```

---

### 4.3 Missing Rate Limiting on Expensive Queries

**File to modify:**
- `lib/storyarn_web/live/page_live/show.ex`

**Implementation:**

```elixir
# Add rate limiting on tab switch (update switch_tab handler)

def handle_event("switch_tab", %{"tab" => tab}, socket) do
  socket = assign(socket, :active_tab, tab)

  socket =
    if tab == "references" and not socket.assigns[:references_loaded] do
      # Only load once per session
      versions = Pages.list_versions(socket.assigns.page.id, limit: 20)
      backlinks = Pages.get_backlinks_with_sources(
        "page",
        socket.assigns.page.id,
        socket.assigns.project.id
      )

      socket
      |> assign(:versions, versions)
      |> assign(:backlinks, backlinks)
      |> assign(:references_loaded, true)
    else
      socket
    end

  {:noreply, socket}
end
```

---

### 4.4 Pages/Flows Can Share Shortcut Names

**Recommendation:** Document this as intended behavior or add cross-table uniqueness.

**Option A - Document (recommended):**

Add to `PHASE_7_5_PAGES_ENHANCEMENT.md`:
```markdown
### Shortcut Namespacing

Pages and flows have separate shortcut namespaces. This means:
- A page can have shortcut `mc.jaime`
- A flow can also have shortcut `mc.jaime` in the same project

References use `target_type` to disambiguate. In mentions, prefix with type:
- `#page:mc.jaime` for pages
- `#flow:mc.jaime` for flows
```

**Option B - Enforce uniqueness (if desired):**

Create migration with cross-table constraint (complex, not recommended).

---

### 4.5 No Validation for Consecutive Dots in Shortcuts

**File to modify:**
- `lib/storyarn/shortcuts.ex`

**Implementation:**

```elixir
# Update slugify/1 (around line 75)

def slugify(text) when is_binary(text) do
  text
  |> String.downcase()
  |> String.replace(~r/[\s_]+/, "-")
  |> String.replace(~r/[^a-z0-9.\-]/, "")
  |> String.replace(~r/-+/, "-")
  |> String.replace(~r/\.+/, ".")  # ADD: Collapse consecutive dots
  |> String.trim("-")
  |> String.trim(".")
end
```

---

### 4.6 No Pagination in Version History UI

**Files to modify:**
- `lib/storyarn_web/live/page_live/show.ex`
- Template section for version history

**Implementation:**

```elixir
# Add pagination state to mount
socket = assign(socket, :versions_page, 1)

# Update load_versions helper
defp load_versions(socket, page \\ 1) do
  per_page = 20
  offset = (page - 1) * per_page

  versions = Pages.list_versions(
    socket.assigns.page.id,
    limit: per_page + 1,  # Fetch one extra to check if more exist
    offset: offset
  )

  has_more = length(versions) > per_page
  versions = Enum.take(versions, per_page)

  socket
  |> assign(:versions, versions)
  |> assign(:versions_page, page)
  |> assign(:has_more_versions, has_more)
end

# Add event handler
def handle_event("load_more_versions", _params, socket) do
  next_page = socket.assigns.versions_page + 1
  {:noreply, load_versions(socket, next_page)}
end
```

Add to template:
```heex
<button
  :if={@has_more_versions}
  phx-click="load_more_versions"
  class="btn btn-ghost btn-sm w-full mt-2"
>
  {gettext("Load more")}
</button>
```

---

## 5. Test Coverage Tasks

### 5.1 Create Versioning Tests

**File to create:**
- `test/storyarn/pages/versioning_test.exs`

```elixir
defmodule Storyarn.Pages.VersioningTest do
  use Storyarn.DataCase

  alias Storyarn.Pages
  alias Storyarn.Pages.PageVersion

  describe "create_version/3" do
    test "creates version with correct snapshot"
    test "increments version number"
    test "generates change summary"
    test "respects rate limiting (5 min minimum)"
    test "includes all block data in snapshot"
  end

  describe "list_versions/2" do
    test "returns versions ordered by version_number desc"
    test "respects limit option"
    test "preloads changed_by user"
  end

  describe "get_version/2" do
    test "returns version by page_id and version_number"
    test "returns nil for non-existent version"
  end

  describe "restore_version/2" do
    test "restores page metadata from snapshot"
    test "deletes current blocks"
    test "recreates blocks from snapshot"
    test "sets current_version_id"
    test "handles empty blocks snapshot"
  end

  describe "delete_version/1" do
    test "deletes version"
    test "clears current_version_id if deleted version was current"
  end

  describe "maybe_create_version/2" do
    test "creates version when rate limit allows"
    test "skips creation within 5 minutes of last version"
    test "creates version for manual creation regardless of rate limit"
  end
end
```

---

### 5.2 Create Soft Delete Tests

**Add to:**
- `test/storyarn/pages_test.exs`

```elixir
describe "soft delete" do
  describe "trash_page/1" do
    test "sets deleted_at on page"
    test "sets deleted_at on all descendant pages"
    test "does not affect non-descendant pages"
  end

  describe "list_trashed_pages/1" do
    test "returns only deleted pages"
    test "scopes to project"
    test "orders by deleted_at desc"
  end

  describe "get_trashed_page/2" do
    test "returns deleted page by id"
    test "returns nil for non-deleted page"
  end

  describe "restore_page/1" do
    test "clears deleted_at"
    test "restores soft-deleted blocks"
  end

  describe "permanently_delete_page/1" do
    test "removes page from database"
    test "removes all versions"
    test "removes target references"
  end

  describe "query filtering" do
    test "list_pages_tree excludes deleted pages"
    test "get_page returns nil for deleted pages"
    test "search_pages excludes deleted pages"
  end
end

describe "block soft delete" do
  test "delete_block sets deleted_at"
  test "list_blocks excludes deleted blocks"
  test "get_block returns nil for deleted blocks"
  test "restore_block clears deleted_at"
end
```

---

### 5.3 Create Shortcut Tests

**Add to:**
- `test/storyarn/pages_test.exs`

```elixir
describe "shortcut auto-generation" do
  test "generates shortcut from page name on create"
  test "generates unique shortcut when collision exists"
  test "preserves explicit shortcut when provided"
  test "regenerates shortcut when name changes and no explicit shortcut"
  test "does not regenerate when explicit shortcut provided"
  test "handles empty name gracefully"
  test "slugifies name correctly (spaces, special chars)"
end

describe "shortcut validation" do
  test "accepts lowercase alphanumeric"
  test "accepts dots and hyphens"
  test "rejects uppercase"
  test "rejects spaces"
  test "rejects special characters"
  test "rejects leading/trailing dots or hyphens"
  test "enforces uniqueness within project"
  test "allows same shortcut in different projects"
  test "allows reuse after soft delete"
end
```

---

## 6. Code Quality Refactoring

### 6.1 Split page_live/show.ex (1275 lines)

**Target:** Reduce to ~400 lines

**Files to create:**
- `lib/storyarn_web/live/page_live/helpers/versioning_helpers.ex`
- `lib/storyarn_web/live/page_live/helpers/asset_helpers.ex`
- `lib/storyarn_web/live/page_live/helpers/reference_helpers.ex`

**Move these handlers:**

To `versioning_helpers.ex`:
- `create_version`
- `restore_version`
- `delete_version`
- `set_current_version`
- `load_versions` (private)

To `asset_helpers.ex`:
- `set_avatar`
- `remove_avatar`
- `upload_banner`
- `remove_banner`
- `upload_avatar_file` (private)
- `upload_banner_file` (private)

To `reference_helpers.ex`:
- `search_references`
- `select_reference`
- `clear_reference`
- `mention_suggestions`
- `load_blocks_with_references` (private)

**Pattern to follow:**
```elixir
# In new helper module
defmodule StoryarnWeb.PageLive.Helpers.VersioningHelpers do
  import Phoenix.LiveView
  import StoryarnWeb.Gettext

  alias Storyarn.Pages

  def create_version(socket) do
    # Implementation
  end

  # ...
end

# In show.ex
import StoryarnWeb.PageLive.Helpers.VersioningHelpers

def handle_event("create_version", params, socket) do
  with_authorization(socket, :edit_content, fn socket ->
    VersioningHelpers.create_version(socket)
  end)
end
```

---

### 6.2 Split core_components.ex (682 lines)

**Target:** Split into focused modules

**Files to create:**
- `lib/storyarn_web/components/form_components.ex` (~200 lines)
- `lib/storyarn_web/components/table_components.ex` (~100 lines)
- `lib/storyarn_web/components/modal_components.ex` (~150 lines)

**Move these components:**

To `form_components.ex`:
- `input/1` (all variants)
- `label/1`
- `error/1`
- `field_group/1`

To `table_components.ex`:
- `table/1`
- `header/1`
- `list/1`

To `modal_components.ex`:
- `modal/1`
- `confirm_modal/1`
- `show_modal/1`
- `hide_modal/1`

**Update imports:**
```elixir
# In lib/storyarn_web.ex, update html_helpers
defp html_helpers do
  quote do
    import StoryarnWeb.CoreComponents
    import StoryarnWeb.FormComponents    # ADD
    import StoryarnWeb.TableComponents   # ADD
    import StoryarnWeb.ModalComponents   # ADD
    # ...
  end
end
```

---

## Execution Checklist

Use this checklist to track progress:

### Critical (P0) ✅ COMPLETE
- [x] 1.1 IDOR in block operations
- [x] 1.2 IDOR in reference blocks
- [x] 1.3 XSS in Tiptap mentions
- [x] 1.4 FK constraints on entity_references

### High Priority (P1) ✅ COMPLETE
- [x] 2.1 Config panel authorization
- [x] 2.2 Flow node reference tracking
- [x] 2.3 TreeOperations deleted_at filter
- [x] 2.4 Block soft-delete
- [x] 2.5 N+1 query optimization

### Medium Priority (P2)
- [ ] 3.1 Restore page with blocks
- [x] 3.2 Soft-deleted sources in backlinks (covered by 2.5)
- [ ] 3.3 Thread safety in reference updates
- [ ] 3.4 Version snapshot block IDs
- [ ] 3.5 Boolean block default value
- [ ] 3.6 Mention query validation
- [ ] 3.7 Mention debouncing
- [ ] 3.8 Asset filename validation
- [ ] 3.9 Credo complexity refactor
- [ ] 3.10 JS shortcut sanitization
- [ ] 3.11 Mention extraction with Floki

### Low Priority (P3)
- [ ] 4.1 Documentation for edge cases
- [ ] 4.2 Type mismatch fix
- [ ] 4.3 Rate limiting on expensive queries
- [ ] 4.4 Document shortcut namespacing
- [ ] 4.5 Consecutive dots validation
- [ ] 4.6 Version history pagination

### Tests
- [ ] 5.1 Versioning tests
- [ ] 5.2 Soft delete tests
- [ ] 5.3 Shortcut tests

### Refactoring
- [ ] 6.1 Split page_live/show.ex
- [ ] 6.2 Split core_components.ex

---

## Notes for Implementation

1. **Run tests after each fix:** `mix test test/storyarn/pages_test.exs`
2. **Check Credo after refactoring:** `mix credo --strict`
3. **Run full test suite before PR:** `mix test`
4. **Format code:** `mix format`
5. **Add Floki dependency if using 3.11:** `{:floki, "~> 0.35"}`

---

*Last updated: February 3, 2026*
