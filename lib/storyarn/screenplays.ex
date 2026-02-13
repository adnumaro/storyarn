defmodule Storyarn.Screenplays do
  @moduledoc """
  The Screenplays context.

  Manages screenplays (block-based screenplay editor) and their elements
  within a project. Screenplays can optionally link to flows for bidirectional sync.

  This module serves as a facade, delegating to specialized submodules:
  - `ScreenplayCrud` — CRUD operations for screenplays
  - `ElementCrud` — CRUD operations for screenplay elements
  - `ScreenplayQueries` — Read-only queries (get_with_elements, count, drafts)
  - `TreeOperations` — Reordering and moving screenplays in the tree
  - `ElementGrouping` — Dialogue group computation from adjacency
  """

  alias Storyarn.Screenplays.{
    AutoDetect,
    ElementCrud,
    ElementGrouping,
    FlowSync,
    LinkedPageCrud,
    ScreenplayCrud,
    ScreenplayQueries,
    TreeOperations
  }

  # =============================================================================
  # Screenplays — CRUD Operations
  # =============================================================================

  @doc "Lists all non-deleted, non-draft screenplays for a project."
  defdelegate list_screenplays(project_id), to: ScreenplayCrud

  @doc "Lists screenplays as a tree structure (root with children preloaded)."
  defdelegate list_screenplays_tree(project_id), to: ScreenplayCrud

  @doc "Gets a screenplay by project_id and screenplay_id. Returns nil if not found."
  defdelegate get_screenplay(project_id, screenplay_id), to: ScreenplayCrud

  @doc "Gets a screenplay by project_id and screenplay_id. Raises if not found."
  defdelegate get_screenplay!(project_id, screenplay_id), to: ScreenplayCrud

  @doc "Creates a screenplay for a project. Auto-generates shortcut and position."
  defdelegate create_screenplay(project, attrs), to: ScreenplayCrud

  @doc "Updates a screenplay. Auto-generates shortcut if name changes."
  defdelegate update_screenplay(screenplay, attrs), to: ScreenplayCrud

  @doc "Soft-deletes a screenplay and all children recursively."
  defdelegate delete_screenplay(screenplay), to: ScreenplayCrud

  @doc "Restores a soft-deleted screenplay."
  defdelegate restore_screenplay(screenplay), to: ScreenplayCrud

  @doc "Returns a changeset for tracking screenplay changes."
  defdelegate change_screenplay(screenplay, attrs \\ %{}), to: ScreenplayCrud

  @doc "Checks if a screenplay exists within a project (non-deleted, non-draft)."
  defdelegate screenplay_exists?(project_id, screenplay_id), to: ScreenplayCrud

  @doc "Lists all soft-deleted screenplays for a project (trash)."
  defdelegate list_deleted_screenplays(project_id), to: ScreenplayCrud

  # =============================================================================
  # Screenplays — Queries
  # =============================================================================

  @doc "Gets a screenplay with all elements preloaded (ordered by position)."
  defdelegate get_with_elements(screenplay_id), to: ScreenplayQueries

  @doc "Returns the number of elements in a screenplay."
  defdelegate count_elements(screenplay_id), to: ScreenplayQueries

  @doc "Lists all drafts of a given screenplay."
  defdelegate list_drafts(screenplay_id), to: ScreenplayQueries

  # =============================================================================
  # Tree Operations
  # =============================================================================

  @doc "Reorders screenplays within a parent container."
  defdelegate reorder_screenplays(project_id, parent_id, screenplay_ids), to: TreeOperations

  @doc "Moves a screenplay to a new parent at a specific position."
  defdelegate move_screenplay_to_position(screenplay, parent_id, position), to: TreeOperations

  # =============================================================================
  # Elements — CRUD Operations
  # =============================================================================

  @doc "Lists all elements for a screenplay, ordered by position."
  defdelegate list_elements(screenplay_id), to: ElementCrud

  @doc "Creates an element appended at the end of the screenplay."
  defdelegate create_element(screenplay, attrs), to: ElementCrud

  @doc "Inserts an element at a specific position, shifting subsequent elements."
  defdelegate insert_element_at(screenplay, position, attrs), to: ElementCrud

  @doc "Updates an element's content, data, type, depth, or branch."
  defdelegate update_element(element, attrs), to: ElementCrud

  @doc "Deletes an element and compacts positions of subsequent elements."
  defdelegate delete_element(element), to: ElementCrud

  @doc "Reorders elements by a list of element IDs."
  defdelegate reorder_elements(screenplay_id, element_ids), to: ElementCrud

  @doc "Splits an element at a cursor position, inserting a new element of the given type."
  defdelegate split_element(element, cursor_position, new_type), to: ElementCrud

  # =============================================================================
  # Element Grouping (computed, not stored — Edge Case F)
  # =============================================================================

  @doc "Computes dialogue groups from element adjacency."
  defdelegate compute_dialogue_groups(elements), to: ElementGrouping

  @doc "Groups consecutive elements into logical units for flow mapping."
  defdelegate group_elements(elements), to: ElementGrouping

  # =============================================================================
  # Flow Sync
  # =============================================================================

  @doc "Returns the linked flow, creating one if the screenplay is unlinked."
  defdelegate ensure_flow(screenplay), to: FlowSync

  @doc "Links a screenplay to an existing flow."
  defdelegate link_to_flow(screenplay, flow_id), to: FlowSync

  @doc "Unlinks a screenplay from its flow. Clears all element links."
  defdelegate unlink_flow(screenplay), to: FlowSync

  @doc "Syncs screenplay elements to the linked flow."
  defdelegate sync_to_flow(screenplay), to: FlowSync

  @doc "Syncs flow nodes into the screenplay (reverse direction)."
  defdelegate sync_from_flow(screenplay), to: FlowSync

  # =============================================================================
  # Linked Pages (Response Branching)
  # =============================================================================

  @doc "Creates a child screenplay linked to a response choice."
  defdelegate create_linked_page(parent, element, choice_id), to: LinkedPageCrud

  @doc "Links a response choice to an existing child screenplay."
  defdelegate link_choice(element, choice_id, child_id, parent_id), to: LinkedPageCrud

  @doc "Unlinks a response choice from its linked screenplay."
  defdelegate unlink_choice(element, choice_id), to: LinkedPageCrud

  @doc "Returns linked screenplay IDs for all choices in a response element."
  defdelegate linked_screenplay_ids(element), to: LinkedPageCrud

  @doc "Lists child screenplays for a parent. Returns [%{id, name}]."
  defdelegate list_child_screenplays(parent_id), to: LinkedPageCrud

  @doc "Finds a choice by ID in a response element's data."
  defdelegate find_choice(element, choice_id), to: LinkedPageCrud

  @doc "Updates a choice in a response element by applying update_fn to the matching choice."
  defdelegate update_choice(element, choice_id, update_fn), to: LinkedPageCrud

  # =============================================================================
  # Auto-Detection
  # =============================================================================

  @doc "Detects element type from content text patterns. Returns type string or nil."
  defdelegate detect_type(content), to: AutoDetect

  # =============================================================================
  # Export / Import
  # =============================================================================

  alias Storyarn.Screenplays.Export.Fountain, as: FountainExport
  alias Storyarn.Screenplays.Import.Fountain, as: FountainImport

  @doc "Exports elements to Fountain format string."
  defdelegate export_fountain(elements), to: FountainExport, as: :export

  @doc "Parses a Fountain format string into element attribute maps."
  defdelegate parse_fountain(text), to: FountainImport, as: :parse
end
