defmodule Storyarn.Projects.Imports.Parsers.Yarn.FormatAdapter do
  @moduledoc false

  @behaviour Storyarn.Projects.Imports.FormatAdapter

  alias Storyarn.Projects.Imports.Parsers.Yarn.Materialization
  alias Storyarn.Projects.Imports.Parsers.Yarn.ReviewDecisions

  # Durable plans from another parser version must be assessed explicitly
  # before adding that version here. The registry verifies at compile time that
  # the current parser version is included in this deliberately supported set.
  @supported_parser_versions MapSet.new(["6"])

  @permanent_error_codes MapSet.new(~w(
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

  @impl true
  def supports_parser_version?(version) when is_binary(version), do: MapSet.member?(@supported_parser_versions, version)

  def supports_parser_version?(_version), do: false

  @impl true
  defdelegate put_allowed_review_actions(review), to: ReviewDecisions, as: :put_allowed_actions

  @impl true
  defdelegate review_resolved?(plan), to: ReviewDecisions, as: :resolved?

  @impl true
  defdelegate save_review_draft(plan, decisions), to: ReviewDecisions, as: :save_draft

  @impl true
  defdelegate apply_review(plan, acknowledged?, decisions), to: ReviewDecisions, as: :apply

  @impl true
  defdelegate confirmation_fingerprint(plan), to: ReviewDecisions

  @impl true
  defdelegate confirm_review(plan, fingerprint), to: ReviewDecisions, as: :confirm

  @impl true
  def permanent_error_codes, do: @permanent_error_codes

  @impl true
  def replacement_snapshot_attrs do
    %{
      title: "Before Yarn project replacement",
      description: "Recovery point created before replacing narrative project content."
    }
  end

  @impl true
  defdelegate rewrite_node_data(data, type, renames), to: Materialization

  @impl true
  defdelegate finalize_flow(flow_data, renames), to: Materialization

  @impl true
  defdelegate clean_node_data(data), to: Materialization
end
