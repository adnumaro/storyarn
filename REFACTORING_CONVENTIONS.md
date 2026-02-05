# Refactoring Conventions

## File Size Limits

| Type                     | Max Lines   |
|--------------------------|-------------|
| LiveView module          | 300         |
| Function component       | 200         |
| Helper module            | 200         |
| Context facade           | 100         |
| Context submodule        | 250         |
| JS Hook (orchestrator)   | 100         |
| JS Handler               | 150         |
| JS LitElement (excl CSS) | 200         |

## Handler Delegation Pattern

LiveView modules (show.ex) should delegate events to handler modules:

```elixir
# show.ex - thin delegation
def handle_event("add_node", params, socket) do
  case authorize(socket, :edit_content) do
    :ok -> NodeEventHandlers.handle_add_node(params, socket)
    {:error, :unauthorized} -> {:noreply, unauthorized_flash(socket)}
  end
end
```

Handler modules receive `(params, socket)` and return `{:noreply, socket}`:

```elixir
# handlers/node_event_handlers.ex
defmodule StoryarnWeb.FlowLive.Handlers.NodeEventHandlers do
  def handle_add_node(%{"type" => type}, socket) do
    NodeHelpers.add_node(socket, type)
  end
end
```

## Function Component Extraction Pattern

When splitting a large component file:

1. Create new module under `components/` subdirectory
2. New module uses `Phoenix.Component` and imports shared dependencies
3. Original module dispatches based on type:

```elixir
# Original (becomes dispatcher)
case @node.type do
  "dialogue" -> ~H"<DialoguePanel.dialogue_properties {...} />"
  "condition" -> ~H"<ConditionPanel.condition_properties {...} />"
  _ -> ~H"<SimplePanels.simple_properties {...} />"
end
```

## JS Handler Factory Pattern

JS modules export factory functions that receive the hook instance:

```javascript
// handlers/my_handler.js
export function createMyHandler(hook) {
  return {
    init() { /* setup */ },
    destroy() { /* cleanup */ },
    handleSomeEvent(data) { /* ... */ }
  };
}
```

## Naming Conventions

### Elixir
- Handler modules: `StoryarnWeb.FlowLive.Handlers.{Domain}EventHandlers`
- Panel components: `StoryarnWeb.FlowLive.Components.Panels.{Type}Panel`
- Sidebar trees: `StoryarnWeb.Components.Sidebar.{Type}Tree`
- Helper extractions: `StoryarnWeb.{Context}.Helpers.{Domain}Helpers`

### JavaScript
- Style modules: `components/{name}_styles.js`
- Formatter modules: `components/{name}_formatters.js`
- Handler modules: `handlers/{name}_handler.js`
- Extension modules: `{lib}/{name}_extension.js`

## When to Create a New File vs Extend Existing

**Create new file when:**
- A module exceeds its file size limit
- Functions serve a distinct domain concern (e.g., responses vs node CRUD)
- A group of functions are always used together but not with the rest

**Extend existing file when:**
- Adding 1-3 related functions to a module within size limits
- The new function is tightly coupled to existing ones (shared private helpers)
- Creating a new file would result in <30 lines

## Rules for Structural Moves

1. **Never change function signatures** during extraction
2. **Never change module boundaries** of callers (imports stay the same where possible)
3. **Run `mix compile --warnings-as-errors`** after every extraction
4. **Run `mix test`** after every extraction
5. **One extraction per commit** for easy rollback
6. **Preserve all `@doc` and `@spec`** annotations during moves
