defmodule StoryarnWeb.Live.Shared.TreePanelHandlersTest do
  use ExUnit.Case, async: true

  alias StoryarnWeb.Live.Shared.TreePanelHandlers

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp build_socket(assigns) do
    defaults = %{
      tree_panel_open: false,
      tree_panel_pinned: false,
      pending_delete_id: nil,
      project: %{id: 1}
    }

    merged = Map.merge(defaults, assigns)

    %Phoenix.LiveView.Socket{
      assigns: Map.merge(%{__changed__: %{}, flash: %{}}, merged),
      private: %{lifecycle_events: [], live_temp: %{}}
    }
  end

  # ============================================================================
  # focus_layout_defaults/0
  # ============================================================================

  describe "focus_layout_defaults/0" do
    test "returns expected default assigns" do
      assert TreePanelHandlers.focus_layout_defaults() ==
               [tree_panel_open: false, tree_panel_pinned: false, online_users: []]
    end
  end

  # ============================================================================
  # handle_tree_panel_event/3 — tree_panel_init
  # ============================================================================

  describe "handle_tree_panel_event tree_panel_init" do
    test "syncs pinned state and opens panel when pinned" do
      socket = build_socket(%{tree_panel_pinned: false, tree_panel_open: false})

      {:noreply, result} =
        TreePanelHandlers.handle_tree_panel_event("tree_panel_init", %{"pinned" => true}, socket)

      assert result.assigns.tree_panel_pinned == true
      assert result.assigns.tree_panel_open == true
    end

    test "keeps panel closed when not pinned" do
      socket = build_socket(%{tree_panel_pinned: false, tree_panel_open: false})

      {:noreply, result} =
        TreePanelHandlers.handle_tree_panel_event("tree_panel_init", %{"pinned" => false}, socket)

      assert result.assigns.tree_panel_pinned == false
      assert result.assigns.tree_panel_open == false
    end
  end

  # ============================================================================
  # handle_tree_panel_event/3 — tree_panel_toggle
  # ============================================================================

  describe "handle_tree_panel_event tree_panel_toggle" do
    test "opens closed panel" do
      socket = build_socket(%{tree_panel_open: false})

      {:noreply, result} =
        TreePanelHandlers.handle_tree_panel_event("tree_panel_toggle", %{}, socket)

      assert result.assigns.tree_panel_open == true
    end

    test "closes open panel" do
      socket = build_socket(%{tree_panel_open: true})

      {:noreply, result} =
        TreePanelHandlers.handle_tree_panel_event("tree_panel_toggle", %{}, socket)

      assert result.assigns.tree_panel_open == false
    end
  end

  # ============================================================================
  # handle_tree_panel_event/3 — tree_panel_pin
  # ============================================================================

  describe "handle_tree_panel_event tree_panel_pin" do
    test "pinning keeps panel open state" do
      socket = build_socket(%{tree_panel_pinned: false, tree_panel_open: true})

      {:noreply, result} =
        TreePanelHandlers.handle_tree_panel_event("tree_panel_pin", %{}, socket)

      assert result.assigns.tree_panel_pinned == true
      assert result.assigns.tree_panel_open == true
    end

    test "unpinning closes the panel" do
      socket = build_socket(%{tree_panel_pinned: true, tree_panel_open: true})

      {:noreply, result} =
        TreePanelHandlers.handle_tree_panel_event("tree_panel_pin", %{}, socket)

      assert result.assigns.tree_panel_pinned == false
      assert result.assigns.tree_panel_open == false
    end

    test "pinning from closed state keeps panel closed" do
      socket = build_socket(%{tree_panel_pinned: false, tree_panel_open: false})

      {:noreply, result} =
        TreePanelHandlers.handle_tree_panel_event("tree_panel_pin", %{}, socket)

      assert result.assigns.tree_panel_pinned == true
      assert result.assigns.tree_panel_open == false
    end
  end

  # ============================================================================
  # handle_set_pending_delete/2
  # ============================================================================

  describe "handle_set_pending_delete/2" do
    test "sets pending_delete_id on socket" do
      socket = build_socket(%{pending_delete_id: nil})

      {:noreply, result} = TreePanelHandlers.handle_set_pending_delete(socket, "42")

      assert result.assigns.pending_delete_id == "42"
    end
  end

  # ============================================================================
  # handle_confirm_delete/2
  # ============================================================================

  describe "handle_confirm_delete/2" do
    test "calls delete_fn with socket and id, clears pending_delete_id" do
      socket = build_socket(%{pending_delete_id: "42"})

      called = :atomics.new(1, signed: false)

      delete_fn = fn received_socket, id ->
        :atomics.put(called, 1, 1)
        assert id == "42"
        assert received_socket.assigns.pending_delete_id == nil
        {:noreply, received_socket}
      end

      {:noreply, result} = TreePanelHandlers.handle_confirm_delete(socket, delete_fn)

      assert :atomics.get(called, 1) == 1
      assert result.assigns.pending_delete_id == nil
    end

    test "returns socket unchanged when no pending_delete_id" do
      socket = build_socket(%{pending_delete_id: nil})

      delete_fn = fn _socket, _id ->
        flunk("delete_fn should not be called")
      end

      {:noreply, result} = TreePanelHandlers.handle_confirm_delete(socket, delete_fn)

      assert result.assigns.pending_delete_id == nil
    end
  end

  # ============================================================================
  # handle_create_entity/5
  # ============================================================================

  describe "handle_create_entity/5" do
    test "on success, navigates to entity path" do
      socket = build_socket(%{project: %{id: 1}})
      entity = %{id: 42, name: "New Flow"}

      create_fn = fn _project, _attrs -> {:ok, entity} end
      path_fn = fn _socket, e -> "/flows/#{e.id}" end

      {:noreply, result} =
        TreePanelHandlers.handle_create_entity(
          socket,
          %{name: "Untitled"},
          create_fn,
          path_fn,
          "Could not create"
        )

      assert result.redirected == {:live, :redirect, %{to: "/flows/42", kind: :push}}
    end

    test "on error, sets error flash" do
      socket = build_socket(%{project: %{id: 1}})

      create_fn = fn _project, _attrs -> {:error, %Ecto.Changeset{}} end
      path_fn = fn _socket, _e -> "/flows/never" end

      {:noreply, result} =
        TreePanelHandlers.handle_create_entity(
          socket,
          %{name: "Untitled"},
          create_fn,
          path_fn,
          "Could not create flow."
        )

      assert result.assigns.flash["error"] == "Could not create flow."
    end
  end

  # ============================================================================
  # handle_create_child/6
  # ============================================================================

  describe "handle_create_child/6" do
    test "merges parent_id into attrs and creates entity" do
      socket = build_socket(%{project: %{id: 1}})
      entity = %{id: 55}

      create_fn = fn _project, attrs ->
        assert attrs[:parent_id] == "parent-123"
        assert attrs[:name] == "Child"
        {:ok, entity}
      end

      path_fn = fn _socket, e -> "/entities/#{e.id}" end

      {:noreply, result} =
        TreePanelHandlers.handle_create_child(
          socket,
          "parent-123",
          %{name: "Child"},
          create_fn,
          path_fn,
          "Could not create"
        )

      assert result.redirected == {:live, :redirect, %{to: "/entities/55", kind: :push}}
    end
  end

  # ============================================================================
  # handle_delete_entity/3
  # ============================================================================

  describe "handle_delete_entity/3" do
    test "when entity is nil and not_found_msg is set, shows error flash" do
      socket = build_socket(%{project: %{id: 1}})

      {:noreply, result} =
        TreePanelHandlers.handle_delete_entity(socket, "999",
          get_fn: fn _project_id, _id -> nil end,
          delete_fn: fn _entity -> flunk("should not be called") end,
          current_entity_id: 1,
          index_path: "/index",
          reload_tree_fn: fn s -> s end,
          error_msg: "Error",
          not_found_msg: "Not found"
        )

      assert result.assigns.flash["error"] == "Not found"
    end

    test "when entity is nil and no not_found_msg, returns socket unchanged" do
      socket = build_socket(%{project: %{id: 1}})

      {:noreply, result} =
        TreePanelHandlers.handle_delete_entity(socket, "999",
          get_fn: fn _project_id, _id -> nil end,
          delete_fn: fn _entity -> flunk("should not be called") end,
          current_entity_id: 1,
          index_path: "/index",
          reload_tree_fn: fn s -> s end,
          error_msg: "Error"
        )

      refute Map.has_key?(result.assigns.flash, "error")
    end

    test "deleting current entity navigates to index_path" do
      socket = build_socket(%{project: %{id: 1}})
      entity = %{id: 42}

      {:noreply, result} =
        TreePanelHandlers.handle_delete_entity(socket, "42",
          get_fn: fn _project_id, _id -> entity end,
          delete_fn: fn _entity -> {:ok, entity} end,
          current_entity_id: 42,
          index_path: "/flows",
          reload_tree_fn: fn s -> s end,
          success_msg: "Deleted!",
          error_msg: "Error"
        )

      assert result.redirected == {:live, :redirect, %{to: "/flows", kind: :push}}
      assert result.assigns.flash["info"] == "Deleted!"
    end

    test "deleting different entity reloads tree" do
      socket = build_socket(%{project: %{id: 1}})
      entity = %{id: 42}
      tree_reloaded = :atomics.new(1, signed: false)

      {:noreply, result} =
        TreePanelHandlers.handle_delete_entity(socket, "42",
          get_fn: fn _project_id, _id -> entity end,
          delete_fn: fn _entity -> {:ok, entity} end,
          current_entity_id: 99,
          index_path: "/flows",
          reload_tree_fn: fn s ->
            :atomics.put(tree_reloaded, 1, 1)
            s
          end,
          success_msg: "Deleted!",
          error_msg: "Error"
        )

      assert :atomics.get(tree_reloaded, 1) == 1
      assert result.assigns.flash["info"] == "Deleted!"
      refute result.redirected
    end

    test "delete without success_msg does not set info flash" do
      socket = build_socket(%{project: %{id: 1}})
      entity = %{id: 42}

      {:noreply, result} =
        TreePanelHandlers.handle_delete_entity(socket, "42",
          get_fn: fn _project_id, _id -> entity end,
          delete_fn: fn _entity -> {:ok, entity} end,
          current_entity_id: 99,
          index_path: "/flows",
          reload_tree_fn: fn s -> s end,
          error_msg: "Error"
        )

      refute Map.has_key?(result.assigns.flash, "info")
    end

    test "on delete error, sets error flash" do
      socket = build_socket(%{project: %{id: 1}})
      entity = %{id: 42}

      {:noreply, result} =
        TreePanelHandlers.handle_delete_entity(socket, "42",
          get_fn: fn _project_id, _id -> entity end,
          delete_fn: fn _entity -> {:error, :some_error} end,
          current_entity_id: 99,
          index_path: "/flows",
          reload_tree_fn: fn s -> s end,
          error_msg: "Could not delete."
        )

      assert result.assigns.flash["error"] == "Could not delete."
    end

    test "compares entity_id with current_entity_id as strings" do
      socket = build_socket(%{project: %{id: 1}})
      entity = %{id: 42}

      # entity_id is string "42", current_entity_id is integer 42
      # Both should be compared as strings
      {:noreply, result} =
        TreePanelHandlers.handle_delete_entity(socket, "42",
          get_fn: fn _pid, _id -> entity end,
          delete_fn: fn _entity -> {:ok, entity} end,
          current_entity_id: 42,
          index_path: "/index",
          reload_tree_fn: fn s -> s end,
          error_msg: "Error"
        )

      # Should navigate because string "42" == to_string(42)
      assert result.redirected == {:live, :redirect, %{to: "/index", kind: :push}}
    end
  end

  # ============================================================================
  # handle_move_entity/5
  # ============================================================================

  describe "handle_move_entity/5" do
    test "on success, reloads tree" do
      socket = build_socket(%{project: %{id: 1}})
      entity = %{id: 10}
      tree_reloaded = :atomics.new(1, signed: false)

      {:noreply, _result} =
        TreePanelHandlers.handle_move_entity(socket, "10", "5", "2",
          get_fn: fn _project_id, _id -> entity end,
          move_fn: fn _entity, new_parent_id, position ->
            assert new_parent_id == 5
            assert position == 2
            {:ok, entity}
          end,
          reload_tree_fn: fn s ->
            :atomics.put(tree_reloaded, 1, 1)
            s
          end,
          error_msg: "Could not move."
        )

      assert :atomics.get(tree_reloaded, 1) == 1
    end

    test "on error, sets error flash" do
      socket = build_socket(%{project: %{id: 1}})
      entity = %{id: 10}

      {:noreply, result} =
        TreePanelHandlers.handle_move_entity(socket, "10", "5", "0",
          get_fn: fn _project_id, _id -> entity end,
          move_fn: fn _entity, _new_parent_id, _pos -> {:error, :some_error} end,
          reload_tree_fn: fn s -> s end,
          error_msg: "Could not move."
        )

      assert result.assigns.flash["error"] == "Could not move."
    end

    test "handles nil parent_id (move to root)" do
      socket = build_socket(%{project: %{id: 1}})
      entity = %{id: 10}

      {:noreply, _result} =
        TreePanelHandlers.handle_move_entity(socket, "10", nil, "0",
          get_fn: fn _project_id, _id -> entity end,
          move_fn: fn _entity, new_parent_id, position ->
            assert new_parent_id == nil
            assert position == 0
            {:ok, entity}
          end,
          reload_tree_fn: fn s -> s end,
          error_msg: "Error"
        )
    end

    test "handles empty string parent_id (move to root)" do
      socket = build_socket(%{project: %{id: 1}})
      entity = %{id: 10}

      {:noreply, _result} =
        TreePanelHandlers.handle_move_entity(socket, "10", "", "0",
          get_fn: fn _project_id, _id -> entity end,
          move_fn: fn _entity, new_parent_id, position ->
            assert new_parent_id == nil
            assert position == 0
            {:ok, entity}
          end,
          reload_tree_fn: fn s -> s end,
          error_msg: "Error"
        )
    end

    test "defaults position to 0 when nil" do
      socket = build_socket(%{project: %{id: 1}})
      entity = %{id: 10}

      {:noreply, _result} =
        TreePanelHandlers.handle_move_entity(socket, "10", "5", nil,
          get_fn: fn _project_id, _id -> entity end,
          move_fn: fn _entity, _new_parent_id, position ->
            assert position == 0
            {:ok, entity}
          end,
          reload_tree_fn: fn s -> s end,
          error_msg: "Error"
        )
    end
  end
end
