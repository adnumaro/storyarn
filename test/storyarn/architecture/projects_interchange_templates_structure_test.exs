defmodule Storyarn.Architecture.ProjectsInterchangeTemplatesStructureTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.Imports
  alias Storyarn.Projects.Imports.Cancellation
  alias Storyarn.Projects.Imports.ImportLifecycle
  alias Storyarn.Projects.Imports.ImportQueue

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
    assert Code.ensure_loaded?(Imports)
    assert Code.ensure_loaded?(Storyarn.Projects.Exports)
    assert Code.ensure_loaded?(Storyarn.Projects.ProjectTemplates)
  end

  test "import cancellation has one direct command owner" do
    assert Code.ensure_loaded?(Cancellation)
    assert Code.ensure_loaded?(ImportLifecycle)
    assert Code.ensure_loaded?(ImportQueue)

    imports = beam_imports(Imports)

    for arity <- [2, 3] do
      assert {Cancellation, :cancel_import, arity} in imports

      refute function_exported?(
               ImportLifecycle,
               :cancel_import,
               arity
             )

      refute function_exported?(
               ImportQueue,
               :cancel_import,
               arity
             )
    end
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
          assert role in ~w(
                   commands queries entities contracts projections reference_data records rules execution adapters
                 )
      end
    end)
  end

  defp beam_imports(module) do
    {:ok, {_module, [{:imports, imports}]}} =
      module
      |> :code.which()
      |> :beam_lib.chunks([:imports])

    imports
  end
end
