defmodule Storyarn.Workspaces.Banner.Adapters.Cleanup.Oban do
  @moduledoc false

  @behaviour Storyarn.Workspaces.Banner.Adapters.Cleanup.Queue

  alias Storyarn.Workers.DeleteWorkspaceBannerWorker

  @impl true
  def enqueue(workspace_slug, storage_key) do
    %{"workspace_slug" => workspace_slug, "storage_key" => storage_key}
    |> DeleteWorkspaceBannerWorker.new()
    |> Oban.insert()
  end
end
