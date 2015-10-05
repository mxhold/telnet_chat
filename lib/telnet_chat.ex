defmodule TelnetChat do
  require Logger

  defmodule ChatEvents do
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

    def handle_event({:part, name}, parent) do
      send parent, {:part, name}
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

    def part(server) do
      GenServer.call(server, :part)
    end

    def init(:ok) do
      {:ok, manager} = GenEvent.start_link
      {:ok, %{manager: manager, names: HashDict.new}}
    end

    def handle_call({:join, name}, {pid, _}, state) do
      state = Dict.update!(state, :names, fn(names) -> names |> HashDict.put(pid, name) end)
      GenEvent.add_handler(state[:manager], {ChatEvents, pid}, pid)
      GenEvent.sync_notify(state[:manager], {:join, pid, name})
      {:reply, :ok, state}
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
    {:ok, socket} = :gen_tcp.listen(port, [:binary, packet: :raw, active: false, reuseaddr: true])
    Logger.info "Accepting connections on port #{port}"
    loop_acceptor(socket)
  end

  defp loop_acceptor(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    {:ok, pid} = Task.Supervisor.start_child(TelnetChat.TaskSupervisor, fn ->
      Logger.metadata(ip: ip(client))
      Logger.debug "connection open"
      try do
        serve(client)
      catch
        :exit, "closed" -> Logger.debug "connection closed"
      end
    end)
    :ok = :gen_tcp.controlling_process(client, pid)
    loop_acceptor(socket)
  end

  # Telnet codes

  @tn_ECHO <<1>>
  @tn_SUPPRESS_GO_AHEAD <<3>>
  @tn_LINEMODE <<34>>

  @tn_WILL <<251>>
  @tn_WONT <<252>>
  @tn_DO <<253>>
  @tn_DONT <<254>>

  @tn_IAC <<255>>

  defp serve(socket) do
    :gen_tcp.send(socket, "Username: ")
    {:ok, response} = :gen_tcp.recv(socket, 0)

    if response == @tn_IAC <> @tn_DO <> @tn_SUPPRESS_GO_AHEAD do
      {:ok, response} = :gen_tcp.recv(socket, 0)
    end

    name = ignore_telnet_stuff(response) |> String.strip

    TelnetChat.Server.join(TelnetChat.ChatServer, name)
    Logger.info "#{name} joined."

    turn_on_character_mode(socket)

    :gen_tcp.send(socket, "> ")

    serve(socket, name)
  end

  def ignore_telnet_stuff(response) do
    case response do
      @tn_IAC <> <<_, _>> <> rest -> rest
      msg -> msg
    end
  end

  defp turn_on_character_mode(socket) do
    :gen_tcp.send(socket, @tn_IAC <> @tn_DONT <> @tn_ECHO)
    :gen_tcp.send(socket, @tn_IAC <> @tn_WILL <> @tn_ECHO)
    :gen_tcp.send(socket, @tn_IAC <> @tn_WILL <> @tn_SUPPRESS_GO_AHEAD)
    :gen_tcp.send(socket, @tn_IAC <> @tn_DONT <> @tn_LINEMODE)
    :gen_tcp.send(socket, @tn_IAC <> @tn_WONT <> @tn_LINEMODE)
  end

  defp clear(length) do
    "\r#{String.duplicate(" ", length)}"
  end

  defp send_and_reprint_buffer(socket, buffer, message) do
    :gen_tcp.send(socket, "#{clear(String.length(buffer) + 3)}\r#{message}> #{buffer}")
  end

  defp serve(socket, name, buffer \\ "") do
    receive do
      {:join, name}         -> send_and_reprint_buffer(socket, buffer, "#{name} joined.\r\n")
      {:say, name, message} -> send_and_reprint_buffer(socket, buffer, "#{name}: #{message}\r\n")
      {:part, name}         -> send_and_reprint_buffer(socket, buffer, "#{name} left.\r\n")
      _ -> nil
    after 0 -> nil
    end

    case :gen_tcp.recv(socket, 1, 0) do
      {:ok, "\r"} ->
        Logger.info "#{name}: #{buffer}"
        TelnetChat.Server.say(TelnetChat.ChatServer, buffer)
        buffer = ""
      {:ok, "\d"} -> # backspace
        buffer = String.slice(buffer, 0..-2)
        send_and_reprint_buffer(socket, buffer, "")
      {:ok, <<27>>} -> # ignore next 2 bytes after escape
        {:ok, ignored_bytes} = :gen_tcp.recv(socket, 2)
        Logger.warn "Ignored escaped bytes: #{inspect ignored_bytes}"
      {:ok, char} ->
        if char > <<31>> && char < <<127>> do
          Logger.debug inspect(char)
          :gen_tcp.send(socket, char)
          buffer = buffer <> char
        end
      {:error, :timeout} -> nil
      {:error, :closed} ->
        Logger.info "#{name} left."
        TelnetChat.Server.part(TelnetChat.ChatServer)
        exit("closed")
    end

    serve(socket, name, buffer |> ignore_telnet_stuff)
  end

  def ip(socket) do
    {:ok, {ip, _}} = :inet.peername(socket)
    ip |> Tuple.to_list |> Enum.join(".")
  end
end
