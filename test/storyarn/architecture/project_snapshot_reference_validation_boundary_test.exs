defmodule Storyarn.Architecture.ProjectSnapshotReferenceValidationBoundaryTest do
  use ExUnit.Case, async: true

  @root "lib/storyarn/projects/versioning/rules/snapshot_references"
  @sources [
    "#{@root}/snapshot_references.ex",
    "#{@root}/sheet_scanner.ex",
    "#{@root}/flow_scanner.ex",
    "#{@root}/scene_scanner.ex"
  ]
  @reference_extraction "lib/storyarn/projects/references/rules/entity_reference_extraction.ex"
  @rich_text_mentions "lib/storyarn/projects/references/rules/rich_text_mentions.ex"

  test "portable snapshot reference validation remains a complete pure slice" do
    discovered_sources = "#{@root}/*.ex" |> Path.wildcard() |> Enum.sort()

    assert discovered_sources == Enum.sort(@sources)

    Enum.each(discovered_sources ++ [@reference_extraction, @rich_text_mentions], fn path ->
      source = File.read!(path)

      refute source =~ "Storyarn.Repo"
      refute source =~ "Ecto.Query"
      refute source =~ "Repo."
      refute source =~ "Oban."
      refute source =~ "Req."
      refute source =~ "Storyarn.Platform.ObjectStorage"
      refute source =~ "Storyarn.Projects.Assets"
      refute source =~ "Storyarn.Projects.Versioning.Builders"
      refute source =~ "Storyarn.Projects.References.Commands"
      refute source =~ "Storyarn.Projects.References.EntityReferenceProjection"
      refute source =~ "Storyarn.Projects.References.ProjectReferenceIntegrity"
      refute source =~ "Repo.transaction"
      refute source =~ "FOR UPDATE"
      refute source =~ "FOR SHARE"
      refute source =~ "pg_advisory"
    end)
  end

  test "ProjectRecovery has the only production entry and builders retain no scanner wrappers" do
    recovery = File.read!("lib/storyarn/projects/versioning/execution/project_recovery.ex")

    assert length(Regex.scan(~r/SnapshotReferences\.validate\(/, recovery)) == 1
    refute recovery =~ "SheetScanner"
    refute recovery =~ "FlowScanner"
    refute recovery =~ "SceneScanner"

    for builder <- ~w(sheet_builder flow_builder scene_builder) do
      source = File.read!("lib/storyarn/projects/versioning/execution/builders/#{builder}.ex")
      refute source =~ "def scan_references"
    end

    projection =
      File.read!("lib/storyarn/projects/references/commands/entity_reference_projection.ex")

    refute projection =~ "def extract_block_value_references"
  end
end
