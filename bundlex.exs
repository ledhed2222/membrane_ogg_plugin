defmodule Membrane.Ogg.BundlexProject do
  use Bundlex.Project

  def project do
    [
      natives: natives()
    ]
  end

  def natives() do
    [
      payloader: [
        interface: :nif,
        deps: [membrane_common_c: :membrane],
        sources: ["payloader.c"],
        pkg_configs: ["ogg"],
        preprocessor: Unifex
      ]
    ]
  end
end
