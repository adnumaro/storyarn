defmodule Storyarn.Flows.Versioning.Adapters.Projects.AssetRegistration do
  @moduledoc """
  Narrow Flow adapter for Projects-owned asset-row registration.

  Flow keeps snapshot storage, quota and compensation orchestration. Projects
  remains the sole writer of the shared asset record.
  """

  alias Storyarn.Projects

  @spec register_materialized_asset(pos_integer(), pos_integer() | nil, map()) ::
          {:ok, %{asset_id: pos_integer(), project_id: pos_integer()}} | {:error, term()}
  def register_materialized_asset(project_id, uploaded_by_id, attrs) do
    Projects.register_materialized_asset(project_id, uploaded_by_id, attrs)
  end
end
