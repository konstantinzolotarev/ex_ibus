defmodule ExIbus.Reader do
  use GenServer
  alias ExIbus.Message

  @moduledoc """
  This module is responsible for reading and fetching messages from data that it receives.
  Data could be sent byte by byte or message by message.
  """

  defmodule State do
    @moduledoc false
    @opaque t :: %__MODULE__{
              buffer: binary,
              name: binary,
              messages: [ExIbus.Message.t()],
              listener: pid,
              active: boolean
            }
    @doc false

    # buffer: list of bytes to process
    # messages: list of already parsed messages waiting to be sent
    # listener: pid send messages to
    # active: active or passive mode
    # name: reader name
    defstruct buffer: "",
              messages: [],
              name: "",
              listener: nil,
              active: false
  end

  @type reader_options ::
          {:active, boolean}
          | {:listener, pid}
          | {:name, binary}

  @doc """
  Start new reader in application. 

  Reader will receive/parse messages from system
  """
  @spec start_link(ExIbus.Reader.reader_options(), [term]) :: {:ok, pid} | {:error, term}
  def start_link(config \\ [], opts \\ []) do
    {:ok, state} = configure_reader(%State{}, config)
    GenServer.start_link(__MODULE__, state, opts)
  end

  @doc """
  Read list of available messages in reader.
  Note that list of messages might be empty if nothing was parsed.

  ```elixir
  iex> {:ok, pid} = ExIbus.Reader.start_link()
  iex> ExIbus.Reader.read(pid)
  []
  ```
  """
  @spec read(GenServer.server()) :: [ExIbus.Message.t()] | {:error, term}
  def read(pid), do: GenServer.call(pid, :get_messages)

  @doc """
  Send data to Module for processing
  """
  @spec write(GenServer.server(), binary) :: :ok | {:error, term}
  def write(pid, msg) do
    send(pid, {:message, msg})
  end

  @doc """
  Configure reader process.

  The folowing options are available:

   * `:active` - (`true` or `false`) specifies whether data is received as
   messages or by calling `read/2`. See discussion below.

   * `:listener` - `pid` that will receive messages in active mode.

   * `:name` - Reader name. If you need to start several readers you are able to use different names
   and you will receive `Reader` name into message later.

  Active mode defaults to true and means that data received on the
  Ibus Reader is reported in messages. The messages have the following form:

     `{:ex_ibus, reader_name, data}`

  or

     `{:ex_ibus, reader_name, {:error, reason}}`

  When in active mode, flow control can not be used to push back on the
  sender and messages will accumulated in the mailbox should data arrive
  fast enough. If this is an issue, set `:active` to false and call
  `read/1` manually when ready for more data.

  """
  @spec configure(GenServer.server(), reader_options) :: :ok | {:error, term}
  def configure(pid, opts) do
    GenServer.call(pid, {:configure, opts})
  end

  @doc false
  @spec init(State.t()) :: {:ok, State.t()}
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
  @spec handle_info({:message, binary}, State.t()) :: {:noreply, State.t()} | {:error, term}
  def handle_info({:message, msg}, state) do
    new_state =
      process_new_message(msg, state)
      |> send_messages()

    {:noreply, new_state}
  end

  @doc false
  def handle_call(:get_messages, _from, %State{messages: messages, active: active} = state) do
    case active do
      true -> {:reply, [], state}
      false -> {:reply, messages, %State{state | messages: []}}
    end
  end

  @doc false
  def handle_call({:configure, opts}, _from, state) do
    case configure_reader(state, opts) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, msg, new_state} -> {:reply, {:error, msg}, new_state}
      _ -> {:reply, {:error, "Something went wrong"}, state}
    end
  end

  # Set new configuration for reader
  defp configure_reader(state, active: true, listener: nil, name: name) do
    {:error, "Could not enable active mode without listener", %State{state | name: name}}
  end

  defp configure_reader(state, active: active, listener: listener, name: name) do
    {:ok, %State{state | active: active, listener: listener, name: name}}
  end

  defp configure_reader(state, opts) do
    active = Keyword.get(opts, :active, true)
    listener = Keyword.get(opts, :listener, nil)
    name = Keyword.get(opts, :name, "")

    configure_reader(state, active: active, listener: listener, name: name)
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
      {:error, _} ->
        %State{state | buffer: ""}

      {:ok, _rest, []} ->
        state

      {:ok, rest, new_messages} ->
        %State{state | messages: messages ++ new_messages, buffer: rest}
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
      false ->
        {:ok, buffer, messages}

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
  defp pick_message(<<src::size(8), lng::size(8), tail::binary>>) do
    with true <- byte_size(tail) >= lng,
         msg <- :binary.part(tail, 0, lng),
         full <- <<src>> <> <<lng>> <> msg,
         true <- Message.valid?(full),
         {:ok, result} <- Message.parse(full),
         rest <- :binary.part(tail, lng, byte_size(tail) - lng) do
      {:ok, result, rest}
    else
      _ -> {:error, "No valid message in message exist"}
    end
  end

  # Send list of messages one by one to controlling process
  defp send_messages(%State{active: false} = state), do: state
  defp send_messages(%State{messages: []} = state), do: state
  defp send_messages(%State{listener: nil} = state), do: state

  defp send_messages(%State{messages: messages, listener: pid, active: true, name: name} = state) do
    messages
    |> Enum.each(&send(pid, {:ex_ibus, name, &1}))

    %State{state | messages: []}
  end
end
