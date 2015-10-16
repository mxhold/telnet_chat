defmodule ChatEventsTest do
  use ExUnit.Case

  setup do
    {:ok, manager} = GenEvent.start_link

    {:ok, %{manager: manager}}
  end

  test "join notifies everyone except provided pid", %{manager: manager} do
    test_pid = self()

    pid1 = spawn fn ->
      receive do
        msg -> send test_pid, {self(), msg}
      end
    end

    pid2 = spawn fn ->
      receive do
        msg -> send test_pid, {self(), msg}
      end
    end

    :ok = GenEvent.add_handler(manager, {TelnetChat.ChatEvents, pid1}, pid1)
    :ok = GenEvent.add_handler(manager, {TelnetChat.ChatEvents, pid2}, pid2)

    GenEvent.sync_notify(manager, {:join, pid1, "joe"})

    refute_receive {^pid1, {:join, "joe"}}
    assert_receive {^pid2, {:join, "joe"}}
  end

  test "say notifies everyone", %{manager: manager} do
    test_pid = self()

    pid1 = spawn fn ->
      receive do
        msg -> send test_pid, {self(), msg}
      end
    end

    pid2 = spawn fn ->
      receive do
        msg -> send test_pid, {self(), msg}
      end
    end

    :ok = GenEvent.add_handler(manager, {TelnetChat.ChatEvents, pid1}, pid1)
    :ok = GenEvent.add_handler(manager, {TelnetChat.ChatEvents, pid2}, pid2)

    GenEvent.sync_notify(manager, {:say, "joe", "hello"})

    assert_receive {^pid1, {:say, "joe", "hello"}}
    assert_receive {^pid2, {:say, "joe", "hello"}}
  end

  test "part notifies everyone", %{manager: manager} do
    test_pid = self()

    pid1 = spawn fn ->
      receive do
        msg -> send test_pid, {self(), msg}
      end
    end

    pid2 = spawn fn ->
      receive do
        msg -> send test_pid, {self(), msg}
      end
    end

    :ok = GenEvent.add_handler(manager, {TelnetChat.ChatEvents, pid1}, pid1)
    :ok = GenEvent.add_handler(manager, {TelnetChat.ChatEvents, pid2}, pid2)

    GenEvent.sync_notify(manager, {:part, "joe"})

    assert_receive {^pid1, {:part, "joe"}}
    assert_receive {^pid2, {:part, "joe"}}
  end
end
