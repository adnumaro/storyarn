defmodule Storyarn.Ideation.Recovery.Capture do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Recovery.Capsule
  alias Storyarn.Ideation.Recovery.Inventory
  alias Storyarn.Ideation.Recovery.Records
  alias Storyarn.Repo

  # Project's exclusive capture lock serializes this derived cache. Reusing the
  # authenticated bytes keeps canonical checksums stable without deterministic
  # encryption/nonces. This cache is disposable, not a recovery dependency.
  def run(project_id) do
    with {:ok, data} <- Records.capture(project_id) do
      digest = :crypto.hash(:sha256, Inventory.encode(data))

      cached =
        Repo.one(
          from c in "ideation_recovery_captures", where: c.project_id == ^project_id, select: map(c, [:digest, :capsule])
        )

      case cached do
        %{digest: ^digest, capsule: capsule} -> {:ok, capsule}
        _ -> persist(project_id, digest, data)
      end
    end
  end

  defp persist(project_id, digest, data) do
    with {:ok, capsule} <- Capsule.seal(data) do
      Repo.insert_all("ideation_recovery_captures", [%{project_id: project_id, digest: digest, capsule: capsule}],
        conflict_target: [:project_id],
        on_conflict: {:replace, [:digest, :capsule]},
        log: false
      )

      {:ok, capsule}
    end
  end
end
