defmodule TelnetChatTest do
  use ExUnit.Case

  test "chat works" do
    TelnetChat.start(nil, port: 4040)

    {:ok, max} = :ct_telnet_client.open('localhost', 4040, :telnet_conn)

    {:ok, prompt} = :ct_telnet_client.get_data(max)
    assert prompt == 'Username: '
    :ok = :ct_telnet_client.send_data(max, 'max')

    {:ok, prompt} = :ct_telnet_client.get_data(max)
    assert prompt == '> '

    # start typing so we check that the join message overwrites and then
    # reprints the current line
    :ok = :ct_telnet_client.send_data(max, 'hello this is my message', false)

    {:ok, joe} = :ct_telnet_client.open('localhost', 4040, :telnet_conn)

    {:ok, prompt} = :ct_telnet_client.get_data(joe)
    assert prompt == 'Username: '
    :ok = :ct_telnet_client.send_data(joe, 'joe')

    {:ok, prompt} = :ct_telnet_client.get_data(joe)
    assert prompt == '> '

    {:ok, message} = :ct_telnet_client.get_data(max)
    assert message == 'hello this is my message\r                          \rjoe joined.\r\n> hello this is my message'

    {:ok, alan} = :ct_telnet_client.open('localhost', 4040, :telnet_conn)

    {:ok, prompt} = :ct_telnet_client.get_data(alan)
    assert prompt == 'Username: '
    :ok = :ct_telnet_client.send_data(alan, 'alan')

    {:ok, prompt} = :ct_telnet_client.get_data(alan)
    assert prompt == '> '

    {:ok, message} = :ct_telnet_client.get_data(max)
    assert message == '\r                          \ralan joined.\r\n> hello this is my message'

    {:ok, message} = :ct_telnet_client.get_data(joe)
    assert message == '\r  \ralan joined.\r\n> '

    :ok = :ct_telnet_client.send_data(max, '\r\n', false)

    {:ok, message} = :ct_telnet_client.get_data(max)
    assert message == '\r  \rmax: hello this is my message\r\n> '

    {:ok, message} = :ct_telnet_client.get_data(joe)
    assert message == '\r  \rmax: hello this is my message\r\n> '

    {:ok, message} = :ct_telnet_client.get_data(alan)
    assert message == '\r  \rmax: hello this is my message\r\n> '
  end
end
