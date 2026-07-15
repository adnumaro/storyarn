defmodule Storyarn.FailingMailerAdapter do
  @moduledoc false

  use Swoosh.Adapter

  @impl true
  def deliver(_email, _config), do: {:error, :simulated_delivery_failure}

  @impl true
  def deliver_many(_emails, _config), do: {:error, :simulated_delivery_failure}
end
