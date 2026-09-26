defmodule Storyarn.RepoTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Repo

  describe "repeatable_read/2" do
    test "joins the repeatable-read transaction it is nested in" do
      assert {:ok, {:ok, :inner}} =
               Repo.repeatable_read(fn -> Repo.repeatable_read(fn -> :inner end) end)
    end

    test "refuses to change the isolation of a transaction opened without it" do
      assert_raise ArgumentError, ~r/cannot change the isolation/, fn ->
        Repo.transaction(fn -> Repo.repeatable_read(fn -> :inner end) end)
      end
    end

    test "leaves no marker behind, so a later transaction is still checked" do
      assert {:ok, :done} = Repo.repeatable_read(fn -> :done end)

      assert_raise ArgumentError, fn ->
        Repo.transaction(fn -> Repo.repeatable_read(fn -> :inner end) end)
      end
    end

    test "clears the marker when the transaction raises" do
      assert_raise RuntimeError, fn -> Repo.repeatable_read(fn -> raise "boom" end) end

      assert_raise ArgumentError, fn ->
        Repo.transaction(fn -> Repo.repeatable_read(fn -> :inner end) end)
      end
    end
  end
end
