defmodule Storyarn.AI.WorkspacePolicyAudit do
  @moduledoc "Append-only snapshot of a workspace AI-policy transition."
  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Accounts.User
  alias Storyarn.Workspaces.Workspace

  schema "ai_workspace_policy_audits" do
    field :workspace_id_snapshot, :integer
    field :actor_id, :integer
    field :from_lanes, {:array, :string}, default: []
    field :to_lanes, {:array, :string}, default: []
    field :from_version, :integer
    field :to_version, :integer

    belongs_to :workspace, Workspace
    belongs_to :user, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(audit, attrs) do
    changeset =
      audit
      |> cast(attrs, [
        :from_lanes,
        :to_lanes,
        :from_version,
        :to_version
      ])
      |> put_identity_fields(attrs)
      |> validate_required([
        :workspace_id_snapshot,
        :actor_id,
        :from_lanes,
        :to_lanes,
        :from_version,
        :to_version
      ])
      |> foreign_key_constraint(:workspace_id)
      |> foreign_key_constraint(:user_id)

    from_version = get_field(changeset, :from_version)
    to_version = get_field(changeset, :to_version)

    if is_integer(from_version) and is_integer(to_version) and to_version == from_version + 1 do
      changeset
    else
      add_error(changeset, :to_version, "must increment once")
    end
  end

  defp put_identity_fields(changeset, attrs) do
    Enum.reduce([:workspace_id, :workspace_id_snapshot, :user_id, :actor_id], changeset, fn field, acc ->
      put_change(acc, field, Map.get(attrs, field))
    end)
  end
end
