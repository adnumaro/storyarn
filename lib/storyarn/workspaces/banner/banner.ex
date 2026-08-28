defmodule Storyarn.Workspaces.Banner do
  @moduledoc """
  Workspace-owned lifecycle for private banner images.

  The capability coordinates authorization, validation, persistence, storage
  compensation, and durable cleanup behind this public boundary.
  """

  alias Storyarn.Workspaces.Banner.Commands.Cleanup
  alias Storyarn.Workspaces.Banner.Commands.Remove
  alias Storyarn.Workspaces.Banner.Commands.Upload
  alias Storyarn.Workspaces.Banner.Queries.Get
  alias Storyarn.Workspaces.Workspace

  @type scope :: %{user: %{id: integer()}}
  @type upload_attrs :: %{
          required(:filename) => String.t(),
          required(:content_type) => String.t(),
          required(:data) => String.t()
        }
  @type banner_error ::
          :not_found
          | :unauthorized
          | :invalid_banner_upload
          | {:workspace_banner_cleanup_enqueue_failed, term()}
          | {:workspace_banner_cleanup_deferred, term(), term()}
          | {:workspace_banner_storage_failed, term()}
          | {:workspace_banner_update_failed, term()}
          | {:workspace_banner_update_failed_with_cleanup_required, term(), String.t(), term()}

  @spec upload(scope(), pos_integer(), upload_attrs(), keyword()) ::
          {:ok, Workspace.t()} | {:error, banner_error()}
  defdelegate upload(scope, workspace_id, attrs, opts \\ []), to: Upload, as: :execute

  @spec remove(scope(), pos_integer(), keyword()) ::
          {:ok, Workspace.t()} | {:error, banner_error()}
  defdelegate remove(scope, workspace_id, opts \\ []), to: Remove, as: :execute

  @spec get(scope(), String.t(), keyword()) ::
          {:ok, %{key: String.t(), content_type: String.t()}} | {:error, :not_found}
  defdelegate get(scope, workspace_slug, opts \\ []), to: Get, as: :execute

  @doc false
  @spec prepare_hard_delete(map(), keyword()) :: :ok | {:error, term()}
  defdelegate prepare_hard_delete(workspace_or_snapshot, opts \\ []), to: Cleanup

  @doc false
  @spec perform_cleanup(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  defdelegate perform_cleanup(workspace_slug, storage_key, opts \\ []), to: Cleanup
end
