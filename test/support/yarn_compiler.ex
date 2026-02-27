defmodule Storyarn.Test.YarnCompiler do
  @moduledoc """
  Helper for validating .yarn files using the official Yarn Spinner compiler (ysc).

  In CI, ysc is built from source and available in PATH.
  Locally, tests requiring ysc are skipped unless it's installed.

  ## Usage in tests

      @tag :ysc_validation
      test "export produces valid yarn", %{project: project} do
        source = yarn_source(export_yarn(project))
        assert YarnCompiler.valid?(source)
      end

  ## Running locally

      # Install .NET SDK, then:
      dotnet tool install --global YarnSpinner.Console

      # Run validation tests:
      mix test --only ysc_validation
  """

  @tmp_dir System.tmp_dir!()

  @doc """
  Returns true if ysc is available in the system PATH.
  """
  def available? do
    case System.find_executable("ysc") do
      nil -> false
      _path -> true
    end
  end

  @doc """
  Validates a .yarn source string by compiling it with ysc.

  Returns `:ok` if the file compiles successfully, or
  `{:error, exit_code, output}` if compilation fails.
  """
  def validate(yarn_source) when is_binary(yarn_source) do
    unless available?() do
      raise "ysc not found in PATH. Install with: dotnet tool install --global YarnSpinner.Console"
    end

    dir = Path.join(@tmp_dir, "storyarn_ysc_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    file_path = Path.join(dir, "export.yarn")

    try do
      File.write!(file_path, yarn_source)

      case System.cmd("ysc", ["compile", file_path],
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
  Returns true if the .yarn source compiles without errors.
  """
  def valid?(yarn_source) do
    validate(yarn_source) == :ok
  end

  @doc """
  Validates multiple .yarn files (for multi-file exports).

  Yarn Spinner compiles all files together, so cross-file references
  (like <<jump>> to nodes in other files) are validated.
  """
  def validate_multi(files) when is_list(files) do
    unless available?() do
      raise "ysc not found in PATH. Install with: dotnet tool install --global YarnSpinner.Console"
    end

    dir = Path.join(@tmp_dir, "storyarn_ysc_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    try do
      paths =
        Enum.flat_map(files, fn {name, content} ->
          if String.ends_with?(name, ".yarn") do
            path = Path.join(dir, name)
            File.write!(path, content)
            [path]
          else
            []
          end
        end)

      case paths do
        [] ->
          {:error, 0, "No .yarn files found in export"}

        paths ->
          case System.cmd("ysc", ["compile" | paths],
                 stderr_to_stdout: true,
                 cd: dir
               ) do
            {_output, 0} -> :ok
            {output, code} -> {:error, code, output}
          end
      end
    after
      File.rm_rf!(dir)
    end
  end
end
