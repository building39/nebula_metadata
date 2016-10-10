defmodule NebulaMetadata.Server do
  use GenServer
  require Logger
  import NebulaMetadata.State

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
  defp delete(key, state) do
    Riak.delete(state.bucket, key)
  end

  @spec get(charlist, map) :: {atom, map}
  defp get(key, state) do
    obj = Riak.find(state.bucket, key)
    case obj do
      nil -> {:not_found, key}
      _   -> {:ok, data} = Poison.decode(obj.data, keys: :atoms)
             {:ok, data.cdmi}
    end
  end

  @spec put(charlist, map, map) :: any
  defp put(key, data, state) when is_map(data) do
    {:ok, stringdata} = Poison.encode(data)
    put(key, stringdata, state)
  end
  @spec put(charlist, charlist, map) :: any
  defp put(key, data, state) when is_list(data) do
    obj = Riak.find(state.bucket, key)
    case obj do
      nil ->
        Riak.put(Riak.Object.create(bucket: state.bucket, key: key, data: data))
        {:ok, data}
      _ ->
        {:dupkey, key, data}
    end
  end

  @spec search(charlist, map) :: {atom, map}
  defp search(query, state) do
    {:ok, {:search_results, results, _score, count}} = Riak.Search.query(state.cdmi_index, query)
    case count do
      1 -> get_data(results, state)
      0 -> {:not_found, query}
      _ -> {:multiples, results, count}
    end
  end

  @spec update(charlist, map, map) :: any
  defp update(key, data, state) when is_map(data) do
    {:ok, stringdata} = Poison.encode(data)
    update(key, stringdata, state)
  end
  @spec update(charlist, map, map) :: any
  defp update(key, data, state) when is_list(data) do
    obj = Riak.find(state.bucket, key)
    case obj do
      nil -> {:not_found, nil}
      _ ->
        obj = %{obj | data: data}
        {:ok, Riak.put(obj).data}
    end
  end

  @spec get_data(list, list) :: {atom, map}
  defp get_data(results, state) do
    {_, rlist} = List.keyfind(results, state.cdmi_index, 0)
    {_, key} = List.keyfind(rlist, "_yz_rk", 0)
    get(key, state)
  end

end
