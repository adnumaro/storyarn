defmodule StoryarnWeb.FlowLive.Helpers.HealthHelpers do
  @moduledoc """
  Serializes `Storyarn.Flows.HealthChecker` findings for the Vue header popover.

  The sibling of `StoryarnWeb.SheetLive.Helpers.HealthHelpers` and
  `StoryarnWeb.SceneLive.Helpers.HealthHelpers`, and deliberately identical to
  them in shape: findings are grouped by location, sorted stably, and each
  reason travels as `%{code, details}` for Vue to translate under
  `flows.health.findings.<code>`. Rendering the sentence here instead is what
  kept flows from reusing the shared popover.

  Both detectors — the per-node editorial checks and the graph-derived structural
  ones in `Storyarn.Flows.StructuralAnalysis` — already emit through
  `HealthChecker.finding/2`, so this serializes one flat list.
  """

  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Shared.StringUtils
  alias StoryarnWeb.FlowLive.NodeTypeRegistry

  @empty_health %{errorItems: [], warningItems: [], infoItems: []}

  @doc "An empty payload suitable for the initial socket assign."
  def empty_health, do: @empty_health

  @doc "Serializes checker findings into stable, grouped UI payloads."
  def health_payload(findings, flow_name) do
    %{
      errorItems: health_items(findings, :error, flow_name),
      warningItems: health_items(findings, :warning, flow_name),
      infoItems: health_items(findings, :info, flow_name)
    }
  end

  defp health_items(findings, severity, flow_name) do
    findings
    |> Enum.filter(&(&1.severity == severity))
    |> Enum.group_by(&{&1.entity_type, &1.entity_id})
    |> Enum.map(fn {_location, grouped} -> health_item(grouped, flow_name) end)
    |> Enum.sort_by(&{is_nil(&1.entityId), &1.label, &1.entityId || 0})
  end

  defp health_item([finding | _] = findings, flow_name) do
    %{
      entityType: finding.entity_type,
      entityId: finding.entity_id,
      label: health_label(finding, flow_name),
      reasons:
        Enum.map(findings, fn item ->
          %{code: Atom.to_string(item.code), details: item.details}
        end)
    }
  end

  defp health_label(%{entity_id: nil}, flow_name), do: StringUtils.present_label(flow_name, dgettext("flows", "Flow"))

  defp health_label(%{entity_type: type, entity_id: id}, _flow_name) do
    dgettext("flows", "%{type} #%{id}", type: NodeTypeRegistry.label(type), id: id)
  end
end
