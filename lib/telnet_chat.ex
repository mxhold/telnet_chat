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

    def handle_event({:say, pid, name, message}, parent) do
      send parent, {:say, name, message}
      {:ok, parent}
    end
  end

  defmodule Server do
    use GenServer

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, :ok, opts)
    end

    def register(server, client_pid) do
      GenServer.call(server, {:register, client_pid})
    end

    def join(server, pid, name) do
      GenServer.call(server, {:join, pid, name})
    end

    def say(server, pid, name, message) do
      GenServer.call(server, {:say, pid, name, message})
    end

    def init(:ok) do
      {:ok, manager} = GenEvent.start_link
      {:ok, %{manager: manager}}
    end

    def handle_call({:register, client_pid}, _from, state) do
      GenEvent.add_handler(state[:manager], {Forwarder, client_pid}, client_pid)
      {:reply, :ok, state}
    end

    def handle_call({:join, pid, name}, _from, state) do
      GenEvent.sync_notify(state[:manager], {:join, pid, name})
      {:reply, :ok, state}
    end

    def handle_call({:say, pid, name, message}, _from, state) do
      GenEvent.sync_notify(state[:manager], {:say, pid, name, message})
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
    TelnetChat.Server.register(TelnetChat.ChatServer, pid)
    :ok = :gen_tcp.controlling_process(client, pid)
    loop_acceptor(socket)
  end

  defp serve(socket) do
    :gen_tcp.send(socket, "Username: ")
    {:ok, response} = :gen_tcp.recv(socket, 0)

    name = ignore_telnet_stuff(response) |> String.strip

    TelnetChat.Server.join(TelnetChat.ChatServer, self, name)

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

  defp serve(socket, name, buffer \\ "") do
    receive do
      {:join, name} -> :gen_tcp.send(socket, "\r#{name} joined.\r\n> #{buffer}")
      {:say, name, message} -> :gen_tcp.send(socket, "\r#{name}: #{message}\r\n> #{buffer}")
      _ -> nil
    after 0 -> nil
    end

    case :gen_tcp.recv(socket, 1, 10) do
      {:ok, "\r"} ->
        TelnetChat.Server.say(TelnetChat.ChatServer, self, name, buffer)
        buffer = ""
      {:ok, "\d"} ->
        buffer = buffer |> String.slice(0..-2)
        :gen_tcp.send(socket, "\r> #{buffer}")
      {:ok, char} ->
        IO.puts inspect char
        if char > <<31>> && char < <<127>> do
          :gen_tcp.send(socket, char)
        end
        buffer = buffer <> char
      {:error, :timeout} -> nil
    end

    serve(socket, name, buffer |> ignore_telnet_stuff)
  end
end
