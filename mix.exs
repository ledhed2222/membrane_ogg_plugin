defmodule MembraneOggPlugin.MixProject do
  use Mix.Project

  def project do
    [
      app: :membrane_ogg_plugin,
      compilers: [:unifex, :bundlex] ++ Mix.compilers(),
      version: "0.1.0",
      elixir: "~> 1.11",
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
      {:unifex, "~> 0.2.6"},
      {:membrane_core, "~> 0.5.0"},
      {:membrane_common_c, "~> 0.3.0"},
      # TODO publish on hex and don't reference github
      {:membrane_ogg_format, git: "https://github.com/ledhed2222/membrane_ogg_format"},
      {:membrane_opus_format, git: "https://github.com/ledhed2222/membrane_opus_format"}
    ]
  end
end
