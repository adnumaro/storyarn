defmodule StoryarnWeb.Helpers.SaveStatusTimerTest do
  use ExUnit.Case, async: true

  alias Phoenix.LiveView.Socket
  alias StoryarnWeb.Helpers.SaveStatusTimer

  describe "schedule_reset/1-2" do
    test "stores a token on the socket" do
      socket = %Socket{assigns: %{save_status: :saved, __changed__: %{}}}
      result = SaveStatusTimer.schedule_reset(socket)

      assert is_reference(result.assigns.save_status_reset_token)
    end

    test "sends :reset_save_status message after default timeout" do
      socket = %Socket{assigns: %{__changed__: %{}}}
      SaveStatusTimer.schedule_reset(socket, 10)

      assert_receive {:reset_save_status, token}, 100
      assert is_reference(token)
    end

    test "returns socket with custom timeout" do
      socket = %Socket{assigns: %{__changed__: %{}}}
      result = SaveStatusTimer.schedule_reset(socket, 50)

      assert is_reference(result.assigns.save_status_reset_token)
      assert_receive {:reset_save_status, _token}, 200
    end

    test "does not send message before timeout" do
      socket = %Socket{assigns: %{__changed__: %{}}}
      SaveStatusTimer.schedule_reset(socket, 200)

      refute_receive {:reset_save_status, _token}, 50
    end
  end
end
