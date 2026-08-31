defmodule StoryarnTest.AI.MissingLockFreeMarkerTask do
  @moduledoc false

  # The registry must reject this fixture before calling definition/0. Keeping
  # it outside the behaviour avoids a compile warning for the deliberately
  # missing marker while still exercising the runtime registration boundary.
  def definition, do: raise("unsafe definition was evaluated")
end
