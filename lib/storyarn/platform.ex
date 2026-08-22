defmodule Storyarn.Platform do
  @moduledoc """
  Public facade for platform-wide capabilities and reaction policy.

  Product contexts own the business facts they emit. Platform decides which
  cross-cutting reactions those facts trigger. The current reaction is
  best-effort product analytics; durable notifications and email delivery must
  enter through persisted, idempotent workflows rather than this synchronous
  path.
  """

  alias Storyarn.Notifications
  alias Storyarn.Platform.Entitlements
  alias Storyarn.Platform.EventTracker
  alias Storyarn.Platform.ProductMetrics.Taxonomy

  @doc "Routes a context-owned event through Platform reaction policy."
  @spec react_to_event(term(), atom(), atom(), map()) :: :ok
  defdelegate react_to_event(scope_or_user, source, event_type, payload),
    to: EventTracker,
    as: :react

  @doc "Returns the current scalar entitlement for one workspace resource."
  @spec entitlement_limit(pos_integer(), atom()) :: non_neg_integer() | nil
  defdelegate entitlement_limit(workspace_id, resource), to: Entitlements, as: :limit

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

  @doc "Persists a context-owned content activity through Platform notification policy."
  @spec deliver_content_activity(term(), pos_integer(), atom(), String.t(), map()) ::
          {:ok, term()} | {:error, term()}
  defdelegate deliver_content_activity(scope, project_id, action, entity_type, entity),
    to: Notifications,
    as: :deliver_content_activity_by_project_id

  @doc "Publishes the committed notification outcome to connected recipients."
  @spec publish_notification_delivery(term()) :: :ok
  defdelegate publish_notification_delivery(outcome), to: Notifications, as: :publish_committed
end
