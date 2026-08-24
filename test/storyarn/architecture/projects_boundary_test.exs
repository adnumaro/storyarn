defmodule Storyarn.Architecture.ProjectsBoundaryTest do
  use ExUnit.Case, async: true

  @projects_domain_sources ["lib/storyarn/projects.ex" | Path.wildcard("lib/storyarn/projects/**/*.ex")] ++
                             ["lib/storyarn/references.ex" | Path.wildcard("lib/storyarn/references/**/*.ex")] ++
                             ["lib/storyarn/versioning.ex" | Path.wildcard("lib/storyarn/versioning/**/*.ex")] ++
                             ["lib/storyarn/exports.ex" | Path.wildcard("lib/storyarn/exports/**/*.ex")] ++
                             ["lib/storyarn/imports.ex" | Path.wildcard("lib/storyarn/imports/**/*.ex")] ++
                             [
                               "lib/storyarn/project_templates.ex"
                               | Path.wildcard("lib/storyarn/project_templates/**/*.ex")
                             ] ++
                             ["lib/storyarn/assets.ex" | Path.wildcard("lib/storyarn/assets/**/*.ex")]

  @projects_web_sources Path.wildcard("lib/storyarn_web/live/project_live/**/*.ex") ++
                          Path.wildcard("lib/storyarn_web/live/project_settings_live/**/*.ex") ++
                          Path.wildcard("lib/storyarn_web/live/asset_live/**/*.ex") ++
                          Path.wildcard("lib/storyarn_web/live/template_live/**/*.ex") ++
                          [
                            "lib/storyarn_web/controllers/export_controller.ex",
                            "lib/storyarn_web/controllers/private_media_controller.ex",
                            "lib/storyarn_web/controllers/snapshot_download_controller.ex",
                            "lib/storyarn_web/controllers/upload_controller.ex"
                          ]

  # Reclassified into the projects boundary during ENG-92; their consumers
  # must stay inside it so they cannot silently regrow into shared utilities.
  @reclassified_shared [
    "lib/storyarn/shared/name_normalizer.ex",
    "lib/storyarn/shared/validations.ex",
    "lib/storyarn/shared/word_count.ex"
  ]

  @foreign_domain_roots [
    "lib/storyarn/accounts",
    "lib/storyarn/workspaces",
    "lib/storyarn/flows",
    "lib/storyarn/scenes",
    "lib/storyarn/sheets",
    "lib/storyarn/localization",
    "lib/storyarn/ai",
    "lib/storyarn/billing",
    "lib/storyarn/notifications",
    "lib/storyarn/platform"
  ]

  test "Projects domain does not depend on StoryarnWeb" do
    violations =
      @projects_domain_sources
      |> Enum.flat_map(&storyarn_web_references/1)
      |> Enum.sort()

    assert violations == [], """
    The Project boundary cannot depend on its Phoenix or LiveVue adapters:

    #{Enum.join(violations, "\n")}
    """
  end

  test "Project Web cannot publish generic business facts" do
    violations =
      Enum.filter(@projects_web_sources, fn path ->
        File.read!(path) =~ "Projects.Events"
      end)

    refute File.read!("lib/storyarn/projects.ex") =~ "defdelegate emit_event"

    assert violations == [], """
    Web adapters may call typed Project commands, but may not choose an event name
    or construct a domain-event payload themselves:

    #{Enum.join(violations, "\n")}
    """
  end

  test "the ratchet seals every boundary and the debt baseline stays empty" do
    config = File.read!("config/architecture_boundaries.exs")

    for context <- ~w(accounts flows localization platform projects scenes sheets workspaces) do
      assert config =~ ~r/zero_debt_consumers:[^\]]*:#{context}/s
      assert config =~ ~r/isolated_contexts:[^\]]*:#{context}/s
    end

    assert config =~ ~r/zero_debt_consumers:[^\]]*:infrastructure/s
    assert config =~ ~r/zero_debt_consumers:[^\]]*:web_infrastructure/s

    for baseline <- Path.wildcard("config/architecture_baselines/*.json") do
      assert %{"edges" => []} = baseline |> File.read!() |> JSON.decode!(),
             "#{baseline} must stay empty: the ENG-92 debt is fully repaid"
    end
  end

  test "reclassified shared modules are consumed only inside the projects boundary" do
    reclassified_modules =
      Enum.map(@reclassified_shared, fn path ->
        path
        |> Path.basename(".ex")
        |> Macro.camelize()
      end)

    violations =
      @foreign_domain_roots
      |> Enum.flat_map(fn root -> Path.wildcard(root <> "*/**/*.ex") ++ Path.wildcard(root <> ".ex") end)
      |> Enum.uniq()
      |> Enum.flat_map(fn path ->
        path
        |> shared_references()
        |> Enum.filter(fn %{segments: segments} ->
          match?([:Storyarn, :Shared, name | _] when is_atom(name), segments) and
            "#{Enum.at(segments, 2)}" in reclassified_modules
        end)
        |> Enum.map(&"#{path}:#{&1.line}: #{Enum.join(&1.segments, ".")}")
      end)
      |> Enum.sort()

    assert violations == [], """
    The shared name normalizer, validations and word count now belong to the
    projects boundary; foreign boundaries own their own copies:

    #{Enum.join(violations, "\n")}
    """
  end

  defp shared_references(path) do
    ast = path |> File.read!() |> Code.string_to_quoted!(file: path, columns: true)

    {_ast, aliases} =
      Macro.prewalk(ast, [], fn
        {:__aliases__, meta, segments} = node, acc ->
          {node, [%{segments: segments, line: meta[:line]} | acc]}

        node, acc ->
          {node, acc}
      end)

    aliases
  end

  defp storyarn_web_references(path) do
    ast = path |> File.read!() |> Code.string_to_quoted!(file: path, columns: true)

    {_ast, aliases} =
      Macro.prewalk(ast, [], fn
        {:__aliases__, meta, segments} = node, acc ->
          {node, [%{segments: segments, line: meta[:line]} | acc]}

        node, acc ->
          {node, acc}
      end)

    aliases
    |> Enum.filter(&match?(%{segments: [:StoryarnWeb | _]}, &1))
    |> Enum.map(&"#{path}:#{&1.line}: #{Enum.join(&1.segments, ".")}")
    |> Enum.uniq()
  end
end
