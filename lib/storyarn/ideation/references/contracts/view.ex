defmodule Storyarn.Ideation.References.View do
  @moduledoc false
  alias Storyarn.Platform.Shared.TimeHelpers

  def context(target) do
    %{
      "name" => target.name,
      "fingerprint" => target.fingerprint,
      "captured_at" => DateTime.to_iso8601(TimeHelpers.now()),
      "overview" => target.context
    }
  end

  def available?(reference, target), do: not is_nil(target) and target.identity == reference.target_identity

  def project(reference, target) do
    available = available?(reference, target)

    %{
      id: reference.id,
      version: reference.version,
      relation: reference.relation,
      target_type: reference.target_type,
      target_id: if(available, do: reference.target_id),
      status: status(reference, target, available),
      base: if(available, do: reference.context),
      current: if(available, do: target),
      captured_at: if(available, do: reference.context["captured_at"])
    }
  end

  defp status(_, _, false), do: "unavailable"

  defp status(reference, target, true) do
    if reference.context["fingerprint"] == target.fingerprint, do: "current", else: "changed"
  end

  def revision(row),
    do: %{
      number: row.number,
      operation: row.operation,
      actor_id: row.actor_id,
      context: row.context,
      inserted_at: DateTime.to_iso8601(row.inserted_at)
    }
end
