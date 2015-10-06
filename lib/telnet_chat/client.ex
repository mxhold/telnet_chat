defmodule TelnetChat.Client do
  require Logger

  @telnet_ECHO <<1>>
  @telnet_SUPPRESS_GO_AHEAD <<3>>
  @telnet_LINEMODE <<34>>

  @telnet_WILL <<251>>
  @telnet_WONT <<252>>
  @telnet_DO <<253>>
  @telnet_DONT <<254>>

  @telnet_IAC <<255>>

  def serve(socket) do
    :gen_tcp.send(socket, "Name: ")
    {:ok, response} = :gen_tcp.recv(socket, 0)

    if response == @telnet_IAC <> @telnet_DO <> @telnet_SUPPRESS_GO_AHEAD do
      {:ok, response} = :gen_tcp.recv(socket, 0)
    end

    name = ignore_telnet_stuff(response) |> String.replace(~r/[^A-Za-z]/, "")

    {:ok, names} = TelnetChat.Server.join(TelnetChat.ChatServer, name)
    Logger.info "#{name} joined."

    message = case names do
      [] -> "You are alone."
      [name] -> "There is one other person here: #{name}."
      [a,b] -> "There are 2 other people here: #{a} and #{b}."
      [a|b] -> "There are #{Dict.size names} other people here: #{Enum.join(b, ", ")}, and #{a}."
    end <> "\r\n"
    :gen_tcp.send(socket, message)

    turn_on_character_mode(socket)

    :gen_tcp.send(socket, "> ")

    loop_server(socket, name)
  end

  def ignore_telnet_stuff(response) do
    case response do
      @telnet_IAC <> <<_, _>> <> rest -> rest
      msg -> msg
    end
  end

  defp turn_on_character_mode(socket) do
    :gen_tcp.send(socket, @telnet_IAC <> @telnet_DONT <> @telnet_ECHO)
    :gen_tcp.send(socket, @telnet_IAC <> @telnet_WILL <> @telnet_ECHO)
    :gen_tcp.send(socket, @telnet_IAC <> @telnet_WILL <> @telnet_SUPPRESS_GO_AHEAD)
    :gen_tcp.send(socket, @telnet_IAC <> @telnet_DONT <> @telnet_LINEMODE)
    :gen_tcp.send(socket, @telnet_IAC <> @telnet_WONT <> @telnet_LINEMODE)
  end

  defp clear(length) do
    "\r#{String.duplicate(" ", length)}"
  end

  defp send_and_reprint_buffer(socket, buffer, message) do
    :gen_tcp.send(socket, "#{clear(String.length(buffer) + 3)}\r#{message}> #{buffer}")
  end

  defp loop_server(socket, name, buffer \\ "") do
    receive do
      {:join, name}         -> send_and_reprint_buffer(socket, buffer, "#{name} joined.\r\n")
      {:say, name, message} -> send_and_reprint_buffer(socket, buffer, "#{name}: #{message}\r\n")
      {:part, name}         -> send_and_reprint_buffer(socket, buffer, "#{name} left.\r\n")
      _ -> nil
    after 0 -> nil
    end

    case :gen_tcp.recv(socket, 1, 30) do
      {:ok, "\r"} ->
        Logger.info "#{name}: #{buffer}"
        TelnetChat.Server.say(TelnetChat.ChatServer, buffer)
        buffer = ""
      {:ok, "\d"} -> # backspace
        buffer = String.slice(buffer, 0..-2)
        send_and_reprint_buffer(socket, buffer, "")
      {:ok, "\e"} -> # ignore next 2 bytes after escape
        {:ok, ignored_bytes} = :gen_tcp.recv(socket, 2)
        Logger.debug "Ignored escaped bytes: #{inspect ignored_bytes}"
      {:ok, char} ->
        if char > <<31>> && char < <<127>> do
          Logger.debug inspect(char)
          :gen_tcp.send(socket, char)
          buffer = buffer <> char
        end
        {:error, :timeout} -> nil
      {:error, :closed} ->
        Logger.info "#{name} left."
        TelnetChat.Server.part(TelnetChat.ChatServer)
        exit(:normal)
    end

    loop_server(socket, name, buffer |> ignore_telnet_stuff)
  end
end
