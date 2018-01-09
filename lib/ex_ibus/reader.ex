defmodule ExIbus.Reader do

  use GenServer
  alias ExIbus.Message

  @moduledoc """
  This module is responsible for reading and fetching messages from data that it receives.
  Data could be sent byte by byte or message by message.
  """

  defmodule State do

    @moduledoc false
    @opaque t :: %__MODULE__{buffer: binary, controlling_process: pid, is_active: boolean}
    @doc false

    # buffer: list of bytes to process
    # messages: list of already parsed messages waiting to be sent
    # controlling_process: pid send messages to
    # is_active: active or passive mode
    defstruct buffer: "", 
      messages: [],
      controlling_process: nil,
      is_active: true

  end

  @type reader_options :: 
          {:active, boolean}
          | {:listener, pid}

  @spec start_link([term]) :: {:ok, pid} | {:error, term}
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, %State{}, opts)

  @doc """
  Read list of available messages in reader.
  Note that list of messages might be empty if nothing was parsed.

  ```elixir
  iex> {:ok, pid} = ExIbus.Reader.start_link()
  iex> ExIbus.Reader.read(pid)
  []
  ```
  """
  @spec read(pid) :: [ExIbus.Message.t] | {:error, term}
  def read(pid), do: GenServer.call(pid, :get_messages)

  @doc """
  Send data to Module for processing
  """
  @spec write(GenServer.server, binary) :: :ok | {:error, term}
  def write(pid, msg) do
    send(pid, {:message, msg})
  end


  @doc false
  @spec init(State.t) :: {:ok, State.t}
  def init(state), do: {:ok, state}

  @doc """
  Handle new part of message or message
  Message will be places in buffer and sytem will try to get a valid message from it

  On success message fetching message will be avaliable into `ExIbus.Reader.read()` function
  or will be sent to pid in case of `:active` mode

  ```elixir
  iex> {:ok, pid} = ExIbus.Reader.start_link()
  iex> send(pid, {:message, <<0x68, 0x04, 0x18, 0x0A, 0x00, 0x7E>>})
  iex> ExIbus.Reader.read(pid)
  [%ExIbus.Message{src: <<0x68>>, dst: <<0x18>>, msg: <<0x0A, 0x00>>}]
  ```
  """
  @spec handle_info({:message, binary}, State.t) :: {:noreply, State.t} | {:error, term}
  def handle_info({:message, msg}, state) do
    new_state = process_new_message(msg, state) 
    {:noreply, new_state}
  end

  @doc false
  def handle_call(:get_messages, _from, %State{messages: messages} = state) do
    {:reply, messages, %State{state | messages: []}}
  end

  # Process buffer that was received by module
  # And try to fetch all messages from it
  defp process_new_message("", state), do: state
  defp process_new_message(msg, %State{buffer: buffer} = state) when is_binary(msg) do
    new_buff = buffer <> msg
    case byte_size(new_buff) do
      x when x >= 5 -> fetch_messages(%State{state | buffer: new_buff})
      _ -> %State{state | buffer: new_buff}
    end
  end
  defp process_new_message(_, state), do: state

  # Will try to fetch a valid message from buffer in state
  defp fetch_messages(%State{messages: messages, buffer: buffer} = state) do
    case process_buffer(buffer) do
      {:error, _} -> %State{state | buffer: ""}
      {:ok, _rest, []} -> state
      {:ok, rest, new_messages} -> %State{state | messages: messages ++ new_messages, buffer: rest}
    end
  end

  # Function will process given binary buffer and fetch all available messages
  # from buffer
  defp process_buffer(buffer, messages \\ [])
  defp process_buffer("", messages), do: {:ok, "", messages}
  defp process_buffer(buffer, messages) when is_binary(buffer) do
    with true <- byte_size(buffer) >= 5,
         {:ok, msg, rest} <- pick_message(buffer) do

          process_buffer(rest, messages ++ [msg])
    else
      false -> {:ok, buffer, messages}
      {:error, _} -> 
        buffer
        |> :binary.part(1, byte_size(buffer) - 1)
        |> process_buffer(messages)
    end
  end
  defp process_buffer(_, _), do: {:error, "Wrong input buffer passed"}

  # Will try to get message in beginning of given buffer
  # On success funciton will return `{:ok, message, rest_of_buffer}`
  # otherwise it will return `{:error, term}`
  #
  # Note that rest of buffer might be an empty binary
  defp pick_message(<< src :: size(8), lng :: size(8), tail :: binary >>) do
    with true          <- byte_size(tail) >= lng,
         msg           <- :binary.part(tail, 0, lng),
         full          <- <<src>> <> <<lng>> <> msg,
         true          <- Message.valid?(full),
         {:ok, result} <- Message.parse(full),
         rest          <- :binary.part(tail, lng, byte_size(tail) - lng) do
           {:ok, result, rest}
    else
      _ -> {:error, "No valid message in message exist"}
    end
  end
  
  # Send list of messages one by one to controlling process
  defp send_messages(%State{is_active: false} = state), do: {:ok, state}
  defp send_messages(%State{messages: []} = state), do: {:ok, state}
  defp send_messages(%State{controlling_process: nil} = state), do: {:ok, state}
  defp send_messages(%State{messages: messages, controlling_process: pid, is_active: true} = state) do
    messages
    |> Enum.each(&(send(pid, {:message, &1})))

    {:ok, %State{state | messages: []}}
  end

end
