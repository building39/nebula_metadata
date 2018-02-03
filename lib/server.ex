defmodule NebulaMetadata.Server do
  use GenServer
  require Logger
  import NebulaMetadata.State
  import Memcache.Client

  def start_link(state) do
    GenServer.start_link(__MODULE__, [state], [name: Metadata])
  end

  def init([state]) do
    {:ok, state}
  end

  def handle_call(:available, _from, state) do
    {:reply, Riak.ping(), state}
  end
  def handle_call({:delete, key}, _from, state) do
    {:reply, delete(key, state), state}
  end
  def handle_call({:get, key}, _from, state) do
    {:reply, get(key, state), state}
  end
  def handle_call({:put, key, data}, _from, state) do
    {:reply, put(key, data, state), state}
  end
  def handle_call({:search, query}, _from, state) do
    {:reply, search(query, state), state}
  end
  def handle_call({:update, key, data}, _from, state) do
    {:reply, update(key, data, state), state}
  end
  def handle_call(request, _from, state) do
    {:reply, {:badrequest, request}, state}
  end

  @spec delete(charlist, map) :: any
  defp delete(id, state) do
    #Logger.debug("Deleting key: #{inspect id}")
    {rc, obj} = get(id, state)
    #Logger.debug("Delete rc: #{inspect rc} obj: #{inspect obj}")
    case rc do
      :ok ->
        response = Memcache.Client.get(id)
        #Logger.debug("Delete cache hit: #{inspect response.value}")
        if response.status == :ok do
          {:ok, obj} = response.value
          #Logger.debug("Delete got a hit cache")
          #Logger.debug("Deleting #{inspect id} from cache")
          r = Memcache.Client.delete(id)
          #Logger.debug("memcache response: #{inspect r}")
          hash = get_domain_hash(obj.domainURI)
          query = "sp:" <> hash <> obj.parentURI <> obj.objectName
          #Logger.debug("Deleting #{inspect query} from cache")
          r = Memcache.Client.delete(query)
          #Logger.debug("memcache delete result: #{inspect r}")
        end
        #Logger.debug("Now deleting from riak")
        # key (id) needs to be reversed for Riak datastore.
        key = String.slice(id, -32..-1) <> String.slice(id, 0..15)
        Riak.delete(state.bucket, key)
      _other ->
        #Logger.debug("delete not found")
        {:not_found, id}
    end
  end

  @spec get(charlist, map, boolean) :: {atom, map}
  defp get(id, state, flip \\ true) do
    #Logger.debug("metadata get key #{inspect id}")
    response = Memcache.Client.get(id)
    case response.status do
      :ok ->
        #Logger.debug("memcache response: #{inspect response.value}")
        response.value
      _status ->
        key = if flip do
          # key (id) needs to be reversed for Riak datastore.
          key = String.slice(id, -32..-1) <> String.slice(id, 0..15)
        else
          id
        end
        #Logger.debug("Finding key #{inspect key}")
        obj = Riak.find(state.bucket, key)
        case obj do
          nil ->
            #Logger.debug("Get not found")
            {:not_found, key}
          _   ->
            {:ok, data} = Poison.decode(obj.data, keys: :atoms)
            Memcache.Client.set("sp:" <> data.sp, {:ok, data.cdmi})
            Memcache.Client.set(data.cdmi.objectID, {:ok, data.cdmi})
            {:ok, data.cdmi}
        end
    end
  end

  @spec put(charlist, map, map) :: any
  defp put(id, data, state) when is_map(data) do
    Logger.debug("metadata put key #{inspect id}")
    # key (id) needs to be reversed for Riak datastore.
    key = String.slice(id, -32..-1) <> String.slice(id, 0..15)
    {:ok, stringdata} = Poison.encode(wrap_object(data))
    {rc, _} = put(key, stringdata, state)
    if rc == :ok do
      Logger.debug(fn -> "Data is #{inspect data}" end)
      Logger.debug(fn -> "ID is #{inspect id}" end)
      Memcache.Client.set(id, {:ok, data})
      Memcache.Client.set(data.sp, {:ok, data})
      #Logger.debug("PUT memcache set: #{inspect r}")
    else
      #Logger.debug("PUT failed: #{inspect rc}")
    end
    {rc, data}
  end
  @spec put(charlist, charlist, map) :: any
  defp put(key, data, state) when is_binary(data) do
    obj = Riak.find(state.bucket, key)
    case obj do
      nil ->
        Riak.put(Riak.Object.create(bucket: state.bucket, key: key, data: data))
        {:ok, data}
      error ->
        #Logger.debug("PUT find failed: #{inspect error}")
        {:dupkey, key, data}
    end
  end

  @spec search(charlist, map) :: {atom, map}
  defp search(query, state) do
    Logger.debug("Searching for #{inspect query}")
    response = Memcache.Client.get(query)
    case response.status do
      :ok ->
        Logger.debug(fn -> "cache hit on data: #{inspect response}" end)
        response.value
      _status ->
        {:ok, {:search_results, results, _score, count}} = Riak.Search.query(state.cdmi_index, query)
        case count do
          1 ->
            {:ok, data} = get_data(results, state)
            Logger.debug(fn -> "got data: #{inspect data}" end)
            Memcache.Client.set(query, {:ok, data})
            Memcache.Client.set(data.objectID, {:ok, data})
            {:ok, data}
          0 ->
            Logger.debug("Search not found: #{inspect query}")
            {:not_found, query}
          _ ->
            Logger.debug("Multiple results found")
            {:multiples, results, count}
        end
    end
  end
  @spec get_data(list, list) :: {atom, map}
  defp get_data(results, state) do
    {_, rlist} = List.keyfind(results, state.cdmi_index, 0)
    {_, key} = List.keyfind(rlist, "_yz_rk", 0)
    get(key, state, false)
  end

  @spec update(charlist, map, map) :: any
  defp update(id, data, state) when is_map(data) do
    #Logger.debug("Update key: #{inspect id}")
    # key (id) needs to be reversed for Riak datastore.
    key = String.slice(id, -32..-1) <> String.slice(id, 0..15)
    {:ok, stringdata} = Poison.encode(wrap_object(data))
    {rc, _} = update(key, stringdata, state)
    if rc == :ok do
      Memcache.Client.set(id, {:ok, data})
      hash = get_domain_hash(data.domainURI)
      if Map.has_key?(data, :parentURI) do
        query = "sp:" <> hash <> data.parentURI <> data.objectName
      else
        # Must be the root container
        query = "sp:" <> hash <> data.objectName
      end
      r = Memcache.Client.set(query, {:ok, data})
      #Logger.debug("Update memcache set: #{inspect r}")
    else
      #Logger.debug("Update failed: #{inspect rc}")
    end
    {rc, data}
  end
  @spec update(charlist, map, map) :: any
  defp update(key, data, state) when is_binary(data) do
    obj = Riak.find(state.bucket, key)
    case obj do
      nil ->
        #Logger.debug("Update not found")
        {:not_found, nil}
      _ ->
        obj = %{obj | data: data}
        {:ok, Riak.put(obj).data}
    end
  end

  @doc """
  Calculate a hash for a domain.
  """
  @spec get_domain_hash(charlist) :: charlist
  def get_domain_hash(domain) when is_list(domain) do
    #Logger.debug("get_domain_hash 1 for #{inspect domain}")
    get_domain_hash(<<domain>>)
  end
  @spec get_domain_hash(binary) :: charlist
  def get_domain_hash(domain) when is_binary(domain) do
    #Logger.debug("get_domain_hash 2 for #{inspect domain}")
    :crypto.hmac(:sha, <<"domain">>, domain)
    |> Base.encode16
    |> String.downcase
  end

  @spec wrap_object(map) :: map
  defp wrap_object(data) do
    # domain = Map.get(data, :domainURI, "/cdmi_domains/system_domain/")
    # hash = get_domain_hash(domain)
    # sp = if Map.has_key?(data, :parentURI) do
    #   hash <> data.parentURI <> data.objectName
    # else
    #   # must be the root container
    #   hash <> data.objectName
    # end
    # %{
    #   sp: sp,
    #   cdmi: data
    # }
    data
  end

end
