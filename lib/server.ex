defmodule NebulaMetadata.Server do
  use GenServer
  require Logger
  import NebulaMetadata.State
  import Memcache.Client

  def start_link(state) do
    GenServer.start_link(__MODULE__, [state], name: Metadata)
  end

  def init([state]) do
    {:ok, state}
  end

  def handle_call(:available, _from, state) do
    Logger.debug("handle_call: :available")
    {:reply, Riak.ping(), state}
  end

  def handle_call({:delete, key}, _from, state) do
    Logger.debug("handle_call: :delete")
    {:reply, delete(key, state), state}
  end

  def handle_call({:get, key}, _from, state) do
    Logger.debug("handle_call: :get")
    {:reply, get(key, state), state}
  end

  def handle_call({:put, key, data}, _from, state) do
    Logger.debug("handle_call: :put")
    {:reply, put(key, data, state), state}
  end

  def handle_call({:search, query}, _from, state) do
    Logger.debug("handle_call: :search")
    s = search(query, state)
    Logger.debug("Search returned: #{inspect(s, pretty: true)}")
    {:reply, s, state}
    # {:reply, search(query, state), state}
  end

  def handle_call({:update, key, data}, _from, state) do
    Logger.debug("handle_call: :update")
    {:reply, update(key, data, state), state}
  end

  def handle_call(request, _from, state) do
    Logger.debug("handle_call: unknown request: #{inspect(request)}")
    {:reply, {:badrequest, request}, state}
  end

  @spec delete(String.t(), map()) :: map()
  defp delete(id, state) do
    {rc, obj} = get(id, state)

    case rc do
      :ok ->
        response = Memcache.Client.get(id)

        if response.status == :ok do
          {:ok, obj} = :erlang.binary_to_term(response.value)
          Memcache.Client.delete(id)
          hash = get_domain_hash(obj.domainURI)
          Logger.debug("setting parentURI")
          query = "sp:" <> hash <> obj.parentURI <> obj.objectName
          Memcache.Client.delete(query)
        end

        # key (id) needs to be reversed for Riak datastore.
        key = String.slice(id, -16..-1) <> String.slice(id, 0..31)
        Riak.delete(state.bucket, key)

      _other ->
        {:not_found, id}
    end
  end

  @spec get(String.t(), map(), boolean()) :: {atom(), map()}
  defp get(id, state, flip \\ true) do
    # Logger.debug("metadata get key #{inspect id}")
    response = Memcache.Client.get(id)

    case response.status do
      :ok ->
        {:ok, obj} = :erlang.binary_to_term(response.value)
        Logger.debug("memcache response: #{inspect(obj)}")
        obj

      _status ->
        key =
          if flip do
            # key (id) needs to be reversed for Riak datastore.
            String.slice(id, -16..-1) <> String.slice(id, 0..31)
          else
            id
          end

        # Logger.debug("Finding key #{inspect key}")
        obj = Riak.find(state.bucket, key)

        case obj do
          nil ->
            # Logger.debug("Get not found")
            {:not_found, key}

          _ ->
            {:ok, data} = Poison.decode(obj.data, keys: :atoms)
            Memcache.Client.set("sp:" <> data.sp, data.cdmi)
            Memcache.Client.set(data.cdmi.objectID, data.cdmi)

            Logger.debug(
              "Set memcached key #{inspect("sp:" <> data.sp)} to #{
                inspect(data.cdmi, pretty: true)
              }"
            )

            Logger.debug(
              "Set memcached key #{inspect(data.cdmi.objectID)} to #{
                inspect(data.cdmi, pretty: true)
              }"
            )

            {:ok, data.cdmi}
        end
    end
  end

  @spec put(String.t(), map(), map()) :: tuple()
  defp put(id, data, state) when is_map(data) do
    Logger.debug("metadata put key #{inspect(id)}")
    Logger.debug("metadata put data #{inspect(data)}")
    # key (id) needs to be reversed for Riak datastore.
    key = String.slice(id, -16..-1) <> String.slice(id, 0..31)
    new_data = wrap_object(data)
    Logger.debug("new_data: #{inspect(new_data)}")
    {:ok, stringdata} = Poison.encode(new_data)
    {rc, _} = put(key, stringdata, state)

    if rc == :ok do
      Logger.debug("Data is #{inspect(new_data)}")
      Logger.debug("ID is #{inspect(id)}")
      Memcache.Client.set(id, data)
      Memcache.Client.set(new_data.sp, data)
      Logger.debug(
        "Set memcached key #{inspect(new_data.sp)} to #{inspect(data, pretty: true)}"
      )

      Logger.debug("Set memcached key #{inspect(id)} to #{inspect(data, pretty: true)}")
      # Logger.debug("PUT memcache set: #{inspect r}")
    else
      Logger.debug("PUT failed: #{inspect(rc)}")
    end

    {rc, new_data}
  end

  @spec put(String.t(), String.t(), map()) :: {:ok | :dupkey, any(), any()}
  defp put(key, data, state) when is_binary(data) do
    obj = Riak.find(state.bucket, key)

    case obj do
      nil ->
        Riak.put(Riak.Object.create(bucket: state.bucket, key: key, data: data))
        {:ok, data}

      _error ->
        # Logger.debug("PUT find failed: #{inspect error}")
        {:dupkey, key, data}
    end
  end

  @spec search(String.t(), map()) :: {atom(), map()}
  defp search(query, state) do
    Logger.debug("Searching for #{inspect(query)}")
    response = Memcache.Client.get(query)

    case response.status do
      :ok ->
        obj = :erlang.binary_to_term(response.value)
        Logger.debug(fn -> "cache hit on data: #{inspect(obj)}" end)
        {:ok, obj}

      _status ->
        Logger.debug("Cache miss")
        {:ok, {:search_results, results, _score, count}} =
          Riak.Search.query(state.cdmi_index, query)

        case count do
          1 ->
            {:ok, data} = get_data(results, state)
            Logger.debug(fn -> "got data: #{inspect(data)}" end)
            Memcache.Client.set(query, data)
            Memcache.Client.set(data.objectID, data)

            Logger.debug("Set memcached key #{inspect(query)} to #{inspect(data, pretty: true)}")

            Logger.debug(
              "Set memcached key #{inspect(data.objectID)} to #{inspect(data, pretty: true)}"
            )

            {:ok, data}

          0 ->
            Logger.debug("Search not found: #{inspect(query)}")
            {:not_found, query}

          _ ->
            Logger.debug("Multiple results found")
            {:multiples, results, count}
        end
    end
  end

  @spec get_data(list(), map()) :: {atom(), map()}
  defp get_data(results, state) do
    {_, rlist} = List.keyfind(results, state.cdmi_index, 0)
    {_, key} = List.keyfind(rlist, "_yz_rk", 0)
    get(key, state, false)
  end

  @spec update(String.t(), map(), map()) :: any()
  defp update(id, data, state) when is_map(data) do
    Logger.debug("Update key: #{inspect(id)}")
    Logger.debug("Update data: #{inspect(data, pretty: true)}")
    # key (id) needs to be reversed for Riak datastore.
    key = String.slice(id, -16..-1) <> String.slice(id, 0..31)
    Logger.debug(fn -> "Key: #{inspect(key)}" end)
    new_data = wrap_object(data)
    Logger.debug("wrapped data: #{inspect(new_data, pretty: true)}")
    {:ok, stringdata} = Poison.encode(new_data)
    Logger.debug("JSON data: #{inspect(stringdata)}")
    {rc, _} = update(key, stringdata, state)

    if rc == :ok do
      Logger.debug("update ok")
      hash = get_domain_hash(data.domainURI)

      query =
        if Map.has_key?(data, :parentURI) do
          "sp:" <> hash <> data.parentURI <> data.objectName
        else
          # Must be the root container
          "sp:" <> hash <> data.objectName
        end

      Memcache.Client.set(query, data)
      Memcache.Client.set(id, data)
      Logger.debug("Set memcached key #{inspect(id)} to #{inspect(data, pretty: true)}")
      Logger.debug("Set memcached key #{inspect(query)} to #{inspect(data, pretty: true)}")
    else
      Logger.debug("Update failed: #{inspect(rc)}")
    end

    Logger.debug("update returning #{inspect({rc, new_data.cdmi})}")
    {rc, new_data.cdmi}
  end

  @spec update(String.t(), String.t(), map()) :: any()
  defp update(key, data, state) do
    Logger.debug("updating with string data: #{inspect(data)}")
    obj = Riak.find(state.bucket, key)

    case obj do
      nil ->
        # Logger.debug("Update not found")
        {:not_found, nil}

      _ ->
        obj = %{obj | data: data}
        {:ok, Riak.put(obj).data}
    end
  end

  @doc """
  Calculate a hash for a domain.
  """
  @spec get_domain_hash(binary()) :: binary()
  # def get_domain_hash(domain) when is_list(domain) do
  # Logger.debug("get_domain_hash 1 for #{inspect domain}")
  #   get_domain_hash(<<domain>>)
  # end
  def get_domain_hash(domain) when is_binary(domain) do
    Logger.debug("get_domain_hash 2 for #{inspect(domain)}")

    :crypto.hmac(:sha, <<"domain">>, domain)
    |> Base.encode16()
    |> String.downcase()
  end

  @spec wrap_object(map()) :: map()
  defp wrap_object(data) do
    Logger.debug("Object: #{inspect(data, pretty: true)}")
    Logger.debug("Object Name: #{inspect(data.objectName)}")

    domain =
      if data.objectName == "/" do
        "/cdmi_domains/system_domain/"
      else
        Map.get(data, :domainURI, "/cdmi_domains/system_domain/")
      end

    Logger.debug("Domain: #{inspect(domain, pretty: true)}")
    hash = get_domain_hash(domain)

    sp =
      if Map.has_key?(data, :parentURI) do
        hash <> data.parentURI <> data.objectName
      else
        # must be the root container
        hash <> data.objectName
      end

    %{
      sp: sp,
      cdmi: data
    }

    # data
  end
end
