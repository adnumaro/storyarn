defmodule Storyarn.Ideation.Sessions.Execution.ContextualLinkReceipt do
  @moduledoc false
  import Ecto.Changeset

  alias Storyarn.Ideation.Sessions.Execution.Mutation
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Repo

  # References already owns the authorized contribution lock. A successful reuse
  # needs its own receipt so replay cannot recreate an independently removed link.
  def record(access, key, fingerprint, reference_identity) do
    if Repo.in_transaction?() do
      session = Repo.get!(Session, access.session_id)

      with {:ok, updated} <- session |> change(revision: session.revision + 1) |> Repo.update() do
        Mutation.record(updated, access.user_id, :context_linked, %{
          "contextual_request" => %{
            "key" => key,
            "fingerprint" => Base.encode16(fingerprint, case: :lower),
            "reference_identity" => reference_identity
          }
        })
      end
    else
      {:error, :contribution_transaction_required}
    end
  end
end
