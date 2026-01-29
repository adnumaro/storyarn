defmodule Storyarn.Repo do
  use Ecto.Repo,
    otp_app: :storyarn,
    adapter: Ecto.Adapters.Postgres
end
