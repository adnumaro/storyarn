defmodule StoryarnWeb.Helpers.SaveStatusTimerTest do
  use ExUnit.Case, async: true

  alias StoryarnWeb.Helpers.SaveStatusTimer

  describe "schedule_reset/1-2" do
    test "returns the socket unchanged (passthrough for piping)" do
      socket = %{assigns: %{save_status: :saved}}
      assert SaveStatusTimer.schedule_reset(socket) == socket
    end

    test "sends :reset_save_status message after default timeout" do
      socket = :some_socket
      SaveStatusTimer.schedule_reset(socket, 10)

      assert_receive :reset_save_status, 100
    end

    test "returns socket with custom timeout" do
      socket = %{assigns: %{}}
      result = SaveStatusTimer.schedule_reset(socket, 50)

      assert result == socket
      assert_receive :reset_save_status, 200
    end

    test "does not send message before timeout" do
      SaveStatusTimer.schedule_reset(:socket, 200)

      refute_receive :reset_save_status, 50
    end
  end
end
