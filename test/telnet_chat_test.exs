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

  test "multiple clients" do
    TelnetChat.start(nil, port: 4040)

    {:ok, max} = :ct_telnet_client.open('localhost', 4040, :telnet_conn)

    {:ok, prompt} = :ct_telnet_client.get_data(max)
    assert prompt == 'Username: '
    :ok = :ct_telnet_client.send_data(max, 'max')

    {:ok, prompt} = :ct_telnet_client.get_data(max)
    assert prompt == '> '

    {:ok, joe} = :ct_telnet_client.open('localhost', 4040, :telnet_conn)

    {:ok, prompt} = :ct_telnet_client.get_data(joe)
    assert prompt == 'Username: '
    :ok = :ct_telnet_client.send_data(joe, 'joe')

    {:ok, prompt} = :ct_telnet_client.get_data(joe)
    assert prompt == '> '

    :ok = :ct_telnet_client.send_data(max, 'hello!')
    {:ok, message} = :ct_telnet_client.get_data(max)
    assert message == 'max: hello!\n> '
    {:ok, message} = :ct_telnet_client.get_data(joe)
    assert message == 'max: hello!\n> '
  end
end
