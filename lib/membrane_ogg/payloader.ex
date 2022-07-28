defmodule Membrane.Ogg.Payloader do
  @moduledoc """
  This module holds various helper functions for all of the different Ogg payloaders.

  It should not be used directly.
  """

  use Bitwise, only_operators: true

  alias __MODULE__.Native

  @spec init(non_neg_integer | :random) :: {:ok, state :: reference} | {:error, reason :: atom}
  def init(serial_number) do
    Native.create(stream_identifier(serial_number))
  end

  @spec make_pages(
          buffer :: binary,
          native :: reference,
          position :: non_neg_integer,
          packet_number :: non_neg_integer,
          header_type :: :bos | :cont | :eos
        ) :: {:ok, state :: binary} | {:error, reason :: atom}
  def make_pages(buffer, native, position, packet_number, header_type) do
    Native.make_pages(
      buffer,
      native,
      position,
      packet_number,
      encode_header_type(header_type)
    )
  end

  @spec flush(reference) :: {:ok, state :: binary} | {:error, reason :: atom}
  def flush(native) do
    Native.flush(native)
  end

  @spec make_pages_and_flush(
          buffer :: binary,
          native :: reference,
          position :: non_neg_integer,
          packet_number :: non_neg_integer,
          header_type :: :bos | :cont | :eos
        ) :: {:ok, state :: binary} | {:error, reason :: atom}
  def make_pages_and_flush(buffer, native, position, packet_number, header_type) do
    with {:ok, page} <- make_pages(buffer, native, position, packet_number, header_type),
         {:ok, flushed} <- flush(native) do
      {:ok, page <> flushed}
    end
  end

  defp encode_header_type(header_type) do
    case header_type do
      :cont -> 0
      :bos -> 1
      :eos -> 2
    end
  end

  defp stream_identifier(:random) do
    :rand.uniform(1 <<< 32) - 1
  end

  # check if in range (0, 2**32)
  defp stream_identifier(number) when number > 0 and number < 4_294_967_296, do: number
end
