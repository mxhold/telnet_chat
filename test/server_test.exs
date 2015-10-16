defmodule ServerTest do
  use ExUnit.Case

  defmodule Forwarder do
    use GenEvent

    def handle_event(event, parent) do
      send parent, event
      {:ok, parent}
    end
  end

  setup do
    {:ok, manager} = GenEvent.start_link
    {:ok, server} = TelnetChat.Server.start_link(manager)

    GenEvent.add_mon_handler(manager, Forwarder, self())
    {:ok, server: server}
  end

  test "joining", %{server: server} do
    test_pid = self()

    pid = spawn fn ->
      {:ok, names} = TelnetChat.Server.join(server, "joe")
      send test_pid, {:names, names}
    end

    assert_receive {:join, ^pid, "joe"}
    assert_receive {:names, []}

    pid = spawn fn ->
      {:ok, names} = TelnetChat.Server.join(server, "rob")
      send test_pid, {:names, names}
    end

    assert_receive {:join, ^pid, "rob"}
    assert_receive {:names, ["joe"]}

    pid = spawn fn ->
      {:ok, names} = TelnetChat.Server.join(server, "mike")
      send test_pid, {:names, names}
    end

    assert_receive {:join, ^pid, "mike"}
    assert_receive {:names, ["joe", "rob"]}
  end

  test "saying", %{server: server} do
    {:ok, _names} = TelnetChat.Server.join(server, "tester")

    TelnetChat.Server.say(server, "hello!")

    assert_receive {:say, "tester", "hello!"}
  end

  test "parting", %{server: server} do
    {:ok, _names} = TelnetChat.Server.join(server, "tester")

    pid = spawn fn ->
      {:ok, _names} = TelnetChat.Server.join(server, "rob")
      TelnetChat.Server.part(server)
    end

    assert_receive {:part, "rob"}

    test_pid = self()

    pid = spawn fn ->
      {:ok, names} = TelnetChat.Server.join(server, "mike")
      send test_pid, {:names, names}
    end

    assert_receive {:names, ["tester"]}
  end
end
