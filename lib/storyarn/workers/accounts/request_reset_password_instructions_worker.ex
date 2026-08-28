defmodule Storyarn.Workers.RequestResetPasswordInstructionsWorker do
  @moduledoc """
  Resolves password reset requests outside the public request path.

  Missing and existing accounts therefore have the same synchronous database
  and queue workload from the caller's perspective.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Storyarn.Accounts

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"email" => email, "reset_url_template" => reset_url_template}}) do
    case Accounts.process_user_reset_password_request(email, reset_url_template) do
      :ok ->
        :ok

      {:ok, :queued} ->
        :ok

      {:error, reason} ->
        Logger.warning("Password reset request processing failed reason=#{inspect(reason)}")
        {:error, reason}
    end
  end
end
