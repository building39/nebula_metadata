defmodule NebulaMetadata do
  use Application
  require Logger

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    # Define workers and child supervisors to be supervised
    Logger.debug("setting up our children")
    bucket_type = Application.get_env(:nebula_metadata, :riak_bucket_type)
    bucket_name = Application.get_env(:nebula_metadata, :riak_bucket_name)
    bucket = {bucket_type, bucket_name}

    state = %NebulaMetadata.State{
      host: Application.get_env(:nebula_metadata, :riak_serverip),
      port: Application.get_env(:nebula_metadata, :riak_serverport),
      bucket_type: bucket_type,
      bucket_name: bucket_name,
      bucket: bucket,
      cdmi_index: Application.get_env(:nebula_metadata, :riak_cdmi_index)
    }

    children = [
      worker(NebulaMetadata.Server, [state])
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    Logger.debug("setting up our opts")
    opts = [strategy: :one_for_one, name: NebulaMetadata.Supervisor]
    Logger.debug("starting our children")
    Supervisor.start_link(children, opts)
  end
end
