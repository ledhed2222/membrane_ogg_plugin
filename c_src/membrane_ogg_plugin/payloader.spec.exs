module Membrane.Ogg.Payloader.Native

spec create(serial :: uint) :: {:ok :: label, state :: state}

spec make_pages(
       payload :: payload,
       state :: state,
       position :: uint,
       packet_number :: uint,
       header_type :: int
     ) ::
       {:ok :: label, payload :: payload}
       | {:error :: label, reason :: atom}

spec flush(state :: state) ::
       {:ok :: label, payload :: payload}
       | {:error :: label, reason :: atom}
