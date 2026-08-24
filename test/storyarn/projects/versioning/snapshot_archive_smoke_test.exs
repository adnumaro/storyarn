defmodule Storyarn.Projects.Versioning.SnapshotArchiveSmokeTest do
  use ExUnit.Case, async: false

  alias Storyarn.Projects.Versioning.SnapshotArchiveSmoke

  test "runtime module has no compiled dependency on Mix" do
    beam = :code.which(SnapshotArchiveSmoke)

    assert {:ok, {SnapshotArchiveSmoke, [imports: imports]}} =
             :beam_lib.chunks(beam, [:imports])

    refute Enum.any?(imports, fn {module, _function, _arity} ->
             module |> Atom.to_string() |> String.starts_with?("Elixir.Mix")
           end)
  end

  test "requires a positive snapshot id" do
    assert_raise ArgumentError, "snapshot_id must be a positive integer", fn ->
      SnapshotArchiveSmoke.run!(0)
    end
  end

  test "fails before database or provider access without the real adapter" do
    original_storage = Application.get_env(:storyarn, :storage)
    Application.put_env(:storyarn, :storage, adapter: :local)

    on_exit(fn -> restore_env(:storyarn, :storage, original_storage) end)

    assert_raise RuntimeError,
                 "The real S3-compatible production storage adapter is not configured.",
                 fn -> SnapshotArchiveSmoke.run!(1) end
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
