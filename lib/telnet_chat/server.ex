defmodule TelnetChat.Server do
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def join(server, name) do
    GenServer.call(server, {:join, name})
  end

  def say(server, message) do
    GenServer.call(server, {:say, message})
  end

  def part(server) do
    GenServer.call(server, :part)
  end

  def init(:ok) do
    {:ok, manager} = GenEvent.start_link
    {:ok, %{manager: manager, names: HashDict.new}}
  end

  def handle_call({:join, name}, {pid, _}, state) do
    names = state[:names] |> Dict.values
    state = Dict.update!(state, :names, fn(names) -> names |> HashDict.put(pid, name) end)
    GenEvent.add_handler(state[:manager], {TelnetChat.ChatEvents, pid}, pid)
    GenEvent.sync_notify(state[:manager], {:join, pid, name})
    {:reply, {:ok, names}, state}
  end

  def handle_call({:say, message}, {pid, _}, state) do
    name = state[:names] |> HashDict.fetch!(pid)
    GenEvent.sync_notify(state[:manager], {:say, name, message})
    {:reply, :ok, state}
  end

  def handle_call(:part, {pid, _}, state) do
    name = Dict.fetch!(state[:names], pid)
    state = Dict.update!(state, :names, fn(names) -> Dict.delete(names, pid) end)
    GenEvent.sync_notify(state[:manager], {:part, name})
    {:reply, :ok, state}
  end
end

