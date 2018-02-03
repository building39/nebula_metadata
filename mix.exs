defmodule NebulaMetadata.Mixfile do
  use Mix.Project

  def project do
    [app: :nebula_metadata,
     version: "0.3.0",
     elixir: "~> 1.6",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [:logger,
                    :riak,
                    :poison,
                    :memcache_client,
                    :logger_file_backend
                   ],
     env: [riak_bucket_type: <<"cdmi">>,
           riak_bucket_name: <<"cdmi">>,
           riak_cdmi_index: <<"cdmi_idx">>,
           riak_serverip: "192.168.69.64",
           riak_serverport: 8087,
           name_prefix: "cdmi"],
     mod: {NebulaMetadata, []}]
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
    [{:logger_file_backend, "~> 0.0"},
     {:riak, "~> 1.0"},
     {:poison, "~> 2.1.0"},
     {:memcache_client, git: "https://github.com/tsharju/memcache_client.git", tag: "v1.1.0"}
    ]
  end
end
