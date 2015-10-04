defmodule TelnetChat do
  defmodule Forwarder do
    use GenEvent
    def handle_event({:join, pid, name}, parent) do
      if parent != pid do
        send parent, {:join, name}
        {:ok, parent}
      else
        {:ok, parent}
      end
    end

    def handle_event({:say, name, message}, parent) do
      send parent, {:say, name, message}
      {:ok, parent}
    end
  end

  defmodule Server do
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

    def init(:ok) do
      {:ok, manager} = GenEvent.start_link
      {:ok, %{manager: manager, names: HashDict.new}}
    end

    def handle_call({:join, name}, {pid, _}, state) do
      state = Dict.update!(state, :names, fn(names) -> names |> HashDict.put(pid, name) end)
      GenEvent.add_handler(state[:manager], {Forwarder, pid}, pid)
      GenEvent.sync_notify(state[:manager], {:join, pid, name})
      {:reply, :ok, state}
    end

    def handle_call({:say, message}, {pid, _}, state) do
      name = state[:names] |> HashDict.fetch!(pid)
      GenEvent.sync_notify(state[:manager], {:say, name, message})
      {:reply, :ok, state}
    end
  end

  use Application

  @doc false
  def start(_type, port: port) do
    import Supervisor.Spec

    children = [
      supervisor(Task.Supervisor, [[name: TelnetChat.TaskSupervisor]]),
      worker(Task, [TelnetChat, :accept, [port]]),
      worker(TelnetChat.Server, [[name: TelnetChat.ChatServer]])
    ]

    opts = [strategy: :one_for_one, name: TelnetChat.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Starts accepting connections on the given `port`.
  """
  def accept(port) do
    {:ok, socket} = :gen_tcp.listen(port,
                      [:binary, packet: :raw, active: false, reuseaddr: true])
    IO.puts "Accepting connections on port #{port}"
    loop_acceptor(socket)
  end

  defp loop_acceptor(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    {:ok, pid} = Task.Supervisor.start_child(TelnetChat.TaskSupervisor, fn -> serve(client) end)
    :ok = :gen_tcp.controlling_process(client, pid)
    loop_acceptor(socket)
  end

  defp serve(socket) do
    :gen_tcp.send(socket, "Username: ")
    {:ok, response} = :gen_tcp.recv(socket, 0)

    if response == <<255, 253, 3>> do
      {:ok, response} = :gen_tcp.recv(socket, 0)
    end

    name = ignore_telnet_stuff(response) |> String.strip

    TelnetChat.Server.join(TelnetChat.ChatServer, name)

    :gen_tcp.send(socket, <<255, 254, 1>>) # DONT ECHO
    :gen_tcp.send(socket, <<255, 251, 1>>) # WILL ECHO
    :gen_tcp.send(socket, <<255, 251, 3>>) # WILL SUPPRESS GO AHEAD
    :gen_tcp.send(socket, <<255, 254, 34>>) # DONT LINEMODE
    :gen_tcp.send(socket, <<255, 252, 34>>) # WONT LINEMODE
    :gen_tcp.send(socket, "> ")

    serve(socket, name)
  end

  def ignore_telnet_stuff(response) do
    case response do
      <<255, _, _>> <> rest -> rest
      msg -> msg
    end
  end

  defp clear(length) do
    "\r#{String.duplicate(" ", length)}"
  end

  defp serve(socket, name, buffer \\ "") do
    receive do
      {:join, name} -> :gen_tcp.send(socket, "#{clear(String.length(buffer) + 2)}\r#{name} joined.\r\n> #{buffer}")
      {:say, name, message} -> :gen_tcp.send(socket, "#{clear(String.length(buffer) + 2)}\r#{name}: #{message}\r\n> #{buffer}")
      _ -> nil
    after 0 -> nil
    end

    case :gen_tcp.recv(socket, 1, 0) do
      {:ok, "\r"} ->
        TelnetChat.Server.say(TelnetChat.ChatServer, buffer)
        buffer = ""
      {:ok, "\d"} -> # backspace
        buffer = buffer |> String.slice(0..-2)
        :gen_tcp.send(socket, "#{clear(String.length(buffer) + 3)}\r> #{buffer}")
      {:ok, <<27>>} -> # ignore next 2 bytes after escape
        :gen_tcp.recv(socket, 2)
      {:ok, char} ->
        if char > <<31>> && char < <<127>> do
          #IO.puts inspect char
          :gen_tcp.send(socket, char)
          buffer = buffer <> char
        end
      {:error, :timeout} -> nil
    end

    serve(socket, name, buffer |> ignore_telnet_stuff)
  end
end
