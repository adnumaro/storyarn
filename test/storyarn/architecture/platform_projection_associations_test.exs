defmodule Storyarn.Architecture.PlatformProjectionAssociationsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Platform.Notifications.Data.ProjectRecord
  alias Storyarn.Platform.Notifications.Data.UserRecord
  alias Storyarn.Platform.Notifications.Notification

  test "notification associations use notification-owned projections" do
    assert association(Notification, :recipient) == UserRecord
    assert association(Notification, :actor) == UserRecord
    assert association(Notification, :project) == ProjectRecord
  end

  test "Notifications does not import Billing persistence models" do
    violations =
      "lib/storyarn/platform/notifications/**/*.ex"
      |> Path.wildcard()
      |> Enum.filter(fn path ->
        File.read!(path) =~ "Storyarn.Platform.Billing.Persistence"
      end)

    assert violations == [],
           "Notifications must duplicate the read shape it needs instead of importing Billing models: #{inspect(violations)}"
  end

  defp association(schema, name), do: schema.__schema__(:association, name).related
end
