defmodule NebulaMetadata.Mixfile do
  use Mix.Project

  def project do
    [
      app: :nebula_metadata,
      version: "0.3.2",
      elixir: "~> 1.9",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      dialyzer: [
        plt_add_deps: true,
        remove_defaults: [:unknown],
        ignore_warnings: "dialyzer.ignore-warnings"
      ],
      deps: deps()
    ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [
      applications: [:logger, :riak, :poison, :memcache_client, :logger_file_backend],
      env: [
        riak_bucket_type: <<"cdmi">>,
        riak_bucket_name: <<"cdmi">>,
        riak_cdmi_index: <<"cdmi_idx">>,
        riak_serverip: "192.168.2.11",
        riak_serverport: 8087,
        name_prefix: "cdmi"
      ],
      mod: {NebulaMetadata, []}
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:logger_file_backend, "~> 0.0.11"},
      {:riak, "~> 1.1.6"},
      {:poison, "~> 4.0.1", override: true},
      {:dialyxir, "~> 0.5", only: [:dev], runtime: false},
      {:mock, "~> 0.3", only: :test},
      {:excoveralls, "~> 0.11", only: :test},
      {:memcache_client, "~> 1.1"}
      #     {:exrm, "~> 1.0"}
    ]
  end
end
