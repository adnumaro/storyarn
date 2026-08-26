defmodule Storyarn.Architecture.ContextOwnedEmailContentTest do
  use ExUnit.Case, async: true

  @context_roots ~w(accounts projects workspaces)
  @retired_module "Storyarn.Platform.Emails.Templates"

  test "account, project, and workspace email content is consumer-owned" do
    for context <- @context_roots,
        path <- Path.wildcard("lib/storyarn/#{context}/**/*.ex") do
      refute File.read!(path) =~ @retired_module,
             "#{path} must own its email intent instead of importing #{@retired_module}"
    end

    refute File.exists?("lib/storyarn/platform/adapters/email/templates.ex")
  end

  test "Platform email code contains only technical layout concerns" do
    platform_email_source =
      "lib/storyarn/platform/adapters/email/**/*.ex"
      |> Path.wildcard()
      |> Enum.map_join("\n", &File.read!/1)

    refute platform_email_source =~ "You've been invited"
    refute platform_email_source =~ "Reset your Storyarn password"
    refute platform_email_source =~ "Update your email address"
  end
end
