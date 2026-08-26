defmodule Storyarn.Architecture.ProjectsInterchangeTemplatesStructureTest do
  use ExUnit.Case, async: true

  @projects_root Path.expand("../../../lib/storyarn/projects", __DIR__)

  test "imports and exports live under the Interchange capability" do
    refute File.exists?(Path.join(@projects_root, "imports.ex"))
    refute File.exists?(Path.join(@projects_root, "imports"))
    refute File.exists?(Path.join(@projects_root, "exports.ex"))
    refute File.exists?(Path.join(@projects_root, "exports"))

    assert File.regular?(Path.join(@projects_root, "interchange/interchange.ex"))
    assert File.regular?(Path.join(@projects_root, "interchange/imports/imports.ex"))
    assert File.regular?(Path.join(@projects_root, "interchange/exports/exports.ex"))

    assert_role_layout("interchange/imports", "imports.ex")
    assert_role_layout("interchange/exports", "exports.ex")
  end

  test "project templates live under the Templates capability" do
    refute File.exists?(Path.join(@projects_root, "project_templates.ex"))
    refute File.exists?(Path.join(@projects_root, "project_templates"))

    assert File.regular?(Path.join(@projects_root, "templates/templates.ex"))
    assert File.regular?(Path.join(@projects_root, "templates/project_templates.ex"))

    assert_role_layout("templates", ["templates.ex", "project_templates.ex"])
  end

  test "stable implementation module identities remain available" do
    assert Code.ensure_loaded?(Storyarn.Projects.Imports)
    assert Code.ensure_loaded?(Storyarn.Projects.Exports)
    assert Code.ensure_loaded?(Storyarn.Projects.ProjectTemplates)
  end

  defp assert_role_layout(relative_root, capability_facades) do
    capability_facades = List.wrap(capability_facades)

    relative_root
    |> then(&Path.join(@projects_root, &1))
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.each(fn file ->
      case file |> Path.relative_to(Path.join(@projects_root, relative_root)) |> Path.split() do
        [facade] ->
          assert facade in capability_facades

        [role | _rest] ->
          assert role in ~w(commands queries entities contracts data rules execution adapters)
      end
    end)
  end
end
