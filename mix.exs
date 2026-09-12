defmodule Storyarn.MixProject do
  use Mix.Project

  def project do
    [
      app: :storyarn,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      test_coverage: [summary: [threshold: 85]],
      test_ignore_filters: [~r/generate_snapshots/],
      dialyzer: [
        # Ignore known false positive with Gettext plural handling
        ignore_warnings: ".dialyzer_ignore.exs",
        plt_add_apps: [:mix]
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Storyarn.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test, "test.e2e": :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:tidewave, "~> 0.5", only: [:dev]},
      {:bcrypt_elixir, "~> 3.0"},

      # Encryption for sensitive data
      {:cloak, "~> 1.1"},
      {:cloak_ecto, "~> 1.3"},
      {:phoenix, "~> 1.8.1"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, "~> 0.22"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:phoenix_live_dashboard, "~> 0.9.1"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:live_vue, "~> 1.2.3"},
      {:igniter, "~> 0.6"},
      {:swoosh, "~> 1.16"},
      {:gen_smtp, "~> 1.0"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_metrics_prometheus_core, "~> 1.2"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26 or ~> 1.0"},
      {:jason, "~> 1.2"},
      {:zstream, "~> 0.6"},
      {:floki, "~> 0.36"},
      {:hammer, "~> 7.0"},
      {:hammer_backend_redis, "~> 7.0"},
      {:remote_ip, "~> 1.2"},
      {:dns_cluster, "~> 0.3.0"},
      {:bandit, "~> 1.5"},

      # Background jobs
      {:oban, "~> 2.19"},

      # S3-compatible storage (Fly Tigris)
      {:ex_aws, "~> 2.6"},
      {:ex_aws_s3, "~> 2.5"},

      # Image processing (libvips - much safer than ImageMagick)
      {:image, "~> 0.63"},

      # Excel export for localization
      {:elixlsx, "~> 0.6"},

      # Product analytics and error tracking
      {:posthog, "~> 2.0"},

      # Feature flags (Postgres-backed, per-user targeting)
      {:fun_with_flags, "~> 1.13"},
      {:fun_with_flags_ui, "~> 1.1", only: :dev},

      # Email templates (MJML → HTML via Rust NIF)
      {:mjml, "~> 6.0"},

      # Documentation
      {:nimble_publisher, "~> 2.1"},
      # faker pins makeup == 1.2.1 for its own docs; the override takes the HTML escaping fix in 1.2.2.
      {:makeup, "~> 1.2.2", override: true},
      {:makeup_elixir, "~> 1.0"},

      # Code quality & security
      {:credo, "~> 1.7.19", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.15.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mix_unused, "~> 0.4", only: :dev, runtime: false},
      {:styler, "~> 1.0", only: [:dev, :test], runtime: false},

      # Testing utilities
      {:ex_machina, "~> 2.8", only: :test},
      {:mox, "~> 1.2", only: :test},
      {:faker, "~> 0.19", only: :test},
      # E2E testing with Playwright
      {:phoenix_test, "~> 0.4", only: :test, runtime: false},
      {:phoenix_test_playwright, "~> 0.10", only: :test, runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: &run_tests/1,
      "test.e2e": ["test test/e2e --include e2e"],
      "assets.setup": ["tailwind.install --if-missing"],
      "assets.build": ["compile", "tailwind storyarn", "phoenix_vite.npm vite build"],
      "assets.deploy": [
        "tailwind storyarn --minify",
        "phoenix_vite.npm vite build",
        "phx.digest"
      ],
      precommit: [
        # Gettext recompiles in this VM; defer consolidation to that pass.
        "compile --warnings-as-errors --no-consolidate-protocols",
        "deps.unlock --unused",
        "format",
        # The suite can only compare `.po` against `.pot`; both are derived, so a
        # `dgettext` that was never extracted is missing from both and every
        # assertion still passes while the string renders in English for `es`.
        # This is the only step that reads the source tree itself. It is strict
        # about `#:` reference lines too, so moving a `dgettext` to another line
        # fails it — re-run `mix gettext.extract --merge` and commit the result.
        "gettext.extract --check-up-to-date",
        "convention.check",
        "architecture.check",
        "credo --strict",
        # `--warnings-as-errors` here covers the `.exs` test files, which the
        # `compile` step above never sees: `elixirc_paths(:test)` is
        # `["lib", "test/support"]`, so a warning inside a test file passed every
        # gate. Three did, on this branch alone.
        "test --warnings-as-errors"
      ],
      dialyzer: ["dialyzer --format short"]
    ]
  end

  # Mix forwards CLI arguments only to the final alias entry. Keep preparation
  # and execution together so --include/--only reach the browser-mode selector.
  defp run_tests(args) do
    prepare_tests(args)
    Mix.Task.run("ecto.create", ["--quiet"])
    Mix.Task.run("ecto.migrate", ["--quiet"])
    Mix.Task.run("test", args)
  end

  defp prepare_tests(args) do
    e2e? = e2e_tests_requested?(args)
    System.put_env("STORYARN_E2E_TESTS", to_string(e2e?))

    if e2e?, do: Mix.Task.run("assets.build")
  end

  @doc false
  def e2e_tests_requested?(args) do
    {options, paths, _invalid} = OptionParser.parse(args, switches: [include: :keep, only: :keep])
    {paths, path_options} = ExUnit.Filters.parse_paths(paths)

    filters =
      options
      |> Enum.filter(fn {tag, _value} -> tag in [:include, :only] end)
      |> Enum.map(&elem(&1, 1))
      |> ExUnit.Filters.parse()
      |> Kernel.++(Keyword.get(path_options, :include, []))

    Enum.any?(filters, fn
      :e2e -> true
      {:e2e, value} -> value in [true, "true"]
      {:location, {path, _lines}} -> e2e_path?(path)
      {:location, path} -> e2e_path?(path)
      {:line, _line} -> paths == [] or Enum.any?(paths, &e2e_search_path?/1)
      _filter -> false
    end)
  end

  # A bare path keeps ExUnit's default exclusions. A location filter explicitly
  # includes its tests, even when their :e2e tag would otherwise exclude them.
  defp e2e_path?(path) do
    e2e_root = Path.join(__DIR__, "test/e2e")
    path = Path.expand(path)
    path == e2e_root or String.starts_with?(path, e2e_root <> "/")
  end

  # Line filters also apply to files discovered below a directory such as test/.
  defp e2e_search_path?(path) do
    e2e_root = Path.join(__DIR__, "test/e2e")
    path = Path.expand(path)

    e2e_path?(path) or (File.dir?(path) and String.starts_with?(e2e_root, path <> "/"))
  end
end
