defmodule StoryarnWeb.Live.Shared.DashboardHelpers do
  @moduledoc """
  Shared backend helpers for Vue-backed project dashboards.

  This module intentionally contains no HEEx components. It only keeps the
  table sorting and pagination used by dashboard LiveViews.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Storyarn.Shared.Severity

  @default_per_page 25
  @max_bigint 9_223_372_036_854_775_807
  @issue_filter_keys ~w(severity code resource)
  @default_issue_filters %{
    "severity" => "all",
    "code" => "all",
    "resource" => "all"
  }
  @issue_severity_values Enum.map(Severity.catalog(), &Atom.to_string/1)
  @issue_severities MapSet.new(["all" | @issue_severity_values])

  def begin_overview_load(status) when status in [:ready, :refreshing, :stale], do: :refreshing
  def begin_overview_load(_status), do: :loading

  def fail_overview_load(:refreshing), do: :stale
  def fail_overview_load(_status), do: :error

  def begin_issues_load(status), do: begin_overview_load(status)
  def fail_issues_load(status), do: fail_overview_load(status)

  def put_pending_delete_id(socket, value) do
    assign(socket, :pending_delete_id, parse_entity_id(value))
  end

  def parse_entity_id(value) do
    case value do
      id when is_integer(id) and id > 0 and id <= @max_bigint ->
        id

      id when is_binary(id) ->
        case Integer.parse(id) do
          {parsed, ""} when parsed > 0 and parsed <= @max_bigint -> parsed
          _invalid -> nil
        end

      _invalid ->
        nil
    end
  end

  def pagination(rows, requested_page, per_page \\ @default_per_page) do
    total = length(rows)
    total_pages = max(ceil(total / per_page), 1)
    page = requested_page |> parse_page() |> clamp(1, total_pages)

    page_rows =
      rows
      |> Enum.drop((page - 1) * per_page)
      |> Enum.take(per_page)

    %{rows: page_rows, page: page, total_pages: total_pages, total: total}
  end

  def sort_table(data, sort_by, sort_dir, columns) do
    sorter = Map.get(columns, sort_by, &String.downcase(&1.name))
    Enum.sort_by(data, &{sortable_value(sorter.(&1)), &1.id}, sort_dir)
  end

  defp sortable_value(%DateTime{} = value), do: DateTime.to_unix(value, :microsecond)
  defp sortable_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_gregorian_seconds(value)
  defp sortable_value(%Date{} = value), do: Date.to_gregorian_days(value)
  defp sortable_value(value), do: value

  def handle_sort(socket, column, all_data_key, page_data_key, sort_columns) do
    {sort_by, sort_dir} = toggle_sort(column, socket.assigns.sort_by, socket.assigns.sort_dir)
    sorted = sort_table(socket.assigns[all_data_key], sort_by, sort_dir, sort_columns)
    page = pagination(sorted, 1)

    socket
    |> assign(:sort_by, sort_by)
    |> assign(:sort_dir, sort_dir)
    |> assign(all_data_key, sorted)
    |> assign(page_data_key, page.rows)
    |> assign(:page, page.page)
    |> assign(:total_pages, page.total_pages)
  end

  def handle_page(socket, requested_page, all_data_key, page_data_key, opts \\ []) do
    page_assign = Keyword.get(opts, :page_assign, :page)
    total_pages_assign = Keyword.get(opts, :total_pages_assign, :total_pages)
    total_assign = Keyword.get(opts, :total_assign)
    page = pagination(socket.assigns[all_data_key], requested_page)

    socket
    |> assign(page_data_key, page.rows)
    |> assign(page_assign, page.page)
    |> assign(total_pages_assign, page.total_pages)
    |> maybe_assign(total_assign, page.total)
  end

  def default_issue_filters, do: @default_issue_filters

  def default_issue_filter_options do
    %{
      totals: %{severity: 0, code: 0, resource: 0},
      severities: Enum.map(@issue_severity_values, &%{value: &1, count: 0}),
      codes: [],
      resources: []
    }
  end

  def put_issues(socket, issues, opts) do
    all_key = Keyword.fetch!(opts, :all_key)
    page_key = Keyword.fetch!(opts, :page_key)
    filters_key = Keyword.fetch!(opts, :filters_key)
    options_key = Keyword.fetch!(opts, :options_key)
    page_assign = Keyword.fetch!(opts, :page_assign)
    total_pages_assign = Keyword.fetch!(opts, :total_pages_assign)
    total_assign = Keyword.fetch!(opts, :total_assign)
    unfiltered_total_assign = Keyword.fetch!(opts, :unfiltered_total_assign)
    requested_page = Keyword.get(opts, :requested_page, socket.assigns[page_assign])

    previous_options = socket.assigns[options_key]
    catalog = issue_filter_catalog(issues)
    filters = normalize_issue_filters(socket.assigns[filters_key], catalog, previous_options)
    catalog = preserve_selected_catalog_options(catalog, filters, previous_options)
    options = issue_filter_options(issues, filters, catalog)
    filtered = filter_issues(issues, filters)
    page = pagination(filtered, requested_page)

    socket
    |> assign(all_key, issues)
    |> assign(page_key, page.rows)
    |> assign(filters_key, filters)
    |> assign(options_key, options)
    |> assign(page_assign, page.page)
    |> assign(total_pages_assign, page.total_pages)
    |> assign(total_assign, page.total)
    |> assign(unfiltered_total_assign, length(issues))
  end

  def handle_issue_filter(socket, filter, value, opts) when filter in @issue_filter_keys do
    filters_key = Keyword.fetch!(opts, :filters_key)
    value = normalize_filter_value(value)

    if selectable_filter_value?(socket, filter, value, opts) do
      filters = Map.put(socket.assigns[filters_key], filter, value)

      socket
      |> assign(filters_key, filters)
      |> put_issues(
        socket.assigns[Keyword.fetch!(opts, :all_key)],
        Keyword.put(opts, :requested_page, 1)
      )
    else
      socket
    end
  end

  def handle_issue_filter(socket, _filter, _value, _opts), do: socket

  def handle_issue_page(socket, requested_page, opts) do
    put_issues(
      socket,
      socket.assigns[Keyword.fetch!(opts, :all_key)],
      Keyword.put(opts, :requested_page, requested_page)
    )
  end

  def filter_issues(issues, filters) do
    Enum.filter(issues, fn issue ->
      matches_issue_filter?(issue, :severity, filters["severity"]) and
        matches_issue_filter?(issue, :code, filters["code"]) and
        matches_issue_filter?(issue, :resource_id, filters["resource"])
    end)
  end

  def put_stable_issue_ids(issues, domain, identity_fun) when is_binary(domain) and is_function(identity_fun, 1) do
    {issues, _occurrences} =
      Enum.map_reduce(issues, %{}, fn issue, occurrences ->
        fingerprint =
          issue
          |> identity_fun.()
          |> :erlang.term_to_binary([:deterministic])
          |> then(&:crypto.hash(:sha256, &1))
          |> Base.url_encode64(padding: false)

        base = "#{domain}:#{fingerprint}"
        occurrence = Map.get(occurrences, base, 0) + 1
        id = "#{base}:#{occurrence}"

        {Map.put(issue, :id, id), Map.put(occurrences, base, occurrence)}
      end)

    issues
  end

  defp issue_filter_catalog(issues) do
    codes =
      issues
      |> Enum.map(& &1.code)
      |> Enum.uniq()
      |> Enum.sort()

    resource_pairs =
      issues
      |> Enum.reject(&is_nil(&1.resource_id))
      |> Enum.reduce(%{}, fn issue, resources ->
        value = to_string(issue.resource_id)
        label = normalize_resource_label(issue.resource_label, value)
        Map.put_new(resources, value, label)
      end)
      |> Map.to_list()

    duplicate_labels =
      Enum.frequencies_by(resource_pairs, fn {_value, label} -> label end)

    resources =
      resource_pairs
      |> Enum.map(fn {value, label} ->
        label = if duplicate_labels[label] > 1, do: "#{label} · ##{value}", else: label
        %{value: value, label: label}
      end)
      |> Enum.sort_by(&{String.downcase(&1.label), &1.value})

    %{codes: codes, resources: resources}
  end

  defp issue_filter_options(issues, filters, catalog) do
    severity_issues = filter_issues(issues, Map.put(filters, "severity", "all"))
    code_issues = filter_issues(issues, Map.put(filters, "code", "all"))
    resource_issues = filter_issues(issues, Map.put(filters, "resource", "all"))

    severity_counts = issue_counts_by(severity_issues, :severity)
    code_counts = issue_counts_by(code_issues, :code)
    resource_counts = issue_counts_by(resource_issues, :resource_id)

    %{
      totals: %{
        severity: length(severity_issues),
        code: length(code_issues),
        resource: length(resource_issues)
      },
      severities: count_options(@issue_severity_values, severity_counts),
      codes: count_options(catalog.codes, code_counts),
      resources:
        Enum.map(catalog.resources, fn resource ->
          Map.put(resource, :count, Map.get(resource_counts, resource.value, 0))
        end)
    }
  end

  defp normalize_issue_filters(filters, catalog, previous_options) do
    valid_values = %{
      "severity" => @issue_severities,
      "code" =>
        catalog.codes
        |> Kernel.++(option_values(previous_options.codes))
        |> MapSet.new()
        |> MapSet.put("all"),
      "resource" =>
        catalog.resources
        |> Enum.map(& &1.value)
        |> Kernel.++(option_values(previous_options.resources))
        |> MapSet.new()
        |> MapSet.put("all")
    }

    Map.new(@issue_filter_keys, fn key ->
      value = Map.get(filters, key, "all")
      {key, if(MapSet.member?(valid_values[key], value), do: value, else: "all")}
    end)
  end

  defp preserve_selected_catalog_options(catalog, filters, previous_options) do
    code = filters["code"]
    resource = filters["resource"]

    codes =
      if code != "all" and code not in catalog.codes do
        Enum.sort([code | catalog.codes])
      else
        catalog.codes
      end

    resources =
      if resource != "all" and Enum.all?(catalog.resources, &(&1.value != resource)) do
        case Enum.find(previous_options.resources, &(&1.value == resource)) do
          nil ->
            catalog.resources

          previous ->
            Enum.sort_by(
              [Map.take(previous, [:value, :label]) | catalog.resources],
              &{String.downcase(&1.label), &1.value}
            )
        end
      else
        catalog.resources
      end

    %{catalog | codes: codes, resources: resources}
  end

  defp matches_issue_filter?(_issue, _key, "all"), do: true

  defp matches_issue_filter?(issue, key, value) do
    issue |> Map.get(key) |> to_string() == value
  end

  defp issue_counts_by(issues, key) do
    Enum.frequencies_by(issues, fn issue ->
      issue |> Map.get(key) |> to_string()
    end)
  end

  defp count_options(values, counts) do
    Enum.map(values, &%{value: &1, count: Map.get(counts, &1, 0)})
  end

  defp selectable_filter_value?(_socket, _filter, "all", _opts), do: true

  defp selectable_filter_value?(_socket, "severity", value, _opts) do
    MapSet.member?(@issue_severities, value)
  end

  defp selectable_filter_value?(socket, filter, value, opts) do
    options = socket.assigns[Keyword.fetch!(opts, :options_key)]

    values =
      case filter do
        "code" -> option_values(options.codes)
        "resource" -> option_values(options.resources)
      end

    value in values
  end

  defp option_values(options), do: Enum.map(options, & &1.value)

  defp normalize_filter_value(value) when is_binary(value), do: value
  defp normalize_filter_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_filter_value(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_filter_value(_value), do: "all"

  defp normalize_resource_label(label, _value) when is_binary(label) and label != "", do: label
  defp normalize_resource_label(_label, value), do: "##{value}"

  defp maybe_assign(socket, nil, _value), do: socket
  defp maybe_assign(socket, key, value), do: assign(socket, key, value)

  defp toggle_sort(column, current_by, current_dir) do
    if column == current_by do
      {column, if(current_dir == :asc, do: :desc, else: :asc)}
    else
      {column, :asc}
    end
  end

  defp parse_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {page, ""} -> page
      _ -> 1
    end
  end

  defp parse_page(page) when is_integer(page), do: page
  defp parse_page(_page), do: 1

  defp clamp(val, min, _max) when val < min, do: min
  defp clamp(val, _min, max) when val > max, do: max
  defp clamp(val, _min, _max), do: val
end
