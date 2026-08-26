defmodule Storyarn.Platform.Reactions do
  @moduledoc """
  Public boundary for Platform-owned event reactions and product taxonomy.

  Product contexts own the facts they emit. Platform owns the best-effort
  reaction policy and the stable, privacy-safe product dimensions derived from
  those facts.
  """

  alias Storyarn.Platform.Analytics
  alias Storyarn.Platform.EventTracker
  alias Storyarn.Platform.ProductMetrics.Taxonomy

  @doc "Routes a context-owned event through Platform reaction policy."
  @spec react_to_event(term(), atom(), atom(), map()) :: :ok
  defdelegate react_to_event(scope_or_user, source, event_type, payload),
    to: EventTracker,
    as: :react

  @doc "Tracks one allowlisted, privacy-safe presentation analytics event."
  @spec track_analytics(term(), String.t(), map()) :: :ok
  defdelegate track_analytics(scope_or_user, event_name, properties \\ %{}),
    to: Analytics,
    as: :track

  @doc "Returns frontend-safe analytics configuration for the presentation adapter."
  @spec analytics_frontend_config(term()) :: map() | nil
  defdelegate analytics_frontend_config(scope_or_user),
    to: Analytics,
    as: :frontend_config

  @doc "Returns the stable project categories collected for product metrics."
  @spec product_metric_project_types() :: [String.t()]
  defdelegate product_metric_project_types(), to: Taxonomy, as: :project_types

  @doc "Returns the stable project subtype taxonomy collected for product metrics."
  @spec product_metric_project_subtypes() :: %{String.t() => [String.t()]}
  defdelegate product_metric_project_subtypes(), to: Taxonomy, as: :project_subtypes

  @doc "Returns the product metric subtypes available for one project category."
  @spec product_metric_project_subtypes(String.t()) :: [String.t()]
  defdelegate product_metric_project_subtypes(project_type),
    to: Taxonomy,
    as: :project_subtypes

  @doc "Returns the complete project classification options for presentation adapters."
  @spec product_metric_project_options() :: %{
          project_types: [String.t()],
          project_subtypes: %{String.t() => [String.t()]}
        }
  defdelegate product_metric_project_options(), to: Taxonomy, as: :project_options

  @doc "Checks whether a project category belongs to the product metric taxonomy."
  @spec known_product_metric_project_type?(term()) :: boolean()
  defdelegate known_product_metric_project_type?(project_type),
    to: Taxonomy,
    as: :known_project_type?

  @doc "Checks whether a project subtype belongs to its product metric category."
  @spec known_product_metric_project_subtype?(term(), term()) :: boolean()
  defdelegate known_product_metric_project_subtype?(project_type, project_subtype),
    to: Taxonomy,
    as: :known_project_subtype?
end
