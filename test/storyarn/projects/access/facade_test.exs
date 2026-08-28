defmodule Storyarn.Projects.AccessFacadeTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.Access

  test "exposes effective project roles through the access boundary" do
    assert Access.effective_role(nil, "admin") == "editor"
    assert Access.effective_role("viewer", "owner") == "viewer"
    assert Access.effective_role(nil, nil) == nil
  end

  test "exposes project permissions through the access boundary" do
    assert Access.can?("owner", :manage_members)
    assert Access.can?("editor", :edit_content)
    refute Access.can?("viewer", :edit_content)
  end
end
