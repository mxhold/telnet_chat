defmodule TelnetChat do
  use Application

  @doc false
  def start(_type, port: port) do
    import Supervisor.Spec

    children = [
      supervisor(Task.Supervisor, [[name: TelnetChat.TaskSupervisor]]),
      worker(Task, [TelnetChat, :accept, [port]])
    ]

    opts = [strategy: :one_for_one, name: TelnetChat.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Starts accepting connections on the given `port`.
  """
  def accept(port) do
    {:ok, socket} = :gen_tcp.listen(port,
                      [:binary, packet: :line, active: false, reuseaddr: true])
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

    name = ignore_telnet_stuff(response) |> String.strip

    serve(socket, name)
  end

  def ignore_telnet_stuff(response) do
    res = case response do
      <<255, 253, _>> <> rest -> rest
      msg -> msg
    end

    res
  end

  defp serve(socket, name) do
    :gen_tcp.send(socket, "> ")
    {:ok, line} = :gen_tcp.recv(socket, 0)

    :gen_tcp.send(socket, "#{name}: #{line}")

    serve(socket, name)
  end
end
