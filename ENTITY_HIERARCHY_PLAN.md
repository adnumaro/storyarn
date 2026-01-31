# Plan: Entity Hierarchy (Phase 2)

## Summary

Add hierarchical support to entities, allowing entities to have parent-child relationships within the same template. This enables use cases like character variants, location sub-areas, and item components.

**Scope:** Database schema, context functions, sidebar tree display, and entity form updates.

---

## Architecture

### Data Model Changes

```
Entity
├── parent_id (FK to entities, nullable)
├── position (integer, for ordering siblings)
│
├── belongs_to :parent (Entity)
├── has_many :children (Entity)
```

### Tree Structure Example

```
Characters (template)
├── John Doe
│   ├── John (Young)
│   └── John (Old)
├── Sarah Smith
└── The Mentor

Locations (template)
├── Castle
│   ├── Throne Room
│   ├── Dungeon
│   │   └── Secret Passage
│   └── Garden
└── Village
```

---

## Implementation Tasks

### 1. Database Migration

Create migration to add `parent_id` and `position` fields to entities table.

```elixir
# Add parent_id for hierarchy
add :parent_id, references(:entities, on_delete: :nilify_all)

# Add position for ordering siblings
add :position, :integer, default: 0

# Index for efficient tree queries
create index(:entities, [:parent_id])
create index(:entities, [:template_id, :parent_id, :position])
```

### 2. Update Entity Schema

- Add `parent_id` and `position` fields
- Add `belongs_to :parent` and `has_many :children` associations
- Add validation that parent must be same template
- Update changesets

### 3. Update EntityCrud Module

Add new functions:
- `list_entities_tree/2` - Returns hierarchical structure
- `get_entity_with_children/2` - Entity with nested children
- `move_entity/3` - Change parent/position
- `reorder_siblings/2` - Reorder entities at same level

### 4. Update Entities Facade

Add delegations for new functions.

### 5. Update Templates Module

Modify `list_templates_with_entities/1` to return hierarchical entity tree.

### 6. Update Project Sidebar

- Render nested entities under parent entities
- Support multi-level expansion
- Update TreeToggle hook for nested nodes

### 7. Update Entity Form

- Add parent selector (dropdown of entities from same template)
- Show "Create child" option when viewing an entity

### 8. Update Entity LiveViews

- EntityLive.Index: Support filtering by parent
- EntityLive.Show: Show children list, "Add child" button

---

## Detailed Implementation

### Task 1: Database Migration

**File:** `priv/repo/migrations/TIMESTAMP_add_entity_hierarchy.exs`

```elixir
defmodule Storyarn.Repo.Migrations.AddEntityHierarchy do
  use Ecto.Migration

  def change do
    alter table(:entities) do
      add :parent_id, references(:entities, on_delete: :nilify_all)
      add :position, :integer, default: 0
    end

    create index(:entities, [:parent_id])
    create index(:entities, [:template_id, :parent_id, :position])
  end
end
```

### Task 2: Entity Schema Updates

**File:** `lib/storyarn/entities/entity.ex`

Add:
```elixir
field :position, :integer, default: 0

belongs_to :parent, Entity
has_many :children, Entity, foreign_key: :parent_id
```

Update changesets to:
- Cast `parent_id` and `position`
- Validate parent is from same template
- Prevent circular references

### Task 3: EntityCrud Functions

**File:** `lib/storyarn/entities/entity_crud.ex`

```elixir
@doc """
Lists entities as a hierarchical tree for a project.
Returns only root entities (parent_id is nil) with children preloaded recursively.
"""
def list_entities_tree(project_id, opts \\ [])

@doc """
Gets an entity with all descendants loaded.
"""
def get_entity_with_descendants(project_id, entity_id)

@doc """
Moves an entity to a new parent (or to root if parent_id is nil).
"""
def move_entity(entity, parent_id, position \\ nil)

@doc """
Validates that setting parent_id would not create a cycle.
"""
def valid_parent?(entity_id, parent_id)
```

### Task 4: Templates Module Update

**File:** `lib/storyarn/entities/templates.ex`

Update `list_templates_with_entities/1` to build tree structure:
- Query entities with preloaded children
- Build recursive tree per template

### Task 5: Sidebar Tree Update

**File:** `lib/storyarn_web/components/project_sidebar.ex`

- Render entities recursively
- Pass depth level for indentation
- Support expansion of entity nodes with children

### Task 6: Entity Form Update

**File:** `lib/storyarn_web/live/entity_live/form.ex`

- Add optional parent_id select field
- Filter parent options to same template
- Exclude self and descendants from parent options

### Task 7: Entity Show Updates

**File:** `lib/storyarn_web/live/entity_live/show.ex`

- Display parent link if entity has parent
- List children with links
- "Add Child" button

---

## Constraints & Validations

1. **Same Template:** Parent must be from the same template
2. **No Cycles:** Cannot set parent to self or any descendant
3. **Depth Limit:** Optional max depth (e.g., 5 levels) to prevent deeply nested trees
4. **Position:** Auto-assign position when creating, allow reordering

---

## Testing Strategy

1. **Unit Tests:**
   - Entity schema validations (parent same template, no cycles)
   - Tree query functions
   - Move/reorder operations

2. **Integration Tests:**
   - Create entity with parent
   - Move entity to different parent
   - Delete parent (children become roots)
   - Sidebar displays tree correctly

---

## Order of Implementation

1. [ ] Database migration
2. [ ] Entity schema updates
3. [ ] EntityCrud tree functions
4. [ ] Entities facade updates
5. [ ] Templates module update (tree structure)
6. [ ] Sidebar tree recursive rendering
7. [ ] Entity form parent selector
8. [ ] Entity show children display
9. [ ] Tests

---

## Future Enhancements (Phase 3)

- Drag & drop reordering in sidebar
- Bulk move operations
- Schema inheritance (child inherits parent's data)
- Context menu (right-click)
- Search within tree
