defmodule Storyarn.Accounts.WaitlistEntry do
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Shared.Validations

  schema "waitlist_entries" do
    field :email, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(waitlist_entry, attrs) do
    waitlist_entry
    |> cast(attrs, [:email])
    |> validate_required([:email])
    |> Validations.validate_email_format()
    |> unique_constraint(:email)
  end
end
