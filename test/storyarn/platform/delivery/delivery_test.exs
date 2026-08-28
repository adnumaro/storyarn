defmodule Storyarn.Platform.DeliveryTest do
  use Storyarn.DataCase, async: true
  use Oban.Testing, repo: Storyarn.Repo

  alias Storyarn.Platform.Delivery
  alias Storyarn.Workers.DeliverInvitationWorker

  test "persists an invitation request with the stable Oban worker identity" do
    attrs = %{
      context: "workspace",
      encrypted_token: Base.encode64("already-encrypted"),
      inviter_name: "Ada",
      locale: "es"
    }

    assert {:ok, %Oban.Job{worker: worker, args: persisted_attrs}} =
             Delivery.enqueue_invitation_delivery(attrs)

    assert worker == inspect(DeliverInvitationWorker)
    assert persisted_attrs == attrs
  end
end
