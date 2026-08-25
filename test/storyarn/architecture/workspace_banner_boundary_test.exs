defmodule Storyarn.Architecture.WorkspaceBannerBoundaryTest do
  use ExUnit.Case, async: true

  @workspace_banner_domain_sources [
    "lib/storyarn/workspaces/banner_cleanup_queue.ex",
    "lib/storyarn/workspaces/banner_cleanup_queue/oban.ex",
    "lib/storyarn/workspaces/banner_storage.ex",
    "lib/storyarn/workspaces/workspace_banner.ex",
    "lib/storyarn/workers/workspaces/delete_workspace_banner_worker.ex"
  ]

  test "the Workspace banner use case has no Projects domain dependency" do
    violations =
      Enum.filter(@workspace_banner_domain_sources, fn path ->
        File.read!(path) =~ "Storyarn.Projects"
      end)

    assert violations == []
    refute File.read!("lib/storyarn/workspaces/workspace_banner.ex") =~ "project_asset_upload_limits"
  end

  test "Workspace settings invoke the Workspaces facade and need no Projects contract" do
    source = File.read!("lib/storyarn_web/live/settings_live/workspace_general.ex")
    policy = File.read!("config/architecture_boundaries.exs")

    assert source =~ "Workspaces.upload_workspace_banner"
    assert source =~ "Workspaces.remove_workspace_banner"
    refute source =~ "Storyarn.Projects"
    refute source =~ "Projects."
    refute policy =~ "Workspace banner uploads use Project-owned media"
  end

  test "the Projects facade does not expose Workspace-banner upload plumbing" do
    facade = File.read!("lib/storyarn/projects.ex")

    refute facade =~ "workspace_banner"
    refute facade =~ "asset_upload_profile"
    refute facade =~ "validate_asset_base64_size"
    refute facade =~ "asset_content_type_from_binary"
    refute facade =~ "project_storage_upload"
  end
end
