defmodule Drab.Live.Partial do
  @moduledoc false
  alias Drab.Live.{Ampere}

  @type t :: %Drab.Live.Partial{
          path: String.t(),
          hash: String.t(),
          amperes: %{String.t() => [Ampere.t()]}
        }
  defstruct path: "", hash: "", amperes: %{}

  @doc """
  Returns %Drab.Live.Partial{} for the given hash.

      iex> match? %Drab.Live.Partial{}, partial("gm2dgnjygm2dgnjt")
      true
      iex> partial("gm2dgnjygm2dgnjt").hash
      "gm2dgnjygm2dgnjt"
      iex> partial("gm2dgnjygm2dgnjt").path
      "test/support/web/templates/live/live_engine_test.html.drab"
  """
  @spec partial(String.t()) :: t
  def partial(hash) do
    module(hash).partial()
  end

  @doc """
  Returns module for the given hash. Raises when not found.

      iex> module("gm2dgnjygm2dgnjt")
      Drab.Live.Template.Gm2dgnjygm2dgnjt
  """
  @spec module(String.t()) :: atom | no_return
  def module(hash) do
    module = Drab.Live.Engine.module_name(hash)
    unless Code.ensure_loaded?(module), do: Drab.Live.raise_partial_not_found(hash)
    module
  end

  @doc """
  Returns the filename, without drab extension, for the template

      iex> template_filename("gm2dgnjygm2dgnjt")
      "live_engine_test.html"
  """
  @spec template_filename(String.t()) :: String.t()
  def template_filename(hash) do
    module(hash).path() |> Path.basename() |> Path.rootname(Drab.Config.drab_extension())
  end

  @doc """
  Returns partial hash for the given view and filename.

      iex> hash_for_view_and_name(DrabTestApp.LiveView, "live_engine_test.html")
      "gm2dgnjygm2dgnjt"
  """
  @spec hash_for_view_and_name(atom, String.t()) :: String.t() | no_return
  def hash_for_view_and_name(view, partial_name) do
    path = partial_path(view, partial_name)
    Drab.Live.Crypto.hash(path)
  end

  @spec partial_path(atom, String.t()) :: String.t()
  defp partial_path(view, partial_name) do
    templates_path(view) <> partial_name <> Drab.Config.drab_extension()
  end

  @spec templates_path(atom) :: String.t()
  defp templates_path(view) do
    {path, _, _} = view.__templates__()
    path <> "/"
  end

  # %Drab.Live.Partial{
  #   amperes: %{
  #     "gi2dcmbrgqztmobz" => [
  #       %Drab.Live.Ampere{
  #         assigns: [:text],
  #         attribute: nil,
  #         gender: :what,
  #         tag: ""
  #       }
  #     ],
  #     "gi4dcmbygq3tmnrt" => [
  #       %Drab.Live.Ampere{
  #         assigns: [:color],
  #         attribute: nil,
  #         gender: :what,
  #         tag: ""
  #       },
  #       %Drab.Live.Ampere{
  #         assigns: [:text],
  #         attribute: nil,
  #         gender: :what,
  #         tag: ""
  #       }
  #     ]
  #   },
  #   hash: "gm2dgnjygm2dgnjt",
  #   name: "test/support/web/templates/live/live_engine_test.html.drab"
  # }

  @doc """
  Returns list of amperes for the given assign.

      iex> amperes_for_assign("gm2dgnjygm2dgnjt", :color)
      ["gi3dmojvga3tknbz", "gi4dcmbygq3tmnrt"]
      iex> amperes_for_assign("gm2dgnjygm2dgnjt", :text)
      ["gi2dcmbrgqztmobz", "gi3dmojvga3tknbz", "gi4dcmbygq3tmnrt"]
      iex> amperes_for_assign("gm2dgnjygm2dgnjt", :nonexistent)
      []
  """
  def amperes_for_assign(hash, assign) do
    for {ampere_id, amperes} <- partial(hash).amperes,
        ampere <- amperes,
        assign in ampere.assigns do
      ampere_id
    end |> Enum.uniq()
  end

  @doc """
  Returns list of amperes for the given assign list.

      iex> amperes_for_assigns("gm2dgnjygm2dgnjt", [:color])
      ["gi3dmojvga3tknbz", "gi4dcmbygq3tmnrt"]
      iex> amperes_for_assigns("gm2dgnjygm2dgnjt", [:text])
      ["gi2dcmbrgqztmobz", "gi3dmojvga3tknbz", "gi4dcmbygq3tmnrt"]
      iex> amperes_for_assigns("gm2dgnjygm2dgnjt", [:color, :text]) |> Enum.sort()
      ["gi2dcmbrgqztmobz", "gi3dmojvga3tknbz", "gi4dcmbygq3tmnrt"]
      iex> amperes_for_assigns("gm2dgnjygm2dgnjt", [:nonexistent])
      []
  """
  def amperes_for_assigns(hash, assigns) do
    for assign <- assigns do
      amperes_for_assign(hash, assign)
    end |> List.flatten() |> Enum.uniq()
  end
end
