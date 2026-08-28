defmodule Storyarn.Platform.Billing.Persistence.ProjectTemplateRecord do
  @moduledoc "Consumer-owned read-only SQL projection for this Platform capability."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "project_templates" do
    field :source_project_id, :id

    timestamps(type: :utc_datetime)
  end
end
