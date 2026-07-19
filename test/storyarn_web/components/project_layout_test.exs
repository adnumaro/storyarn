defmodule StoryarnWeb.Components.ProjectLayoutTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.Project
  alias StoryarnWeb.Components.ProjectLayout

  test "exposes safe project colors as scoped CSS theme tokens" do
    project = %Project{
      settings: %{
        "theme" => %{
          "primary" => "#00D4CC",
          "accent" => "#E8922F"
        }
      }
    }

    style = ProjectLayout.project_theme_style(project)

    assert style =~ "--primary: 177.74 100.0% 41.57%"
    assert style =~ "--ring: 177.74 100.0% 41.57%"
    assert style =~ "--primary-foreground: 0.0 0.0% 3.92%"
    assert style =~ "--project-accent: 32.11 80.09% 54.71%"
  end

  test "ignores missing or invalid project colors" do
    assert ProjectLayout.project_theme_style(%Project{settings: %{}}) == nil

    project = %Project{
      settings: %{"theme" => %{"primary" => "red", "accent" => "orange"}}
    }

    assert ProjectLayout.project_theme_style(project) == nil
  end
end
