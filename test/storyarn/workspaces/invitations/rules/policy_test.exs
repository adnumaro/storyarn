defmodule Storyarn.Workspaces.Invitations.Rules.PolicyTest do
  use ExUnit.Case, async: true

  alias Storyarn.Workspaces.Invitations.Rules.Policy

  test "workspace invitations are valid for seven days" do
    assert Policy.validity_in_days() == 7
  end
end
