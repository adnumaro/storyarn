defmodule Storyarn.Workspaces.BannerCleanupQueue.Oban do
  @moduledoc false

  @behaviour Storyarn.Workspaces.BannerCleanupQueue

  alias Storyarn.Workers.DeleteWorkspaceBannerWorker

  @impl true
  def enqueue(workspace_slug, storage_key) do
    %{"workspace_slug" => workspace_slug, "storage_key" => storage_key}
    |> DeleteWorkspaceBannerWorker.new()
    |> Oban.insert()
  end
end
