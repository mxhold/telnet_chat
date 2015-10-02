defmodule TelnetChatTest do
  use ExUnit.Case

  test "echo server" do
    TelnetChat.start(nil, port: 4040)

    {:ok, pid} = :ct_telnet_client.open('localhost', 4040, :telnet_conn)

    :ct_telnet_client.send_data(pid, 'hello!')

    {:ok, response} = :ct_telnet_client.get_data(pid)

    assert response == 'hello!\n'
  end
end
