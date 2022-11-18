defmodule Membrane.Ogg.Payloader.Opus do
  @moduledoc """
  Payloads an Opus stream for embedding into an Ogg container.

  Right now this only support mono or stereo input. It is possible to mux multiple
  Opus streams for more input channels, but that's not implemented yet. This also
  doesn't support any tags right now.
  """

  use Membrane.Filter

  require Membrane.Logger

  alias Membrane.{Buffer, Ogg, Opus}
  alias Membrane.Ogg.Payloader

  @vendor_string "Membrane"
  # this is hardcoded per the RFC
  @encapsulation_version 1
  @reference_sample_rate 48_000

  def_options frame_size: [
                spec: float,
                description: """
                The duration of an Opus packet can be any
                multiple of 2.5 ms, up to a maximum of 120 ms.
                See https://datatracker.ietf.org/doc/html/rfc7845#section-4
                """
              ],
              serial_number: [
                spec: non_neg_integer | :random,
                default: :random,
                description: """
                Ogg logical bitstreams must be assigned a unique 4-byte serial number which is chosen randomly.
                This option allows you to pass in a specific number which can be useful for reproducability.
                See https://datatracker.ietf.org/doc/html/rfc3533#section-4
                """
              ],
              original_sample_rate: [
                spec: non_neg_integer,
                default: 0,
                description: """
                The original sample rate of the source - before it was encoded with Opus.
                This is considered optional metadata for Ogg/Opus and it does NOT affect playback.
                See https://tools.ietf.org/html/rfc7845#section-5.
                """
              ],
              output_gain: [
                spec: integer,
                default: 0,
                description: """
                The gain change to be applied by a player when decoding.
                This is NOT the preferred way to change volume.
                Unless you have a reason to preserve the original audio waveform, gain changes should be applied
                directly to the samples i.e. the stream should be remuxed with scaled samples and 0 `output_gain`.
                See https://tools.ietf.org/html/rfc7845#section-5
                """
              ],
              pre_skip: [
                spec: non_neg_integer,
                default: 0,
                description: """
                The number of samples (at 48kHz) to be discarded from the decoder output when starting playback.
                See https://tools.ietf.org/html/rfc7845#section-5
                """
              ]

  def_input_pad :input, demand_unit: :buffers, accepted_format: Opus
  def_output_pad :output, accepted_format: Ogg

  @impl true
  def handle_init(_ctx, %__MODULE__{} = options) do
    state =
      options
      |> Map.from_struct()
      |> Map.merge(%{
        header_sent?: false,
        granule_position: 0,
        payloader: nil,
        # initialize to 2 to account for id and tag pages
        packet_number: 2
      })

    {[], state}
  end

  @impl true
  def handle_setup(_ctx, state) do
    case Payloader.init(state.serial_number) do
      {:ok, payloader} ->
        {[], %{state | payloader: payloader}}

      {:error, reason} ->
        {{:error, reason}, state}
    end
  end

  @impl true
  def handle_demand(:output, bufs, :buffers, _ctx, state) do
    {[demand: {:input, bufs}], state}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    if stream_format.channels > 2,
      do:
        Membrane.Logger.warn(
          "Tried to payload an Opus stream with #{stream_format.channels} but only Opus streams with 1 or 2 channels are currently supported."
        )

    stream_format = %Ogg{
      content: stream_format
    }

    {[stream_format: {:output, stream_format}], state}
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    {:ok, null_page} =
      Payloader.make_pages_and_flush(
        <<>>,
        state.payloader,
        state.granule_position,
        state.packet_number,
        :eos
      )

    {[buffer: {:output, %Buffer{payload: null_page}}, end_of_stream: :output],
     %{state | packet_number: state.packet_number + 1}}
  end

  @impl true
  def handle_process(:input, %Buffer{payload: data}, ctx, state) when state.header_sent? do
    {:ok, {raw_output, position_offset}} = audio_pages(data, ctx, state)

    state =
      state
      |> Map.merge(%{
        packet_number: state.packet_number + 1,
        granule_position: state.granule_position + position_offset
      })

    actions =
      if byte_size(raw_output) > 0 do
        [buffer: {:output, %Buffer{payload: raw_output}}]
      else
        [redemand: :output]
      end

    {actions, state}
  end

  @impl true
  def handle_process(:input, %Buffer{payload: data}, ctx, state) do
    with {:ok, id_header} <- id_header(ctx, state),
         {:ok, comment_header} <- comment_header(state),
         {:ok, {audio_pages, position_offset}} <- audio_pages(data, ctx, state) do
      output =
        [
          id_header,
          comment_header,
          audio_pages
        ]
        |> Enum.filter(fn raw -> byte_size(raw) > 0 end)
        |> Enum.map(fn raw -> %Buffer{payload: raw} end)

      state =
        state
        |> Map.merge(%{
          packet_number: state.packet_number + 1,
          granule_position: state.granule_position + position_offset,
          header_sent?: true
        })

      {[buffer: {:output, output}], state}
    else
      {:error, reason} -> {{:error, reason}, state}
    end
  end

  defp id_header(ctx, state) do
    [
      "OpusHead",
      <<@encapsulation_version::size(8)>>,
      <<ctx.pads.input.stream_format.channels::size(8)>>,
      <<state.pre_skip::little-size(16)>>,
      <<state.original_sample_rate::little-size(32)>>,
      <<state.output_gain::little-signed-size(16)>>,
      # channel mapping family 0; only suitable for mono or stereo
      <<0::size(8)>>
    ]
    |> :binary.list_to_bin()
    |> Payloader.make_pages_and_flush(
      state.payloader,
      0,
      0,
      :bos
    )
  end

  defp comment_header(state) do
    [
      "OpusTags",
      <<byte_size(@vendor_string)::little-size(32)>>,
      <<@vendor_string::utf8>>,
      # number of user comments; for now just don't output any
      <<0::little-size(32)>>
    ]
    |> :binary.list_to_bin()
    |> Payloader.make_pages_and_flush(
      state.payloader,
      0,
      1,
      :cont
    )
  end

  defp audio_pages(data, _ctx, state) do
    # For now doesn't handle 0-length frames
    position_offset = div(@reference_sample_rate, 1000) * state.frame_size

    {:ok, output} =
      Payloader.make_pages(
        data,
        state.payloader,
        state.granule_position + position_offset,
        state.packet_number,
        :cont
      )

    {:ok, {output, position_offset}}
  end
end
