defmodule Storyarn.Screenplays.ScreenplayTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Screenplays.Screenplay

  describe "create_changeset/2" do
    test "valid with name" do
      changeset = Screenplay.create_changeset(%Screenplay{}, %{name: "Act 1"})
      assert changeset.valid?
      assert get_change(changeset, :name) == "Act 1"
    end

    test "requires name" do
      changeset = Screenplay.create_changeset(%Screenplay{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "rejects empty name" do
      changeset = Screenplay.create_changeset(%Screenplay{}, %{name: ""})
      refute changeset.valid?
    end

    test "rejects name longer than 200 characters" do
      long_name = String.duplicate("a", 201)
      changeset = Screenplay.create_changeset(%Screenplay{}, %{name: long_name})
      refute changeset.valid?
      assert "should be at most 200 character(s)" in errors_on(changeset).name
    end

    test "accepts name at max length (200)" do
      name = String.duplicate("a", 200)
      changeset = Screenplay.create_changeset(%Screenplay{}, %{name: name})
      assert changeset.valid?
    end

    test "accepts valid shortcut" do
      changeset = Screenplay.create_changeset(%Screenplay{}, %{name: "Test", shortcut: "act-1"})
      assert changeset.valid?
    end

    test "accepts shortcut with dots" do
      changeset =
        Screenplay.create_changeset(%Screenplay{}, %{name: "Test", shortcut: "act.intro"})

      assert changeset.valid?
    end

    test "accepts single character shortcut" do
      changeset = Screenplay.create_changeset(%Screenplay{}, %{name: "Test", shortcut: "a"})
      assert changeset.valid?
    end

    test "rejects shortcut with spaces" do
      changeset = Screenplay.create_changeset(%Screenplay{}, %{name: "Test", shortcut: "act 1"})
      refute changeset.valid?
    end

    test "rejects shortcut with uppercase" do
      changeset = Screenplay.create_changeset(%Screenplay{}, %{name: "Test", shortcut: "Act1"})
      refute changeset.valid?
    end

    test "accepts description" do
      changeset =
        Screenplay.create_changeset(%Screenplay{}, %{name: "Test", description: "A scene"})

      assert changeset.valid?
      assert get_change(changeset, :description) == "A scene"
    end

    test "rejects description longer than 2000 characters" do
      long_desc = String.duplicate("a", 2001)

      changeset =
        Screenplay.create_changeset(%Screenplay{}, %{name: "Test", description: long_desc})

      refute changeset.valid?
    end

    test "accepts parent_id and position" do
      changeset =
        Screenplay.create_changeset(%Screenplay{}, %{name: "Test", parent_id: 1, position: 3})

      assert changeset.valid?
    end
  end

  describe "update_changeset/2" do
    test "updates name" do
      screenplay = %Screenplay{name: "Old", shortcut: "old"}

      changeset = Screenplay.update_changeset(screenplay, %{name: "New Name"})
      assert changeset.valid?
      assert get_change(changeset, :name) == "New Name"
    end

    test "requires name on update" do
      screenplay = %Screenplay{name: "Old"}

      changeset = Screenplay.update_changeset(screenplay, %{name: nil})
      refute changeset.valid?
    end

    test "updates shortcut" do
      screenplay = %Screenplay{name: "Test", shortcut: "old"}

      changeset = Screenplay.update_changeset(screenplay, %{shortcut: "new-shortcut"})
      assert changeset.valid?
      assert get_change(changeset, :shortcut) == "new-shortcut"
    end
  end

  describe "move_changeset/2" do
    test "changes parent_id and position" do
      screenplay = %Screenplay{name: "Test", parent_id: nil, position: 0}

      changeset = Screenplay.move_changeset(screenplay, %{parent_id: 5, position: 2})
      assert changeset.valid?
      assert get_change(changeset, :parent_id) == 5
      assert get_change(changeset, :position) == 2
    end
  end

  describe "delete_changeset/1" do
    test "sets deleted_at" do
      screenplay = %Screenplay{name: "Test", deleted_at: nil}

      changeset = Screenplay.delete_changeset(screenplay)
      assert changeset.valid?
      assert get_change(changeset, :deleted_at) != nil
    end
  end

  describe "restore_changeset/1" do
    test "clears deleted_at" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      screenplay = %Screenplay{name: "Test", deleted_at: now}

      changeset = Screenplay.restore_changeset(screenplay)
      assert changeset.valid?
      assert get_change(changeset, :deleted_at) == nil
    end
  end

  describe "link_flow_changeset/2" do
    test "sets linked_flow_id" do
      screenplay = %Screenplay{name: "Test", linked_flow_id: nil}

      changeset = Screenplay.link_flow_changeset(screenplay, %{linked_flow_id: 42})
      assert changeset.valid?
      assert get_change(changeset, :linked_flow_id) == 42
    end

    test "clears linked_flow_id (unlink)" do
      screenplay = %Screenplay{name: "Test", linked_flow_id: 42}

      changeset = Screenplay.link_flow_changeset(screenplay, %{linked_flow_id: nil})
      assert changeset.valid?
      assert get_change(changeset, :linked_flow_id) == nil
    end
  end

  describe "draft?/1" do
    test "returns true when draft_of_id is set" do
      assert Screenplay.draft?(%Screenplay{draft_of_id: 1})
    end

    test "returns false when draft_of_id is nil" do
      refute Screenplay.draft?(%Screenplay{draft_of_id: nil})
    end
  end

  describe "deleted?/1" do
    test "returns true when deleted_at is set" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      assert Screenplay.deleted?(%Screenplay{deleted_at: now})
    end

    test "returns false when deleted_at is nil" do
      refute Screenplay.deleted?(%Screenplay{deleted_at: nil})
    end
  end
end
