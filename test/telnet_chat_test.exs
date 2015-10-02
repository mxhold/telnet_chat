defmodule TelnetChatTest do
  use ExUnit.Case

  test "echo server" do
    TelnetChat.start(nil, port: 4040)

    {:ok, socket} = :gen_tcp.connect('localhost', 4040, [:binary, packet: :line, active: false, reuseaddr: true])

    :ok = :gen_tcp.send(socket, "hello\n")

    {:ok, data} = :gen_tcp.recv(socket, 0)

    assert data == "hello\n"
  end
end
