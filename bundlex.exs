defmodule Membrane.Ogg.BundlexProject do
  use Bundlex.Project

  def project do
    [
      nifs: nifs(Bundlex.platform())
    ]
  end

  def nifs(_platform) do
    [
      payloader: [
        deps: [membrane_common_c: :membrane, unifex: :unifex],
        sources: [
          "_generated/payloader.c",
          "payloader.c"
        ],
        libs: ["ogg"]
      ]
    ]
  end
end
