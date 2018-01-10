defmodule ExIbus.ReaderTest do
  use ExUnit.Case

  doctest ExIbus.Reader
  alias ExIbus.{Message, Reader}

  test "pid should be process" do
    {:ok, pid} = Reader.start_link()
    assert is_pid(pid)
    Process.exit(pid, :kill)
  end

  test "read() return empty list of messages" do
    {:ok, pid} = Reader.start_link()
    [] = Reader.read(pid)
    Process.exit(pid, :kill)
  end

  test "write() should send message to process" do
    {:ok, pid} = Reader.start_link()
    [] = Reader.read(pid)
    Reader.write(pid, <<0x68>>)
    Reader.write(pid, <<0x04>>)
    Reader.write(pid, <<0x18>>)
    Reader.write(pid, <<0x0A>>)
    Reader.write(pid, <<0x00>>)
    Reader.write(pid, <<0x7E>>)

    msg = %Message{src: <<0x68>>, dst: <<0x18>>, msg: <<0x0A, 0x00>>}
    [^msg] = Reader.read(pid)
    Process.exit(pid, :kill)
  end

  test "write() should accept entire message" do
    msg = %Message{src: <<0x68>>, dst: <<0x18>>, msg: <<0x0A, 0x00>>}
    {:ok, pid} = Reader.start_link()
    Reader.write(pid, Message.raw(msg))
    [^msg] = Reader.read(pid)
    Process.exit(pid, :kill)
  end

  test "configure() active with no listener should fail" do
    {:ok, pid} = Reader.start_link()
    {:error, _} = Reader.configure(pid, active: true, listener: nil)
    Process.exit(pid, :kill)
  end

  test "active should send messages to process" do
    {:ok, pid} = Reader.start_link()
    :ok = Reader.configure(pid, active: true, listener: self())
    msg = %Message{src: <<0x68>>, dst: <<0x18>>, msg: <<0x0A, 0x00>>}
    Reader.write(pid, Message.raw(msg))
    assert_receive {:ex_ibus, "", ^msg}
  end

  test "named reader process" do
    name = "random_reader"
    {:ok, pid} = Reader.start_link()
    :ok = Reader.configure(pid, active: true, listener: self(), name: name)
    msg = %Message{src: <<0x68>>, dst: <<0x18>>, msg: <<0x0A, 0x00>>}
    Reader.write(pid, Message.raw(msg))
    assert_receive {:ex_ibus, ^name, ^msg}
  end
end
