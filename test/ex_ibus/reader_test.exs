defmodule ExIbus.ReaderTest do
  use ExUnit.Case

  doctest ExIbus.Reader
  alias ExIbus.{Message, Reader}

  setup_all do
    {:ok, pid} = Reader.start_link()
    {:ok, pid: pid}
  end

  test "pid should be process", %{pid: pid} do
    assert is_pid(pid)
  end

  test "read() return empty list of messages", %{pid: pid} do
    [] = Reader.read(pid)
  end
end
