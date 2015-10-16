defmodule TelnetChat.ChatEvents do
  use GenEvent

  def handle_event({:join, pid, name}, parent) do
    if parent != pid do
      send parent, {:join, name}
    end
    {:ok, parent}
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
