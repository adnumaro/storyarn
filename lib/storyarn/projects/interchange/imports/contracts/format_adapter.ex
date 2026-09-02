defmodule Storyarn.Projects.Imports.FormatAdapter do
  @moduledoc """
  Closed contract between the parser-independent import lifecycle and one
  source format.

  Parsers may retain source-specific metadata in a versioned `ImportPlan`, but
  the shared preview and writer never interpret that metadata themselves. The
  registered adapter owns review semantics and the last source-aware rewrite
  immediately before persistence.
  """

  alias Storyarn.Projects.Imports.ImportPlan

  @doc """
  Returns whether this release can safely execute a durable plan produced by
  the given parser version.

  Adapters must list deliberately supported historical versions instead of
  assuming that every stored plan is compatible with the current parser.
  """
  @callback supports_parser_version?(String.t()) :: boolean()

  @callback put_allowed_review_actions(map()) :: map()
  @callback review_resolved?(ImportPlan.t()) :: boolean()
  @callback save_review_draft(ImportPlan.t(), term()) :: {:ok, ImportPlan.t()} | {:error, term()}
  @callback apply_review(ImportPlan.t(), boolean(), term()) :: {:ok, ImportPlan.t()} | {:error, term()}
  @callback confirmation_fingerprint(ImportPlan.t()) :: {:ok, String.t()} | {:error, term()}
  @callback confirm_review(ImportPlan.t(), term()) :: :ok | {:error, term()}

  @callback permanent_error_codes() :: MapSet.t(String.t())
  @callback replacement_snapshot_attrs() :: %{
              required(:title) => String.t(),
              required(:description) => String.t()
            }

  @callback rewrite_node_data(map(), String.t(), %{optional(String.t()) => String.t()}) :: map()
  @callback finalize_flow(map(), %{optional(String.t()) => String.t()}) :: map()
  @callback clean_node_data(map()) :: map()
end
