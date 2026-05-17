defmodule Storyarn.Analytics.PostHogAdapterTest do
  use ExUnit.Case, async: false

  alias Storyarn.Analytics.PostHogAdapter

  test "capture delegates to the official PostHog SDK payload contract" do
    assert :ok =
             PostHogAdapter.capture(%{
               event: "project created",
               distinct_id: "user:42",
               properties: %{"project_id" => 7, "workspace_id" => 3}
             })

    assert Enum.any?(PostHog.Test.all_captured(), fn event ->
             match?(
               %{
                 event: "project created",
                 distinct_id: "user:42",
                 properties: %{"project_id" => 7, "workspace_id" => 3}
               },
               event
             )
           end)
  end

  test "identify uses PostHog's $identify event shape" do
    assert :ok =
             PostHogAdapter.identify(%{
               distinct_id: "user:42",
               properties: %{"locale" => "es", "is_super_admin" => false}
             })

    assert Enum.any?(PostHog.Test.all_captured(), fn event ->
             match?(
               %{
                 event: "$identify",
                 distinct_id: "user:42",
                 properties: %{"$set" => %{"locale" => "es", "is_super_admin" => false}}
               },
               event
             )
           end)
  end
end
