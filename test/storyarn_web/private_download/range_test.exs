defmodule StoryarnWeb.PrivateDownload.RangeTest do
  use ExUnit.Case, async: true

  alias StoryarnWeb.PrivateDownload.Range, as: DownloadRange

  @etag ~s("object-etag")

  test "selects the full object when Range is absent" do
    assert DownloadRange.select([], [], 10, @etag) == full_selection(10)
  end

  test "selects closed, open, and suffix byte ranges" do
    assert DownloadRange.select(["bytes=2-5"], [], 10, @etag) ==
             partial_selection(2, 5, 10)

    assert DownloadRange.select(["bytes=7-"], [], 10, @etag) ==
             partial_selection(7, 9, 10)

    assert DownloadRange.select(["bytes=-3"], [], 10, @etag) ==
             partial_selection(7, 9, 10)

    assert DownloadRange.select(["bytes=-20"], [], 10, @etag) ==
             partial_selection(0, 9, 10)
  end

  test "clips the end of a closed range to the object size" do
    assert DownloadRange.select(["bytes=7-20"], [], 10, @etag) ==
             partial_selection(7, 9, 10)
  end

  test "marks ranges outside the object or in reverse order as unsatisfiable" do
    assert DownloadRange.select(["bytes=10-"], [], 10, @etag) ==
             unsatisfied_selection(10)

    assert DownloadRange.select(["bytes=5-4"], [], 10, @etag) ==
             unsatisfied_selection(10)

    assert DownloadRange.select(["bytes=-0"], [], 10, @etag) ==
             unsatisfied_selection(10)
  end

  test "ignores malformed, unsupported, multiple, and multi-range headers" do
    for range_headers <- [
          ["not-bytes=0-1"],
          ["bytes=invalid"],
          ["bytes=0-1,3-4"],
          ["bytes=0-1", "bytes=3-4"]
        ] do
      assert DownloadRange.select(range_headers, [], 10, @etag) == full_selection(10)
    end
  end

  test "distinguishes valid and malformed ranges for an empty object" do
    assert DownloadRange.select(["bytes=0-"], [], 0, @etag) ==
             unsatisfied_selection(0)

    assert DownloadRange.select(["bytes=not-a-range"], [], 0, @etag) ==
             full_selection(0)
  end

  test "honors Range only when If-Range exactly matches the object ETag" do
    assert DownloadRange.select(["bytes=2-5"], [@etag], 10, @etag) ==
             partial_selection(2, 5, 10)

    assert DownloadRange.select(["bytes=2-5"], [~s("stale-etag")], 10, @etag) ==
             full_selection(10)

    assert DownloadRange.select(["bytes=2-5"], [@etag], 10, nil) ==
             %{full_selection(10) | etag: nil}

    assert DownloadRange.select(["bytes=2-5"], [@etag, @etag], 10, @etag) ==
             full_selection(10)
  end

  defp full_selection(size) do
    %{
      status: :ok,
      offset: 0,
      length: size,
      last_byte: max(size - 1, 0),
      size: size,
      etag: @etag
    }
  end

  defp partial_selection(first_byte, last_byte, size) do
    %{
      status: :partial_content,
      offset: first_byte,
      length: last_byte - first_byte + 1,
      last_byte: last_byte,
      size: size,
      etag: @etag
    }
  end

  defp unsatisfied_selection(size) do
    %{
      status: :range_not_satisfiable,
      offset: 0,
      length: 0,
      last_byte: 0,
      size: size,
      etag: @etag
    }
  end
end
