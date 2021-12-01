defmodule MembraneOggPlugin.MixProject do
  use Mix.Project

  def project do
    [
      app: :membrane_ogg_plugin,
      compilers: [:unifex, :bundlex] ++ Mix.compilers(),
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:membrane_core, "~> 0.8.0"},
      {:membrane_common_c, "~> 0.10.0"},
      {:unifex, "~> 0.7.0"},
      # TODO publish on hex and don't reference github
      {:membrane_ogg_format, github: "membraneframework/membrane_ogg_format"},
      {:membrane_opus_format, "~> 0.3.0"}
    ]
  end
end
