defmodule ExIbus.Mixfile do
  use Mix.Project

  @description """
  Ibus helper modules
  """

  def project do
    [
      app: :ex_ibus,
      version: "0.1.0",
      elixir: "~> 1.3",
      name: "Ibus protocol helper",
      description: @description,
      docs: [extras: ["README.md"]],
      start_permanent: Mix.env() == :prod,
      package: package(),
      deps: deps(),
      source_url: "https://github.com/konstantinzolotarev/ex_ibus"
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
      {:ex_doc, "~> 0.14", only: :dev}
    ]
  end

  defp package do
    [
      maintainers: ["Konstantin Zolotarev"],
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/konstantinzolotarev/ex_ibus"}
    ]
  end
end
