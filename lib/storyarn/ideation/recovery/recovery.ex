defmodule Storyarn.Ideation.Recovery do
  @moduledoc false
  alias Storyarn.Ideation.Recovery.Capsule
  alias Storyarn.Ideation.Recovery.Capture
  alias Storyarn.Ideation.Recovery.Restore
  alias Storyarn.Repo

  def capture(project_id) do
    if Repo.in_transaction?() do
      Capture.run(project_id)
    else
      {:error, :ideation_recovery_transaction_required}
    end
  end

  def validate(nil), do: :ok

  def validate(capsule) do
    with {:ok, _} <- Capsule.open(capsule), do: :ok
  end

  defdelegate restore(project_id, capsule, destination_maps \\ nil), to: Restore, as: :run
  defdelegate verify(project_id, capsule, maps), to: Restore
end
