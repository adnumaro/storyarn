defmodule StoryarnWeb.SheetLive.Handlers.InheritanceHandlersTest do
  use Storyarn.DataCase, async: true

  alias StoryarnWeb.SheetLive.Handlers.InheritanceHandlers

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Sheets

  # =============================================================================
  # handle_detach/3
  # =============================================================================

  describe "handle_detach/3" do
    setup :setup_inheritance_context

    test "detaches an inherited block successfully", %{
      socket: socket,
      helpers: helpers,
      child_block: child_block
    } do
      {:noreply, result} =
        InheritanceHandlers.handle_detach(to_string(child_block.id), socket, helpers)

      assert result.assigns.flash["info"] =~ "detach"
    end

    test "returns error for non-existent block", %{socket: socket, helpers: helpers} do
      {:noreply, result} = InheritanceHandlers.handle_detach("999999", socket, helpers)
      assert result.assigns.flash["error"] =~ "not found"
    end
  end

  # =============================================================================
  # handle_reattach/3
  # =============================================================================

  describe "handle_reattach/3" do
    setup :setup_inheritance_context

    test "reattaches a detached inherited block", %{
      socket: socket,
      child_block: child_block,
      child_sheet: child_sheet
    } do
      # First detach it
      Sheets.detach_block(child_block)
      helpers_for_child = build_helpers(socket.assigns.project, child_sheet)

      socket = %{
        socket
        | assigns:
            socket.assigns
            |> Map.put(:sheet, child_sheet)
            |> Map.put(:blocks, Sheets.list_blocks(child_sheet.id))
      }

      {:noreply, result} =
        InheritanceHandlers.handle_reattach(to_string(child_block.id), socket, helpers_for_child)

      assert result.assigns.flash["info"] =~ "re-synced"
    end

    test "returns error for non-existent block", %{socket: socket, helpers: helpers} do
      {:noreply, result} = InheritanceHandlers.handle_reattach("999999", socket, helpers)
      assert result.assigns.flash["error"] =~ "not found"
    end
  end

  # =============================================================================
  # handle_hide_for_children/3
  # =============================================================================

  describe "handle_hide_for_children/3" do
    setup :setup_inheritance_context

    test "hides block from children", %{socket: socket, helpers: helpers, parent_block: block} do
      {:noreply, result} =
        InheritanceHandlers.handle_hide_for_children(to_string(block.id), socket, helpers)

      updated_sheet = result.assigns.sheet
      assert block.id in (updated_sheet.hidden_inherited_block_ids || [])
    end
  end

  # =============================================================================
  # handle_unhide_for_children/3
  # =============================================================================

  describe "handle_unhide_for_children/3" do
    setup :setup_inheritance_context

    test "unhides block for children", %{
      socket: socket,
      helpers: helpers,
      parent_block: block,
      parent_sheet: parent_sheet
    } do
      # First hide it
      {:ok, updated_sheet} = Sheets.hide_for_children(parent_sheet, block.id)
      socket = %{socket | assigns: %{socket.assigns | sheet: updated_sheet}}

      {:noreply, result} =
        InheritanceHandlers.handle_unhide_for_children(to_string(block.id), socket, helpers)

      assert result.assigns.flash["info"] =~ "visible"
    end
  end

  # =============================================================================
  # handle_navigate_to_source/3
  # =============================================================================

  describe "handle_navigate_to_source/3" do
    setup :setup_inheritance_context

    test "navigates to source sheet for inherited block", %{
      socket: socket,
      helpers: helpers,
      child_block: child_block,
      child_sheet: child_sheet
    } do
      socket = %{
        socket
        | assigns: %{
            socket.assigns
            | sheet: child_sheet,
              blocks: Sheets.list_blocks(child_sheet.id)
          }
      }

      {:noreply, result} =
        InheritanceHandlers.handle_navigate_to_source(to_string(child_block.id), socket, helpers)

      # Should push_navigate (which sets __changed__ on the socket)
      assert result.redirected
    end

    test "returns error for non-existent block", %{socket: socket, helpers: helpers} do
      {:noreply, result} =
        InheritanceHandlers.handle_navigate_to_source("999999", socket, helpers)

      assert result.assigns.flash["error"] =~ "not found"
    end

    test "returns error when source sheet not found", %{
      socket: socket,
      helpers: helpers,
      parent_block: parent_block
    } do
      # parent_block has no inherited_from_block_id, so get_source_sheet returns nil
      {:noreply, result} =
        InheritanceHandlers.handle_navigate_to_source(to_string(parent_block.id), socket, helpers)

      assert result.assigns.flash["error"] =~ "Source sheet not found"
    end
  end

  # =============================================================================
  # handle_change_scope/3
  # =============================================================================

  describe "handle_change_scope/4" do
    setup :setup_scope_context

    test "does nothing when scope is same", %{socket: socket, helpers: helpers, block: block} do
      {:noreply, result} = InheritanceHandlers.handle_change_scope(block, "self", socket, helpers)
      assert result == socket
    end

    test "changes scope from self to children", %{
      socket: socket,
      helpers: helpers,
      block: block
    } do
      {:noreply, result} =
        InheritanceHandlers.handle_change_scope(block, "children", socket, helpers)

      # Verify the block was updated in the DB
      updated_block = Sheets.get_block!(block.id)
      assert updated_block.scope == "children"
    end
  end

  # =============================================================================
  # handle_toggle_required/2
  # =============================================================================

  describe "handle_toggle_required/3" do
    setup :setup_scope_context

    test "toggles required from false to true", %{socket: socket, helpers: helpers, block: block} do
      {:noreply, _result} = InheritanceHandlers.handle_toggle_required(block, socket, helpers)

      updated_block = Sheets.get_block!(block.id)
      assert updated_block.required == true
    end

    test "toggles required from true to false", %{socket: socket, helpers: helpers, block: block} do
      {:ok, block} = Sheets.update_block(block, %{required: true})

      {:noreply, _result} = InheritanceHandlers.handle_toggle_required(block, socket, helpers)

      updated_block = Sheets.get_block!(block.id)
      assert updated_block.required == false
    end
  end

  # =============================================================================
  # handle_open_propagation_modal/3
  # =============================================================================

  describe "handle_open_propagation_modal/3" do
    setup :setup_scope_context

    test "assigns propagation_block", %{socket: socket, helpers: helpers, block: block} do
      {:noreply, result} =
        InheritanceHandlers.handle_open_propagation_modal(to_string(block.id), socket, helpers)

      assert result.assigns.propagation_block != nil
      assert result.assigns.propagation_block.id == block.id
    end

    test "returns error for non-existent block", %{socket: socket, helpers: helpers} do
      {:noreply, result} =
        InheritanceHandlers.handle_open_propagation_modal("999999", socket, helpers)

      assert result.assigns.flash["error"] =~ "not found"
    end
  end

  # =============================================================================
  # handle_cancel_propagation/1
  # =============================================================================

  describe "handle_cancel_propagation/1" do
    setup :setup_scope_context

    test "clears propagation_block", %{socket: socket, block: block} do
      socket = %{socket | assigns: %{socket.assigns | propagation_block: block}}
      {:noreply, result} = InheritanceHandlers.handle_cancel_propagation(socket)
      assert result.assigns.propagation_block == nil
    end
  end

  # =============================================================================
  # handle_propagate_property/3
  # =============================================================================

  describe "handle_propagate_property/3" do
    setup :setup_inheritance_context

    test "propagates property to descendant sheets", %{
      socket: socket,
      helpers: helpers,
      parent_block: parent_block,
      child_sheet: child_sheet
    } do
      # Set scope to children first
      {:ok, block} = Sheets.update_block(parent_block, %{scope: "children"})
      socket = %{socket | assigns: %{socket.assigns | propagation_block: block}}

      sheet_ids_json = Jason.encode!([child_sheet.id])

      {:noreply, result} =
        InheritanceHandlers.handle_propagate_property(sheet_ids_json, socket, helpers)

      assert result.assigns.propagation_block == nil
      assert result.assigns.flash["info"] =~ "propagated"
    end

    test "returns error for invalid JSON", %{socket: socket, helpers: helpers} do
      socket = %{socket | assigns: %{socket.assigns | propagation_block: nil}}

      {:noreply, result} =
        InheritanceHandlers.handle_propagate_property("not json", socket, helpers)

      assert result.assigns.flash["error"] =~ "Invalid"
    end

    test "returns error for non-list JSON", %{socket: socket, helpers: helpers} do
      socket = %{socket | assigns: %{socket.assigns | propagation_block: nil}}

      {:noreply, result} =
        InheritanceHandlers.handle_propagate_property("{\"key\": 1}", socket, helpers)

      assert result.assigns.flash["error"] =~ "Invalid"
    end
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp build_helpers(_project, sheet) do
    %{
      reload_blocks: fn socket ->
        blocks = Sheets.list_blocks(sheet.id)
        Phoenix.Component.assign(socket, :blocks, blocks)
      end,
      maybe_create_version: fn _socket -> :ok end,
      notify_parent: fn _socket, _action -> :ok end
    }
  end

  defp build_socket(assigns) do
    %Phoenix.LiveView.Socket{
      assigns: Map.merge(%{__changed__: %{}, flash: %{}, propagation_block: nil}, assigns),
      private: %{lifecycle_events: [], live_temp: %{}}
    }
  end

  defp setup_inheritance_context(_context) do
    user = user_fixture()
    project = project_fixture(user)
    workspace = Storyarn.Repo.preload(project, :workspace).workspace

    parent_sheet = sheet_fixture(project, %{name: "Parent"})
    child_sheet = child_sheet_fixture(project, parent_sheet, %{name: "Child"})
    parent_block = inheritable_block_fixture(parent_sheet, label: "HP", type: "number")

    # Trigger inheritance resolution so child gets inherited blocks
    Sheets.resolve_inherited_blocks(child_sheet.id)
    child_blocks = Sheets.list_blocks(child_sheet.id)
    child_block = Enum.find(child_blocks, &(&1.inherited_from_block_id != nil))

    helpers = build_helpers(project, child_sheet)

    socket =
      build_socket(%{
        project: project,
        workspace: workspace,
        sheet: parent_sheet,
        blocks: Sheets.list_blocks(parent_sheet.id)
      })

    %{
      project: project,
      parent_sheet: parent_sheet,
      child_sheet: child_sheet,
      parent_block: parent_block,
      child_block: child_block,
      socket: socket,
      helpers: helpers
    }
  end

  defp setup_scope_context(_context) do
    user = user_fixture()
    project = project_fixture(user)
    workspace = Storyarn.Repo.preload(project, :workspace).workspace

    sheet = sheet_fixture(project, %{name: "Test Sheet"})
    block = block_fixture(sheet, %{type: "text"})

    helpers = build_helpers(project, sheet)

    socket =
      build_socket(%{
        project: project,
        workspace: workspace,
        sheet: sheet,
        blocks: Sheets.list_blocks(sheet.id)
      })

    %{project: project, sheet: sheet, block: block, socket: socket, helpers: helpers}
  end
end
