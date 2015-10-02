defmodule TelnetChatTest do
  use ExUnit.Case

  test "echo server" do
    TelnetChat.start(nil, port: 4040)

    {:ok, pid} = :ct_telnet_client.open('localhost', 4040, :telnet_conn)

    {:ok, prompt} = :ct_telnet_client.get_data(pid)

    assert prompt == 'Username: '

    :ok = :ct_telnet_client.send_data(pid, 'max')

    {:ok, prompt} = :ct_telnet_client.get_data(pid)

    assert prompt == '> '

    :ok = :ct_telnet_client.send_data(pid, 'hello!')

    {:ok, prompt} = :ct_telnet_client.get_data(pid)

    assert prompt == 'max: hello!\n> '
  end
end
