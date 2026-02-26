defmodule Storyarn.Workspaces.WorkspaceTest do
  use ExUnit.Case, async: true

  alias Storyarn.Workspaces.Workspace

  defp valid_create_attrs do
    %{name: "My Workspace", slug: "my-workspace"}
  end

  # =============================================================================
  # create_changeset/2
  # =============================================================================

  describe "create_changeset/2" do
    test "valid with minimal required attrs" do
      cs = Workspace.create_changeset(%Workspace{}, valid_create_attrs())
      assert cs.valid?
    end

    test "valid with all optional attrs" do
      cs =
        Workspace.create_changeset(%Workspace{}, %{
          name: "My Workspace",
          slug: "my-workspace",
          description: "A nice workspace",
          color: "#3b82f6",
          source_locale: "es"
        })

      assert cs.valid?
    end

    test "invalid without name" do
      cs = Workspace.create_changeset(%Workspace{}, %{slug: "my-workspace"})
      refute cs.valid?
      assert errors_on(cs)[:name]
    end

    test "invalid without slug" do
      cs = Workspace.create_changeset(%Workspace{}, %{name: "My Workspace"})
      refute cs.valid?
      assert errors_on(cs)[:slug]
    end

    test "name max length 100" do
      cs =
        Workspace.create_changeset(%Workspace{}, %{
          name: String.duplicate("a", 101),
          slug: "test"
        })

      refute cs.valid?
      assert errors_on(cs)[:name]
    end

    test "name min length 1" do
      cs = Workspace.create_changeset(%Workspace{}, %{name: "", slug: "test"})
      refute cs.valid?
    end

    test "description max length 1000" do
      cs =
        Workspace.create_changeset(%Workspace{}, %{
          name: "Test",
          slug: "test",
          description: String.duplicate("a", 1001)
        })

      refute cs.valid?
      assert errors_on(cs)[:description]
    end
  end

  # =============================================================================
  # Slug validation
  # =============================================================================

  describe "slug validation" do
    test "valid slug formats" do
      for slug <- ~w(test my-workspace workspace-123 a 1) do
        cs = Workspace.create_changeset(%Workspace{}, %{name: "Test", slug: slug})
        assert cs.valid?, "Expected slug '#{slug}' to be valid"
      end
    end

    test "invalid slug - uppercase" do
      cs = Workspace.create_changeset(%Workspace{}, %{name: "Test", slug: "MyWorkspace"})
      refute cs.valid?
      assert errors_on(cs)[:slug]
    end

    test "invalid slug - spaces" do
      cs = Workspace.create_changeset(%Workspace{}, %{name: "Test", slug: "my workspace"})
      refute cs.valid?
      assert errors_on(cs)[:slug]
    end

    test "invalid slug - leading hyphen" do
      cs = Workspace.create_changeset(%Workspace{}, %{name: "Test", slug: "-test"})
      refute cs.valid?
      assert errors_on(cs)[:slug]
    end

    test "invalid slug - trailing hyphen" do
      cs = Workspace.create_changeset(%Workspace{}, %{name: "Test", slug: "test-"})
      refute cs.valid?
      assert errors_on(cs)[:slug]
    end

    test "invalid slug - consecutive hyphens" do
      cs = Workspace.create_changeset(%Workspace{}, %{name: "Test", slug: "test--slug"})
      refute cs.valid?
      assert errors_on(cs)[:slug]
    end

    test "slug max length 100" do
      cs =
        Workspace.create_changeset(%Workspace{}, %{
          name: "Test",
          slug: String.duplicate("a", 101)
        })

      refute cs.valid?
      assert errors_on(cs)[:slug]
    end
  end

  # =============================================================================
  # Color validation
  # =============================================================================

  describe "color validation in create_changeset" do
    test "valid 3-char hex color" do
      cs = Workspace.create_changeset(%Workspace{}, %{name: "T", slug: "t", color: "#fff"})
      assert cs.valid?
    end

    test "valid 6-char hex color" do
      cs = Workspace.create_changeset(%Workspace{}, %{name: "T", slug: "t", color: "#3b82f6"})
      assert cs.valid?
    end

    test "valid 8-char hex color with alpha" do
      cs =
        Workspace.create_changeset(%Workspace{}, %{name: "T", slug: "t", color: "#3b82f680"})

      assert cs.valid?
    end

    test "invalid color - missing hash" do
      cs = Workspace.create_changeset(%Workspace{}, %{name: "T", slug: "t", color: "3b82f6"})
      refute cs.valid?
      assert errors_on(cs)[:color]
    end

    test "invalid color - wrong length" do
      cs = Workspace.create_changeset(%Workspace{}, %{name: "T", slug: "t", color: "#FFFF"})
      refute cs.valid?
      assert errors_on(cs)[:color]
    end

    test "invalid color - non-hex chars" do
      cs = Workspace.create_changeset(%Workspace{}, %{name: "T", slug: "t", color: "#GGHHII"})
      refute cs.valid?
      assert errors_on(cs)[:color]
    end

    test "nil color is valid (skips validation)" do
      cs = Workspace.create_changeset(%Workspace{}, %{name: "T", slug: "t"})
      assert cs.valid?
    end
  end

  # =============================================================================
  # update_changeset/2
  # =============================================================================

  describe "update_changeset/2" do
    test "valid with name change" do
      cs = Workspace.update_changeset(%Workspace{name: "Old"}, %{name: "New"})
      assert cs.valid?
    end

    test "invalid without name" do
      cs = Workspace.update_changeset(%Workspace{name: "Old"}, %{name: ""})
      refute cs.valid?
    end

    test "validates color on update" do
      cs = Workspace.update_changeset(%Workspace{name: "Test"}, %{color: "invalid"})
      refute cs.valid?
      assert errors_on(cs)[:color]
    end

    test "allows updating description" do
      cs =
        Workspace.update_changeset(%Workspace{name: "Test"}, %{
          description: "Updated description"
        })

      assert cs.valid?
    end

    test "does not allow slug changes on update" do
      cs = Workspace.update_changeset(%Workspace{name: "Test"}, %{slug: "new-slug"})
      # slug is not in update_changeset's cast list, so change is ignored
      assert cs.valid?
      refute Ecto.Changeset.get_change(cs, :slug)
    end
  end

  # =============================================================================
  # Schema defaults
  # =============================================================================

  describe "schema defaults" do
    test "source_locale defaults to en" do
      assert %Workspace{}.source_locale == "en"
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
