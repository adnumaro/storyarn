defmodule Storyarn.Accounts.WaitlistEntry do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.ProductMetrics.Taxonomy
  alias Storyarn.Shared.Validations

  @metric_fields [
    :profession,
    :primary_interest,
    :discovery_source,
    :current_tool,
    :current_tool_other
  ]

  schema "waitlist_entries" do
    field :email, :string
    field :profession, :string
    field :primary_interest, :string
    field :discovery_source, :string
    field :current_tool, :string
    field :current_tool_other, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(waitlist_entry, attrs) do
    waitlist_entry
    |> cast(attrs, [
      :email,
      :profession,
      :primary_interest,
      :discovery_source,
      :current_tool,
      :current_tool_other
    ])
    |> normalize_email()
    |> validate_required([:email, :profession, :primary_interest, :discovery_source])
    |> Validations.validate_email_format()
    |> validate_metrics()
    |> unique_constraint(:email)
  end

  def email_changeset(waitlist_entry, attrs) do
    waitlist_entry
    |> cast(attrs, [:email])
    |> normalize_email()
    |> validate_required([:email])
    |> Validations.validate_email_format()
    |> unique_constraint(:email)
  end

  def details_changeset(waitlist_entry, attrs) do
    waitlist_entry
    |> cast(attrs, @metric_fields)
    |> validate_metrics()
  end

  defp normalize_email(changeset) do
    update_change(changeset, :email, fn email ->
      email
      |> String.trim()
      |> String.downcase()
    end)
  end

  defp validate_metrics(changeset) do
    changeset
    |> validate_inclusion(:profession, Taxonomy.professions())
    |> validate_inclusion(:primary_interest, Taxonomy.primary_interests())
    |> validate_inclusion(:discovery_source, Taxonomy.discovery_sources())
    |> validate_inclusion(:current_tool, Taxonomy.current_tools())
    |> validate_length(:current_tool_other, max: 120)
    |> validate_current_tool_other()
  end

  defp validate_current_tool_other(changeset) do
    if get_field(changeset, :current_tool) == "other" do
      validate_required(changeset, [:current_tool_other])
    else
      changeset
    end
  end
end
