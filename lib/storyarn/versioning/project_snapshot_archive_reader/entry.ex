defmodule Storyarn.Versioning.ProjectSnapshotArchiveReader.Entry do
  @moduledoc false

  @enforce_keys [
    :path,
    :size_bytes,
    :sha256,
    :content_type,
    :data_offset,
    :crc32,
    :local_header_offset
  ]
  defstruct [
    :path,
    :size_bytes,
    :sha256,
    :content_type,
    :data_offset,
    :crc32,
    :local_header_offset
  ]

  @type t :: %__MODULE__{
          path: String.t(),
          size_bytes: non_neg_integer(),
          sha256: String.t(),
          content_type: String.t(),
          data_offset: non_neg_integer(),
          crc32: non_neg_integer(),
          local_header_offset: non_neg_integer()
        }
end
