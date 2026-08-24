defmodule StoryarnWeb.Live.Shared.DashboardHelpersTest do
  use ExUnit.Case, async: true

  alias Phoenix.LiveView.Socket
  alias Storyarn.Platform.Shared.Severity
  alias StoryarnWeb.Live.Shared.DashboardHelpers

  @issue_opts [
    all_key: :all_issues,
    page_key: :issues,
    filters_key: :filters,
    options_key: :filter_options,
    page_assign: :issue_page,
    total_pages_assign: :issue_total_pages,
    total_assign: :issue_total,
    unfiltered_total_assign: :unfiltered_issue_total
  ]

  test "pagination clamps the reported page as well as the returned rows" do
    page = DashboardHelpers.pagination(Enum.to_list(1..30), 999)

    assert page.page == 2
    assert page.total_pages == 2
    assert page.total == 30
    assert page.rows == Enum.to_list(26..30)
  end

  test "table sorting uses id as a total-order tiebreak across paginated refreshes" do
    rows = for id <- 1..30, do: %{id: id, name: "Same", issue_count: 1}
    columns = %{"issue_count" => & &1.issue_count}

    for {direction, expected_ids} <- [
          {:asc, Enum.to_list(1..30)},
          {:desc, Enum.to_list(30..1//-1)}
        ] do
      first_load = DashboardHelpers.sort_table(rows, "issue_count", direction, columns)
      refreshed = DashboardHelpers.sort_table(Enum.reverse(rows), "issue_count", direction, columns)

      assert Enum.map(first_load, & &1.id) == expected_ids
      assert Enum.map(refreshed, & &1.id) == expected_ids

      assert DashboardHelpers.pagination(first_load, 1).rows ==
               DashboardHelpers.pagination(refreshed, 1).rows

      assert DashboardHelpers.pagination(first_load, 2).rows ==
               DashboardHelpers.pagination(refreshed, 2).rows
    end
  end

  test "overview loading distinguishes initial loads from background refreshes" do
    assert DashboardHelpers.begin_overview_load(:loading) == :loading
    assert DashboardHelpers.begin_overview_load(:error) == :loading
    assert DashboardHelpers.begin_overview_load(:ready) == :refreshing
    assert DashboardHelpers.begin_overview_load(:refreshing) == :refreshing
    assert DashboardHelpers.begin_overview_load(:stale) == :refreshing
  end

  test "overview failure preserves refreshed content but exposes an initial error" do
    assert DashboardHelpers.fail_overview_load(:loading) == :error
    assert DashboardHelpers.fail_overview_load(:error) == :error
    assert DashboardHelpers.fail_overview_load(:refreshing) == :stale
  end

  test "default severity filters follow the canonical severity catalog" do
    expected = Enum.map(Severity.catalog(), &Atom.to_string/1)

    assert Enum.map(
             DashboardHelpers.default_issue_filter_options().severities,
             & &1.value
           ) == expected
  end

  test "issue filters are combined before using the same 25-row paginator" do
    issues =
      for id <- 1..30 do
        %{
          id: "issue-#{id}",
          severity: if(rem(id, 2) == 0, do: "warning", else: "error"),
          code: if(id <= 28, do: "shared_code", else: "other_code"),
          resource_id: if(id <= 26, do: 10, else: 20),
          resource_label: if(id <= 26, do: "Alpha", else: "Beta")
        }
      end

    socket = DashboardHelpers.put_issues(socket_fixture(), issues, @issue_opts)

    assert socket.assigns.issue_total == 30
    assert socket.assigns.issue_total_pages == 2
    assert length(socket.assigns.issues) == 25

    assert socket.assigns.filter_options == %{
             totals: %{severity: 30, code: 30, resource: 30},
             severities: [
               %{value: "error", count: 15},
               %{value: "warning", count: 15},
               %{value: "info", count: 0}
             ],
             codes: [
               %{value: "other_code", count: 2},
               %{value: "shared_code", count: 28}
             ],
             resources: [
               %{value: "10", label: "Alpha", count: 26},
               %{value: "20", label: "Beta", count: 4}
             ]
           }

    socket =
      DashboardHelpers.handle_issue_filter(
        socket,
        "severity",
        "warning",
        @issue_opts
      )

    assert socket.assigns.issue_page == 1
    assert socket.assigns.issue_total == 15
    assert Enum.all?(socket.assigns.issues, &(&1.severity == "warning"))

    assert socket.assigns.filter_options.totals == %{severity: 30, code: 15, resource: 15}

    assert socket.assigns.filter_options.severities == [
             %{value: "error", count: 15},
             %{value: "warning", count: 15},
             %{value: "info", count: 0}
           ]

    assert socket.assigns.filter_options.codes == [
             %{value: "other_code", count: 1},
             %{value: "shared_code", count: 14}
           ]

    assert socket.assigns.filter_options.resources == [
             %{value: "10", label: "Alpha", count: 13},
             %{value: "20", label: "Beta", count: 2}
           ]

    socket =
      DashboardHelpers.handle_issue_filter(
        socket,
        "resource",
        "10",
        @issue_opts
      )

    assert socket.assigns.issue_total == 13
    assert Enum.all?(socket.assigns.issues, &(&1.resource_id == 10))
    assert socket.assigns.unfiltered_issue_total == 30

    assert socket.assigns.filter_options.totals == %{severity: 26, code: 13, resource: 15}

    assert socket.assigns.filter_options.severities == [
             %{value: "error", count: 13},
             %{value: "warning", count: 13},
             %{value: "info", count: 0}
           ]

    assert socket.assigns.filter_options.codes == [
             %{value: "other_code", count: 0},
             %{value: "shared_code", count: 13}
           ]

    assert socket.assigns.filter_options.resources == [
             %{value: "10", label: "Alpha", count: 13},
             %{value: "20", label: "Beta", count: 2}
           ]
  end

  test "a known severity stays selected when it currently has no matches" do
    issues = [
      %{
        id: "issue-1",
        severity: "warning",
        code: "warning_code",
        resource_id: 10,
        resource_label: "Alpha"
      }
    ]

    socket =
      socket_fixture()
      |> DashboardHelpers.put_issues(issues, @issue_opts)
      |> DashboardHelpers.handle_issue_filter("severity", "error", @issue_opts)

    assert socket.assigns.filters["severity"] == "error"
    assert socket.assigns.issue_total == 0
    assert socket.assigns.issues == []
  end

  test "selected code and resource stay active with zero results when they disappear on refresh" do
    original = %{
      id: "issue-1",
      severity: "warning",
      code: "resolved_code",
      resource_id: 10,
      resource_label: "Resolved resource"
    }

    remaining = %{
      id: "issue-2",
      severity: "info",
      code: "other_code",
      resource_id: 20,
      resource_label: "Other resource"
    }

    socket =
      socket_fixture()
      |> DashboardHelpers.put_issues([original], @issue_opts)
      |> DashboardHelpers.handle_issue_filter("code", "resolved_code", @issue_opts)
      |> DashboardHelpers.handle_issue_filter("resource", "10", @issue_opts)
      |> DashboardHelpers.put_issues([remaining], @issue_opts)

    assert socket.assigns.filters == %{
             "severity" => "all",
             "code" => "resolved_code",
             "resource" => "10"
           }

    assert socket.assigns.issue_total == 0
    assert socket.assigns.issues == []

    assert %{value: "resolved_code", count: 0} =
             Enum.find(socket.assigns.filter_options.codes, &(&1.value == "resolved_code"))

    assert %{value: "10", label: "Resolved resource", count: 0} =
             Enum.find(socket.assigns.filter_options.resources, &(&1.value == "10"))
  end

  test "unknown filter keys and values cannot become active filters" do
    issue = %{
      id: "issue-1",
      severity: "warning",
      code: "known_code",
      resource_id: 10,
      resource_label: "Known resource"
    }

    socket = DashboardHelpers.put_issues(socket_fixture(), [issue], @issue_opts)

    for {filter, value} <- [
          {"code", "unknown_code"},
          {"resource", "999"},
          {"severity", "critical"},
          {"unknown", "known_code"}
        ] do
      unchanged =
        DashboardHelpers.handle_issue_filter(
          socket,
          filter,
          value,
          @issue_opts
        )

      assert unchanged.assigns.filters == DashboardHelpers.default_issue_filters()
      assert unchanged.assigns.issue_total == 1
      assert unchanged.assigns.issues == [issue]
    end
  end

  test "resource options deduplicate an id and tolerate a missing label" do
    issues = [
      %{id: "issue-1", severity: "warning", code: "one", resource_id: 10, resource_label: nil},
      %{id: "issue-2", severity: "error", code: "two", resource_id: 10, resource_label: "Later"}
    ]

    socket = DashboardHelpers.put_issues(socket_fixture(), issues, @issue_opts)

    assert socket.assigns.filter_options.resources == [
             %{value: "10", label: "#10", count: 2}
           ]
  end

  test "stable issue ids remain unique when the semantic identity collides" do
    issues = [
      %{code: "stale_reference", location: 10, details: %{path: "action"}},
      %{code: "stale_reference", location: 10, details: %{path: "action"}},
      %{code: "stale_reference", location: 10, details: %{path: "condition"}}
    ]

    identified =
      DashboardHelpers.put_stable_issue_ids(issues, "scene", fn issue ->
        {issue.code, issue.location, issue.details}
      end)

    ids = Enum.map(identified, & &1.id)

    assert length(ids) == length(Enum.uniq(ids))
    assert Enum.at(ids, 0) != Enum.at(ids, 1)

    assert identified ==
             DashboardHelpers.put_stable_issue_ids(issues, "scene", fn issue ->
               {issue.code, issue.location, issue.details}
             end)

    survivor = Enum.at(issues, 2)
    identified_survivor = Enum.at(identified, 2)

    assert [remaining] =
             DashboardHelpers.put_stable_issue_ids([survivor], "scene", fn issue ->
               {issue.code, issue.location, issue.details}
             end)

    assert remaining.id == identified_survivor.id
  end

  defp socket_fixture do
    %Socket{
      assigns: %{
        __changed__: %{},
        all_issues: [],
        issues: [],
        filters: DashboardHelpers.default_issue_filters(),
        filter_options: DashboardHelpers.default_issue_filter_options(),
        issue_page: 1,
        issue_total_pages: 1,
        issue_total: 0,
        unfiltered_issue_total: 0
      }
    }
  end
end
