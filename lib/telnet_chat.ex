defmodule TelnetChat do
  require Logger
  use Application

  @manager_name TelnetChat.EventManager

  @doc false
  def start(_type, port: port) do
    import Supervisor.Spec

    children = [
      worker(GenEvent, [[name: @manager_name]]),
      worker(TelnetChat.Server, [@manager_name, [name: TelnetChat.ChatServer]]),
      supervisor(Task.Supervisor, [[name: TelnetChat.TaskSupervisor]]),
      worker(Task, [TelnetChat, :accept, [port]]),
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
        TelnetChat.Client.serve(client)
      catch
        :exit, :normal -> Logger.debug "connection closed"
      end
    end)
    :ok = :gen_tcp.controlling_process(client, pid)
    loop_acceptor(socket)
  end

  defp ip(socket) do
    {:ok, {ip, _}} = :inet.peername(socket)
    ip |> Tuple.to_list |> Enum.join(".")
  end
end
