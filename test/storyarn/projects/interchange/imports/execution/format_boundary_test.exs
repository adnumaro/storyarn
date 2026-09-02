defmodule Storyarn.Projects.Imports.FormatBoundaryTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.Imports.Error
  alias Storyarn.Projects.Imports.FormatRegistry
  alias Storyarn.Projects.Imports.FormatReview
  alias Storyarn.Projects.Imports.ImportFormatId
  alias Storyarn.Projects.Imports.ImportPlan
  alias Storyarn.Projects.Imports.ParserRegistry
  alias Storyarn.Projects.Imports.Parsers.Yarn
  alias Storyarn.Projects.Imports.Parsers.Yarn.FormatAdapter, as: YarnFormatAdapter
  alias Storyarn.Projects.Imports.Preview
  alias Storyarn.Projects.Imports.Telemetry

  @protected_source_roots [
    "lib/storyarn/projects/interchange/imports/adapters/input",
    "lib/storyarn/projects/interchange/imports/adapters/storage",
    "lib/storyarn/projects/interchange/imports/adapters/telemetry",
    "lib/storyarn/projects/interchange/imports/commands",
    "lib/storyarn/projects/interchange/imports/contracts",
    "lib/storyarn/projects/interchange/imports/entities",
    "lib/storyarn/projects/interchange/imports/execution",
    "lib/storyarn/projects/interchange/imports/queries",
    "lib/storyarn/projects/interchange/imports/rules",
    "lib/storyarn/projects/reconstitution"
  ]
  @protected_source_files [
    "lib/storyarn/projects/interchange/imports/adapters/parsers/parser_registry.ex"
  ]

  @yarn_permanent_error_codes MapSet.new(~w(
    archive_missing_yarn_files
    duplicate_yarn_node_title
    empty_yarn_project
    invalid_yarn_command
    missing_yarn_body_end
    missing_yarn_body_start
    missing_yarn_endif
    unsupported_yarn_character_markup
    yarn_document_limit_exceeded
    yarn_node_description_too_long
    yarn_node_title_too_long
    yarn_statement_limit_exceeded
  ))

  test "unknown plan formats fail closed across the shared review lifecycle" do
    plan = %ImportPlan{format: :unknown_test_format, parser_version: "test", data: %{}}

    assert FormatReview.ensure_resolved(plan) == {:error, :unsupported_import_format}

    assert FormatReview.put_allowed_actions(plan, %{}) ==
             {:error, :unsupported_import_format}

    assert FormatReview.save_draft(plan, %{}) == {:error, :unsupported_import_format}
    assert FormatReview.apply(plan, true, %{}) == {:error, :unsupported_import_format}

    assert FormatReview.confirmation_fingerprint(plan) ==
             {:error, :unsupported_import_format}

    assert FormatReview.confirm(plan, "untrusted-fingerprint") ==
             {:error, :unsupported_import_format}

    assert Preview.preview(-1, plan) == {:error, :unsupported_import_format}
  end

  test "known formats with unsupported parser versions fail before preview, review, or queue policy" do
    plan = %ImportPlan{
      format: :yarn,
      parser_version: "unsupported-test-version",
      source_kind: :file,
      data: %{}
    }

    assert FormatReview.ensure_supported(plan) == {:error, :unsupported_import_format}
    assert FormatReview.ensure_resolved(plan) == {:error, :unsupported_import_format}
    assert FormatReview.put_allowed_actions(plan, %{}) == {:error, :unsupported_import_format}
    assert FormatReview.save_draft(plan, []) == {:error, :unsupported_import_format}
    assert FormatReview.apply(plan, true, []) == {:error, :unsupported_import_format}

    assert FormatReview.confirmation_fingerprint(plan) ==
             {:error, :unsupported_import_format}

    assert FormatReview.confirm(plan, "untrusted-fingerprint") ==
             {:error, :unsupported_import_format}

    assert Preview.preview(-1, plan) == {:error, :unsupported_import_format}
  end

  test "known formats with unsupported source kinds fail closed" do
    plan = %ImportPlan{
      format: :yarn,
      parser_version: Yarn.parser_version(),
      source_kind: :future_container,
      data: %{}
    }

    assert FormatReview.ensure_supported(plan) == {:error, :unsupported_import_format}
    assert FormatReview.ensure_resolved(plan) == {:error, :unsupported_import_format}
  end

  test "the format registry exposes only the deliberately registered adapters" do
    assert FormatRegistry.persisted_formats() == ["yarn"]
    assert FormatRegistry.fetch(:yarn) == {:ok, YarnFormatAdapter}
    assert FormatRegistry.fetch(:unknown_test_format) == {:error, :unsupported_import_format}
    assert FormatRegistry.fetch("yarn") == {:error, :unsupported_import_format}

    refute function_exported?(FormatRegistry, :register, 2)
    refute function_exported?(FormatRegistry, :put, 2)
  end

  test "every parser registration agrees with its durable and execution identities" do
    registrations = FormatRegistry.registrations()
    assert registrations != []

    for %{format: format, parser: parser, adapter: adapter, sources: sources} <- registrations do
      persisted_format = Atom.to_string(format)

      assert parser.format() == format
      assert FormatRegistry.fetch(format) == {:ok, adapter}
      assert ImportFormatId.valid?(persisted_format)
      assert adapter.supports_parser_version?(parser.parser_version())
      assert FormatRegistry.encode_persisted(format) == {:ok, persisted_format}
      assert FormatRegistry.decode_persisted(persisted_format) == {:ok, format}

      for {extension, source_kind} <- sources do
        assert {:ok, source} = FormatRegistry.source_for("source#{extension}")
        assert source == %{format: format, parser: parser, source_kind: source_kind}

        matching_plan = %ImportPlan{
          format: format,
          parser_version: parser.parser_version(),
          source_kind: source_kind,
          data: %{}
        }

        assert FormatRegistry.validate_parsed_plan(source, matching_plan) == :ok

        assert FormatRegistry.validate_parsed_plan(source, %{matching_plan | format: :wrong}) ==
                 {:error, :unsupported_import_format}

        assert FormatRegistry.validate_parsed_plan(source, %{
                 matching_plan
                 | parser_version: "wrong"
               }) == {:error, :unsupported_import_format}

        other_source_kind = if source_kind == :file, do: :archive, else: :file

        assert FormatRegistry.validate_parsed_plan(source, %{
                 matching_plan
                 | source_kind: other_source_kind
               }) == {:error, :unsupported_import_format}
      end
    end
  end

  test "durable format ids are opaque while support remains closed by the registry" do
    assert ImportFormatId.valid?("future_format")
    refute ImportFormatId.valid?("FutureFormat")
    refute ImportFormatId.valid?(String.duplicate("a", 31))

    assert FormatRegistry.decode_persisted("future_format") ==
             {:error, :unsupported_import_format}
  end

  test "the registered format adapter owns source-specific replacement and error policy" do
    assert YarnFormatAdapter.replacement_snapshot_attrs() == %{
             title: "Before Yarn project replacement",
             description: "Recovery point created before replacing narrative project content."
           }

    assert YarnFormatAdapter.permanent_error_codes() == @yarn_permanent_error_codes

    for code <- @yarn_permanent_error_codes do
      assert FormatRegistry.permanent_error_code?(:yarn, code)
      assert FormatRegistry.permanent_error_code?("yarn", code)
    end

    assert {"archive_missing_yarn_files", "The import file could not be processed.", true} =
             Error.classify(:archive_missing_yarn_files, :yarn)

    assert {"archive_missing_yarn_files", "The import could not be completed. It may be retried automatically.", false} =
             Error.classify(:archive_missing_yarn_files)

    refute FormatRegistry.permanent_error_code?(:unknown_test_format, "archive_missing_yarn_files")
    refute FormatRegistry.permanent_error_code?(nil, "archive_missing_yarn_files")

    refute FormatRegistry.permanent_error_code?(:yarn, "unknown_format_specific_failure")

    assert {"unknown_format_specific_failure", "The import could not be completed. It may be retried automatically.",
            false} =
             Error.classify(:unknown_format_specific_failure)
  end

  test "review revisions may change data but no durable source identity or envelope metadata" do
    plan = %ImportPlan{
      format: :yarn,
      parser_version: Yarn.parser_version(),
      source_kind: :file,
      attempt_binding: "binding",
      replace_eligible: true,
      issues: [],
      metadata: %{warning_count: 0},
      data: %{"flows" => []}
    }

    assert FormatReview.validate_revision(plan, %{plan | data: %{"flows" => [%{"title" => "Start"}]}}) == :ok

    immutable_changes = [
      format: :other,
      parser_version: "other",
      source_kind: :archive,
      attempt_binding: "other-binding",
      replace_eligible: false,
      issues: [:changed],
      metadata: %{warning_count: 1}
    ]

    for {field, value} <- immutable_changes do
      assert FormatReview.validate_revision(plan, Map.put(plan, field, value)) ==
               {:error, :invalid_import_review}
    end
  end

  test "every accepted parser format resolves through the same closed registry" do
    for filename <- ["story.yarn", "story.YARN", "story.zip", "story.ZIP"] do
      assert ParserRegistry.parser_for(filename) == {:ok, Yarn}
      assert FormatRegistry.parser_for(filename) == {:ok, Yarn}
      assert {:ok, %{format: :yarn, parser: Yarn}} = FormatRegistry.source_for(filename)
      assert FormatRegistry.fetch(Yarn.format()) == {:ok, YarnFormatAdapter}
      assert FormatRegistry.encode_persisted(Yarn.format()) == {:ok, "yarn"}
      assert FormatRegistry.decode_persisted("yarn") == {:ok, Yarn.format()}
    end

    assert ParserRegistry.parser_for("story.ink") ==
             {:error, :unsupported_import_format}

    assert FormatRegistry.source_for("story.ink") ==
             {:error, :unsupported_import_format}

    assert FormatRegistry.encode_persisted(:unknown_test_format) ==
             {:error, :unsupported_import_format}

    assert FormatRegistry.decode_persisted("unknown_test_format") ==
             {:error, :unsupported_import_format}
  end

  test "source telemetry is derived from the registered parser profile" do
    assert Telemetry.source_metadata("story.yarn") == %{
             format: "yarn",
             source_kind: "file",
             parser_version: "unknown"
           }

    assert Telemetry.source_metadata("story.zip") == %{
             format: "yarn",
             source_kind: "archive",
             parser_version: "unknown"
           }

    assert Telemetry.source_metadata("story.ink") == %{
             format: "unknown",
             source_kind: "file",
             parser_version: "unknown"
           }
  end

  test "shared import contracts, records, input, telemetry, commands, rules, execution, queries, and reconstitution remain format agnostic" do
    protected_sources = protected_sources_by_root()

    for {root, sources} <- protected_sources do
      assert sources != [], "format-boundary ratchet matched no Elixir sources under #{root}"
    end

    violations =
      for {_root, sources} <- protected_sources,
          path <- sources,
          source = File.read!(path),
          violation <- format_specific_violations(source),
          do: {path, violation}

    assert violations == [], """
    Shared import contracts, records, input, telemetry, commands, rules,
    execution, queries, and project reconstitution must consume the closed
    format contract.
    Source-specific modules, metadata, and policy belong to the registered
    format adapter:

    #{inspect(violations, pretty: true)}
    """
  end

  defp protected_sources_by_root do
    roots =
      Map.new(@protected_source_roots, fn root ->
        {root, root |> Path.join("**/*.ex") |> Path.wildcard() |> Enum.sort()}
      end)

    Map.put(roots, :explicit_files, @protected_source_files)
  end

  defp format_specific_violations(source) do
    []
    |> maybe_add_violation(
      Regex.match?(~r/Storyarn\.Projects\.Imports\.Parsers\.Yarn(?:\.|\b)/, source),
      :yarn_module_dependency
    )
    |> maybe_add_violation(String.contains?(source, "import_yarn_"), :yarn_metadata_interpretation)
    |> maybe_add_violation(
      Regex.match?(~r/(?<![A-Za-z0-9_])(?::yarn|"yarn")(?![A-Za-z0-9_])/, source),
      :yarn_identity_literal
    )
    |> maybe_add_violation(
      Regex.match?(~r/(?:\bYarn\b|\byarn_|\.yarn\b)/, source),
      :yarn_policy_leakage
    )
    |> Enum.reverse()
  end

  defp maybe_add_violation(violations, true, violation), do: [violation | violations]
  defp maybe_add_violation(violations, false, _violation), do: violations
end
