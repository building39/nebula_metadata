defmodule NebulaMetadata.Server do
  use GenServer
  require Logger
  import NebulaMetadata.State

  def start_link(state) do
    GenServer.start_link(__MODULE__, [state], [name: Metadata])
  end

  def init([state]) do
#    Logger.debug "Server init"
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

  defp delete(key, state) do
    Logger.debug("In delete")
    Riak.delete(state.bucket, key)
  end

  defp get(key, state) do
    obj = Riak.find(state.bucket, key)
    Logger.debug("Back from Riak.find")
    json = case obj do
             nil -> nil
             _ -> obj.data
    end
    {:ok, data} = Poison.decode(json, keys: :atoms)
    data
  end

  defp put(key, data, state) when is_map(data) do
    {:ok, stringdata} = Poison.encode(data)
    put(key, stringdata, state)
  end
  defp put(key, data, state) do
    obj = Riak.find(state.bucket, key)
    case obj do
      nil ->
        Riak.put(Riak.Object.create(bucket: state.bucket, key: key, data: data))
        {:ok, data}
      _ ->
        {:dupkey, key, data}
    end
  end

  defp search(query, state) do
    Logger.debug("In search")
    {:ok, {:search_results, results, _score, count}} = Riak.Search.query(state.cdmi_index, query)
    case count do
      1 -> get_data(results, state)
      0 -> {:notfound, query}
      _ -> {:multiples, results, count}
    end

  end

  defp update(key, data, state) do
    Logger.debug("In update")
    obj = Riak.find(state.bucket, key)
    case obj do
      nil -> {:notfound, nil}
      _ ->
        obj = %{obj | data: data}
        {:ok, Riak.put(obj).data}
    end
  end

  def get_data(results, state) do
    {_, rlist} = List.keyfind(results, state.cdmi_index, 0)
    {_, key} = List.keyfind(rlist, "_yz_rk", 0)
    get(key, state)
  end

end
