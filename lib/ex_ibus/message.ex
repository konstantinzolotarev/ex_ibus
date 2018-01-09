defmodule ExIbus.Message do

  use Bitwise
  
  @moduledoc """
  A struct that keeps information about Ibus Message

  It contains 3 main fields:

   * `:src` - message source
   * `:dst` - message destination (receiver)
   * `:msg` - message content

  Module also contain several functions to operate with a message
  """
  @enforce_keys [:src, :dst, :msg]

  defstruct src: <<0x00>>, dst: <<0x00>>, msg: <<0x00>>

  @type t :: %__MODULE__{src: binary, dst: binary, msg: binary}

  defimpl Inspect do
    def inspect(%ExIbus.Message{} = message, _) do
      message
      |> ExIbus.Message.raw()
      |> String.codepoints()
      |> Enum.map(&("0x#{Base.encode16(&1)}"))
      |> Enum.join(" ")
    end
  end

  @doc """
  Create a raw binary message with length byte and last XOR byte as well.

  ## Example: 
  ```elixir
  iex(1)> ExIbus.Message.raw(%ExIbus.Message{src: <<0x68>>, dst: <<0x18>>, msg: <<0x0A, 0x00>>})
  <<104, 4, 24, 10, 0, 126>>
  ```

  This message should be sent into Ibus can and will be normally received by car
  """
  @spec raw(ExIbus.Message.t) :: binary
  def raw(%__MODULE__{src: src, dst: dst, msg: msg} = message) do
    full = src <> <<len(message)>> <> dst <> msg
    full <> <<xor(full)>>
  end

  @doc """
  Check if given raw message is valid Ibus message
  
  Function is really usefull for scanning Ibus can from car.
  """
  @spec valid?(binary) :: boolean
  def valid?(<< src :: size(8), lng :: size(8), dst :: size(8), msg :: binary >> = rawMsg) when is_binary(rawMsg) do
    case byte_size(<<dst>> <> msg) == lng do
      false -> false
      true ->
        # msg will contain xor byte aswell and we have to remove it
        msg = :binary.part(msg, 0, byte_size(msg) - 1)
        rawMsg ==  %__MODULE__{src: <<src>>, dst: <<dst>>, msg: msg} |> raw()
    end
  end

  def valid?(_), do: false

  @doc """
  Will try to create a new `ExIbus.Message.t` from given raw binary message
  """
  @spec parse(binary) :: {:ok, ExIbus.Message.t} | {:error, term}
  def parse(<< src :: size(8), _ :: size(8), dst :: size(8), msg :: binary >> = raw) do
    case valid?(raw) do
      false -> {:error, "Wrong message passed for parsing"}
      true ->
           # msg will contain xor byte aswell and we have to remove it
           msg = :binary.part(msg, 0, byte_size(msg) - 1)
           {:ok, %__MODULE__{src: <<src>>, dst: <<dst>>, msg: msg}}
    end
  end

  def parse(_), do: {:error, "Wrong message passed"}


  # Calculate xor (checksum) for message
  # It's a last byte for ibus message 
  defp xor(msg) when is_binary(msg) do
    msg
    |> :binary.bin_to_list()
    |> Enum.reduce(0, fn(x, acc) -> Bitwise.bxor(acc, x) end)
  end
  defp xor(_), do: <<0x00>>

  # Calculate length of Ibus message
  # Note that in Ibus protocol source of mesage should not be calculated in length
  defp len(%__MODULE__{dst: dst, msg: msg}) do
    byte_size(dst <> msg) + 1
  end
  defp len(_), do: 0

end
