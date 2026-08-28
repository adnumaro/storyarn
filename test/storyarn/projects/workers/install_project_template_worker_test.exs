defmodule Storyarn.Workers.InstallProjectTemplateWorkerTest do
  use ExUnit.Case, async: true

  alias Storyarn.Workers.InstallProjectTemplateWorker

  test "snoozes session lock contention without consuming the retry budget" do
    assert {:snooze, 30} =
             InstallProjectTemplateWorker.handle_perform_result(
               {:error, :session_lock_timeout},
               123
             )
  end
end
