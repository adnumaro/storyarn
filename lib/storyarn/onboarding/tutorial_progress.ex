defmodule Storyarn.Onboarding.TutorialProgress do
  @moduledoc """
  Per-user progress for a contextual onboarding tutorial.

  Missing rows and rows without `completed_at` represent tutorials that should
  be shown. A completed timestamp records the user's explicit choice not to see
  that tutorial automatically again.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Accounts.User

  @tutorials [:workspace, :sheets, :flows, :scenes, :localization, :export]

  @type tutorial :: :workspace | :sheets | :flows | :scenes | :localization | :export

  @type t :: %__MODULE__{
          id: integer() | nil,
          tutorial: tutorial() | nil,
          guide_version: pos_integer(),
          completed_at: DateTime.t() | nil,
          user_id: integer() | nil,
          user: User.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "onboarding_tutorial_progress" do
    field :tutorial, Ecto.Enum, values: @tutorials
    field :guide_version, :integer, default: 1
    field :completed_at, :utc_datetime

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc "Returns the stable tutorial keys supported by the application."
  @spec tutorials() :: [tutorial()]
  def tutorials, do: @tutorials

  @doc "Safely casts a client or server tutorial key without creating atoms."
  @spec cast_tutorial(atom() | String.t()) :: {:ok, tutorial()} | :error
  def cast_tutorial(tutorial) when tutorial in @tutorials, do: {:ok, tutorial}

  def cast_tutorial(tutorial) when is_binary(tutorial) do
    case Enum.find(@tutorials, &(Atom.to_string(&1) == tutorial)) do
      nil -> :error
      value -> {:ok, value}
    end
  end

  def cast_tutorial(_tutorial), do: :error

  @doc false
  def changeset(progress, attrs) do
    progress
    |> cast(attrs, [:tutorial, :guide_version, :completed_at])
    |> validate_required([:tutorial, :guide_version])
    |> validate_number(:guide_version, greater_than: 0)
    |> unique_constraint([:user_id, :tutorial],
      name: :onboarding_tutorial_progress_user_id_tutorial_index
    )
    |> foreign_key_constraint(:user_id)
  end
end
