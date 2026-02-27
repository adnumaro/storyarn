defmodule Storyarn.Test.InkCompiler do
  @moduledoc """
  Helper for validating .ink files using the official Ink compiler (inklecate).

  In CI, inklecate is built from source and available in PATH.
  Locally, tests requiring inklecate are skipped unless it's installed.

  ## Usage in tests

      @tag :ink_validation
      test "export produces valid ink", %{project: project} do
        source = ink_source(export_ink(project))
        assert InkCompiler.valid?(source)
      end

  ## Running locally

      # Install .NET SDK, then build inklecate:
      git clone --depth 1 --branch v.1.2.0 https://github.com/inkle/ink.git /tmp/inklecate-src
      dotnet publish /tmp/inklecate-src/inklecate/inklecate.csproj \\
        -c Release -r osx-arm64 --self-contained true -o /opt/inklecate
      # Add /opt/inklecate to PATH

      # Run validation tests:
      mix test --only ink_validation
  """

  @tmp_dir System.tmp_dir!()

  @doc """
  Returns true if inklecate is available in the system PATH.
  """
  def available? do
    case System.find_executable("inklecate") do
      nil -> false
      _path -> true
    end
  end

  @doc """
  Validates an .ink source string by compiling it with inklecate.

  Returns `:ok` if the file compiles successfully, or
  `{:error, exit_code, output}` if compilation fails.
  """
  def validate(ink_source) when is_binary(ink_source) do
    unless available?() do
      raise "inklecate not found in PATH. See module docs for build instructions."
    end

    dir = Path.join(@tmp_dir, "storyarn_ink_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    file_path = Path.join(dir, "export.ink")

    try do
      File.write!(file_path, ink_source)

      case System.cmd("inklecate", ["-o", Path.join(dir, "output.json"), file_path],
             stderr_to_stdout: true,
             cd: dir
           ) do
        {_output, 0} -> :ok
        {output, code} -> {:error, code, output}
      end
    after
      File.rm_rf!(dir)
    end
  end

  @doc """
  Returns true if the .ink source compiles without errors.
  """
  def valid?(ink_source) do
    validate(ink_source) == :ok
  end
end
