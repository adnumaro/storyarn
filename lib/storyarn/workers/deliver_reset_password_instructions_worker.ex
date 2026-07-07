defmodule Storyarn.Workers.DeliverResetPasswordInstructionsWorker do
  @moduledoc """
  Delivers password reset instructions outside the LiveView request cycle.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Storyarn.Accounts
  alias Storyarn.Accounts.UserNotifier

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"email" => email, "encrypted_reset_url" => encrypted_reset_url}}) do
    with {:ok, reset_url} <- Accounts.decrypt_reset_password_url(encrypted_reset_url),
         {:ok, _email} <- UserNotifier.deliver_reset_password_instructions(email, reset_url) do
      :ok
    else
      {:error, reason} ->
        Logger.warning("Password reset email delivery failed reason=#{inspect(reason)}")
        {:error, reason}
    end
  end
end
