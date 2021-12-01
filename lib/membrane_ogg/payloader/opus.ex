defmodule Membrane.Ogg.Payloader.Opus do
  @moduledoc """
  Payloads an Opus stream for embedding into an Ogg container.

  Right now this only support mono or stereo input. It is possible to mux multiple
  Opus streams for more input channels, but that's not implemented yet. This also
  doesn't support any tags right now.
  """

  use Membrane.Filter

  alias Membrane.{Buffer, Opus, Ogg}
  alias Membrane.Ogg.Payloader

  @vendor_string "Membrane"
  # this is hardcoded per the RFC
  @encapsulation_version 1
  @reference_sample_rate 48_000

  def_options frame_size: [
                type: :float,
                description: """
                The duration of an Opus packet as defined in [RFC6716] can be any
                multiple of 2.5 ms, up to a maximum of 120 ms.
                See https://datatracker.ietf.org/doc/html/rfc7845#section-4
                """
              ],
              original_sample_rate: [
                type: :non_neg_integer,
                default: 0,
                description: """
                Optionally, you may pass the original sample rate of the source (before it was encoded).
                This is considered metadata for Ogg/Opus. Leave this at 0 otherwise.
                See https://tools.ietf.org/html/rfc7845#section-5.
                """
              ],
              output_gain: [
                type: :integer,
                default: 0,
                description: """
                Optionally, you may pass a gain change when decoding.
                You probably shouldn't though. Instead apply any gain changes using Membrane itself, if possible.
                See https://tools.ietf.org/html/rfc7845#section-5
                """
              ],
              pre_skip: [
                type: :non_neg_integer,
                default: 0,
                description: """
                Optionally, you may as a number of samples (at 48kHz) to discard
                from the decoder output when starting playback.
                See https://tools.ietf.org/html/rfc7845#section-5
                """
              ]

  def_input_pad :input, demand_unit: :buffers, caps: Opus
  def_output_pad :output, caps: Ogg

  @impl true
  def handle_init(%__MODULE__{} = options) do
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

    {:ok, state}
  end

  @impl true
  def handle_stopped_to_prepared(_ctx, state) do
    case Payloader.init() do
      {:ok, payloader} ->
        {:ok, %{state | payloader: payloader}}

      {:error, reason} ->
        {{:error, reason}, state}
    end
  end

  @impl true
  def handle_prepared_to_stopped(_ctx, state) do
    {:ok, %{state | payloader: nil}}
  end

  @impl true
  def handle_demand(:output, bufs, :buffers, _ctx, state) do
    {{:ok, demand: {:input, bufs}}, state}
  end

  @impl true
  def handle_caps(:input, caps, _ctx, state) do
    caps = %Ogg{
      content: caps
    }

    {{:ok, caps: {:output, caps}}, state}
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

    {{:ok, buffer: {:output, %Buffer{payload: null_page}}, end_of_stream: :output},
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

    {{:ok, actions}, state}
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

      {{:ok, buffer: {:output, output}}, state}
    else
      {:error, reason} -> {{:error, reason}, state}
    end
  end

  defp id_header(ctx, state) do
    [
      "OpusHead",
      <<@encapsulation_version::size(8)>>,
      <<ctx.pads.input.caps.channels::size(8)>>,
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
    # FIXME for now doesn't handle 0-length frames
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
