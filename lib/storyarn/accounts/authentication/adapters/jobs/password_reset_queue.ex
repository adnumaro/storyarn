defmodule Storyarn.Accounts.Authentication.Adapters.Jobs.PasswordResetQueue do
  @moduledoc """
  Technical adapter for the two-stage durable password-reset workflow.

  Worker module identities remain stable because existing Oban jobs may store
  them as serialized strings.
  """

  alias Storyarn.Workers.DeliverResetPasswordInstructionsWorker
  alias Storyarn.Workers.RequestResetPasswordInstructionsWorker

  @spec enqueue_request(String.t(), String.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_request(email, reset_url_template) do
    %{email: email, reset_url_template: reset_url_template}
    |> RequestResetPasswordInstructionsWorker.new()
    |> Oban.insert()
  end

  @spec enqueue_delivery(String.t(), String.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_delivery(email, encrypted_reset_url) do
    %{email: email, encrypted_reset_url: encrypted_reset_url}
    |> DeliverResetPasswordInstructionsWorker.new()
    |> Oban.insert()
  end
end
