defmodule Storyarn.Shared.NameNormalizerTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Shared.NameNormalizer

  # ===========================================================================
  # slugify/1
  # ===========================================================================

  describe "slugify/1" do
    test "converts simple name to slug" do
      assert NameNormalizer.slugify("My Workspace") == "my-workspace"
    end

    test "converts multiple spaces to single separator" do
      assert NameNormalizer.slugify("Hello   World") == "hello-world"
    end

    test "strips special characters" do
      assert NameNormalizer.slugify("Hello! @World#") == "hello-world"
    end

    test "handles Unicode transliteration (accents to ASCII)" do
      assert NameNormalizer.slugify("cafe") == "cafe"
      assert NameNormalizer.slugify("Resume") == "resume"
    end

    test "handles accented characters" do
      assert NameNormalizer.slugify("El Nino") == "el-nino"
    end

    test "returns empty string for nil" do
      assert NameNormalizer.slugify(nil) == ""
    end

    test "returns empty string for empty string" do
      assert NameNormalizer.slugify("") == ""
    end

    test "trims leading/trailing separators" do
      assert NameNormalizer.slugify("-hello-") == "hello"
      assert NameNormalizer.slugify("  hello  ") == "hello"
    end

    test "handles all-special-character input" do
      assert NameNormalizer.slugify("!@#$%^&*()") == ""
    end

    test "preserves numbers" do
      assert NameNormalizer.slugify("Project 42") == "project-42"
    end

    test "collapses multiple dashes" do
      assert NameNormalizer.slugify("hello---world") == "hello-world"
    end

    test "handles mixed case" do
      assert NameNormalizer.slugify("MyProject") == "myproject"
    end
  end

  # ===========================================================================
  # variablify/1
  # ===========================================================================

  describe "variablify/1" do
    test "converts label to variable name" do
      assert NameNormalizer.variablify("Health Points") == "health_points"
    end

    test "preserves dots for nested references" do
      assert NameNormalizer.variablify("mc.jaime.health") == "mc.jaime.health"
    end

    test "returns nil for nil input" do
      assert NameNormalizer.variablify(nil) == nil
    end

    test "returns nil for empty string" do
      assert NameNormalizer.variablify("") == nil
    end

    test "strips special characters except dots and underscores" do
      assert NameNormalizer.variablify("Health!Points") == "healthpoints"
    end

    test "handles Unicode characters" do
      assert NameNormalizer.variablify("Energia") == "energia"
    end

    test "collapses multiple underscores" do
      assert NameNormalizer.variablify("hello   world") == "hello_world"
    end

    test "trims leading/trailing separators and dots" do
      assert NameNormalizer.variablify("_hello_") == "hello"
      assert NameNormalizer.variablify(".hello.") == "hello"
    end

    test "returns empty string for all-special-character input" do
      # normalize returns "" after stripping all special chars.
      # variablify(name) calls normalize(name, "_", ".") || nil
      # In Elixir, "" is truthy, so "" || nil == ""
      assert NameNormalizer.variablify("!@#$%^&*()") == ""
    end

    test "preserves numbers" do
      assert NameNormalizer.variablify("Level 5 Stats") == "level_5_stats"
    end
  end

  # ===========================================================================
  # shortcutify/1
  # ===========================================================================

  describe "shortcutify/1" do
    test "converts entity name to shortcut" do
      assert NameNormalizer.shortcutify("MC.Jaime") == "mc.jaime"
    end

    test "preserves dots in shortcut" do
      assert NameNormalizer.shortcutify("Main.Character") == "main.character"
    end

    test "uses hyphens for spaces" do
      assert NameNormalizer.shortcutify("My Entity Name") == "my-entity-name"
    end

    test "handles nil input" do
      assert NameNormalizer.shortcutify(nil) == ""
    end

    test "handles empty string input" do
      assert NameNormalizer.shortcutify("") == ""
    end

    test "strips special characters except dots and hyphens" do
      assert NameNormalizer.shortcutify("MC!Jaime") == "mcjaime"
    end

    test "collapses multiple dots" do
      assert NameNormalizer.shortcutify("MC..Jaime") == "mc.jaime"
    end

    test "collapses multiple hyphens" do
      assert NameNormalizer.shortcutify("My   Entity") == "my-entity"
    end

    test "trims leading/trailing dots and hyphens" do
      assert NameNormalizer.shortcutify(".mc.jaime.") == "mc.jaime"
      assert NameNormalizer.shortcutify("-mc-jaime-") == "mc-jaime"
    end

    test "handles Unicode transliteration" do
      assert NameNormalizer.shortcutify("Cafe.Paris") == "cafe.paris"
    end
  end

  # ===========================================================================
  # generate_unique_slug/4
  # ===========================================================================

  describe "generate_unique_slug/4" do
    test "generates slug from name when no collision" do
      # Using Storyarn.Workspaces.Workspace which has a slug field
      slug =
        NameNormalizer.generate_unique_slug(Storyarn.Workspaces.Workspace, [], "My Workspace")

      assert slug == "my-workspace"
    end

    test "generates slug with suffix on collision" do
      import Storyarn.WorkspacesFixtures

      # Create a workspace to cause collision (fixture includes slug)
      user = Storyarn.AccountsFixtures.user_fixture()
      _workspace = workspace_fixture(user, %{name: "Test Workspace"})

      # Now try to generate slug for the same name - it should add a suffix
      slug =
        NameNormalizer.generate_unique_slug(
          Storyarn.Workspaces.Workspace,
          [],
          "Test Workspace"
        )

      assert String.starts_with?(slug, "test-workspace")
      # Should have a suffix since "test-workspace" is taken
      assert slug != "test-workspace"
    end

    test "generates slug with scope filtering" do
      import Storyarn.WorkspacesFixtures

      user = Storyarn.AccountsFixtures.user_fixture()
      workspace = workspace_fixture(user, %{name: "Scoped Workspace"})

      # Generate slug for a different name - no collision
      slug =
        NameNormalizer.generate_unique_slug(
          Storyarn.Workspaces.Workspace,
          [],
          "Unique Name"
        )

      assert slug == "unique-name"
      assert workspace.slug == "scoped-workspace"
    end
  end

  # ===========================================================================
  # maybe_regenerate/4
  # ===========================================================================

  describe "maybe_regenerate/4" do
    test "generates from new name when current is nil" do
      result = NameNormalizer.maybe_regenerate(nil, "New Name", false, &NameNormalizer.slugify/1)
      assert result == "new-name"
    end

    test "generates from new name when current is empty string" do
      result = NameNormalizer.maybe_regenerate("", "New Name", false, &NameNormalizer.slugify/1)
      assert result == "new-name"
    end

    test "keeps current value when referenced" do
      result =
        NameNormalizer.maybe_regenerate("old-slug", "New Name", true, &NameNormalizer.slugify/1)

      assert result == "old-slug"
    end

    test "regenerates from new name when not referenced" do
      result =
        NameNormalizer.maybe_regenerate("old-slug", "New Name", false, &NameNormalizer.slugify/1)

      assert result == "new-name"
    end

    test "works with variablify as normalize function" do
      result =
        NameNormalizer.maybe_regenerate(nil, "Health Points", false, &NameNormalizer.variablify/1)

      assert result == "health_points"
    end

    test "works with shortcutify as normalize function" do
      result =
        NameNormalizer.maybe_regenerate(nil, "MC.Jaime", false, &NameNormalizer.shortcutify/1)

      assert result == "mc.jaime"
    end

    test "generates from new name when current is nil and referenced is true" do
      # nil/empty current always generates, regardless of referenced? flag
      result = NameNormalizer.maybe_regenerate(nil, "New Name", true, &NameNormalizer.slugify/1)
      assert result == "new-name"
    end
  end
end
