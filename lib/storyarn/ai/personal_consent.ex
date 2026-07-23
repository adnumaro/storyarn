defmodule Storyarn.AI.PersonalConsent do
  @moduledoc "Actor-owned consent for one personal integration and workspace AI scope."
  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Accounts.User
  alias Storyarn.AI.Integration
  alias Storyarn.Workspaces.Workspace

  @capabilities ~w(translation suggestions tasks images)

  schema "ai_personal_consents" do
    field :provider, :string
    field :capability, :string
    field :cost_class, :string
    field :policy_text_version, :string
    field :granted_at, :utc_datetime
    field :revoked_at, :utc_datetime

    belongs_to :user, User
    belongs_to :workspace, Workspace
    belongs_to :integration, Integration

    timestamps(type: :utc_datetime)
  end

  def grant_changeset(consent, attrs) do
    consent
    |> cast(attrs, [:provider, :capability, :cost_class, :policy_text_version, :granted_at])
    |> put_identity_fields(attrs)
    |> validate_required([
      :user_id,
      :workspace_id,
      :integration_id,
      :provider,
      :capability,
      :cost_class,
      :policy_text_version,
      :granted_at
    ])
    |> validate_inclusion(:capability, @capabilities)
    |> validate_length(:provider, min: 1, max: 80)
    |> validate_length(:cost_class, min: 1, max: 80)
    |> validate_length(:policy_text_version, min: 1, max: 120)
    |> unique_constraint(
      [:user_id, :workspace_id, :integration_id, :capability, :cost_class, :policy_text_version],
      name: :ai_personal_consents_active_scope_index
    )
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:integration_id)
  end

  def revoke_changeset(consent, revoked_at) do
    consent
    |> change(revoked_at: revoked_at)
    |> validate_required([:revoked_at])
  end

  defp put_identity_fields(changeset, attrs) do
    Enum.reduce([:user_id, :workspace_id, :integration_id], changeset, fn field, acc ->
      put_change(acc, field, Map.get(attrs, field))
    end)
  end
end
