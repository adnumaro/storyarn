defmodule Storyarn.AI.Telemetry do
  @moduledoc false

  @allowed_metadata_keys [
    :task_id,
    :capability,
    :lane,
    :provider,
    :status,
    :error_classification,
    :context_version,
    :context_scope,
    :builder_version,
    :context_hash
  ]

  def emit(event, measurements, metadata) when is_list(event) and is_map(measurements) and is_map(metadata) do
    safe_metadata = Map.take(metadata, @allowed_metadata_keys)
    :telemetry.execute([:ai | event], measurements, safe_metadata)
  end
end
