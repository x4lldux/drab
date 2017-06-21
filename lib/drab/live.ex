defmodule Drab.Live do
  @moduledoc false
  import Drab.Core

  use DrabModule
  def js_templates(),  do: ["drab.events.js", "drab.live.js"]

  def transform_payload(payload, _state) do
    # IO.inspect payload
    # decrypt assigns
    # TODO: maybe better to do it on demand, on poke/peek?
    decrypted = for {k, v} <- payload["assigns"] || %{}, into: %{}, do: {k, Drab.Live.Crypto.decode64(v)}
    Map.merge(payload, %{"assigns" => decrypted})
      |> Map.put_new("value", payload["val"])
  end

  def transform_socket(socket, payload, state) do
    # # store assigns in socket as well
    priv = Map.merge(state.priv, %{
      ampere_assigns: payload["assigns"],
      amperes: payload["amperes"],
      ampere_scripts: payload["scripts"]
    })
    Drab.pid(socket) |> Drab.set_priv(priv)
    socket
  end

  # engine: Drab.Live.EExEngine
  def render_live(template, assigns \\ []) do
    EEx.eval_file(template, [assigns: assigns], engine: Drab.Live.EExEngine)
  end

  defp assigns(socket) do
    socket |> Drab.pid() |> Drab.get_priv() |> Map.get(:ampere_assigns)
  end

  defp amperes(socket) do
    socket |> Drab.pid() |> Drab.get_priv() |> Map.get(:amperes)
  end

  def peek(socket, assign) when is_binary(assign) do
    assigns(socket)[assign]
  end

  def peek(socket, assign) when is_atom(assign), do: peek(socket, Atom.to_string(assign))

  def poke(socket, assigns) do
    current_assigns = assigns(socket)
    assigns_to_update = Map.new(assigns)
    assigns_to_update_keys = Map.keys(assigns_to_update)

    view = socket.assigns.__controller.__drab__().view
    app_module = Drab.Config.app_module()
    router_helpers = Module.concat(app_module, Router.Helpers)
    error_helpers = Module.concat(app_module, ErrorHelpers)
    gettext = Module.concat(app_module, Gettext)

    # amperes of attributes contains more hashes, space separated
    amperes = amperes(socket)
      |> Enum.map(&String.split/1)
      |> List.flatten()
      |> Enum.uniq()

    # construct the javascript for update the innerHTML of amperes
    #TODO: group updates on one node
    injected_updates = for ampere_hash <- amperes do
      selector = "[drab-ampere='#{ampere_hash}']"
      case Drab.Live.Cache.get(ampere_hash) do
        {:expr, expr, assigns_in_expr} ->
          # change only if poked assign exist in this ampere
          #TODO: stay DRY
          if has_common?(assigns_in_expr, assigns_to_update_keys) do
            {safe, _assigns} = expr_with_imports(expr, view, router_helpers, error_helpers, gettext)
              |> Code.eval_quoted([assigns: assigns_for_expr(assigns_to_update, assigns_in_expr, current_assigns)])

            new_value = safe_to_encoded_js(safe)

            "Drab.update_drab_span(#{encode_js(selector)}, #{new_value})"
          else
            nil
          end
        {:attribute, list} ->
          for {attribute, pattern, exprs} <- list do
            hash_and_value = Enum.map(exprs, fn hash -> 
              {:expr, expr, assigns_in_expr} = Drab.Live.Cache.get(hash)

              if has_common?(assigns_in_expr, assigns_to_update_keys) do
                {safe, _assigns} = expr_with_imports(expr, view, router_helpers, error_helpers, gettext)
                  |> Code.eval_quoted([assigns: assigns_for_expr(assigns_to_update, assigns_in_expr, current_assigns)])
                new_value = safe_to_string(safe)

                {hash, new_value}
              else
                nil
              end

            end) |> Enum.filter(fn x -> x end)
            new_value_of_attribute = replace_pattern(pattern, hash_and_value) |> encode_js()

            if Regex.match?(~r/{{{{@drab-ampere:[^@}]+@drab-expr-hash:[^@}]+}}}}/, attribute) do
              #TODO: special form, without atribute name
              nil
            else
              "Drab.update_attribute(#{encode_js(selector)}, #{encode_js(attribute)}, #{new_value_of_attribute})"
            end
          end
        {:script, pattern, exprs} -> 
          hash_and_value = Enum.map(exprs, fn hash ->
            {:expr, expr, assigns_in_expr} = Drab.Live.Cache.get(hash)
            if has_common?(assigns_in_expr, assigns_to_update_keys) do
              {safe, _assigns} = expr_with_imports(expr, view, router_helpers, error_helpers, gettext)
                |> Code.eval_quoted([assigns: assigns_for_expr(assigns_to_update, assigns_in_expr, current_assigns)])
              new_value = safe_to_string(safe)
              {hash, new_value}
            else
              nil
            end
          end) |> Enum.filter(fn x -> x end)
          new_script = replace_pattern(pattern, hash_and_value) |> encode_js()

          "Drab.update_script(#{encode_js(selector)}, #{new_script})"
        _ -> raise "Ampere \"#{ampere_hash}\" can't be found in Drab Cache"
        # _ -> []
      end
    end |> Enum.filter(fn x -> x end) |> List.flatten()

    IO.inspect(injected_updates)

    changes_assigns_js = changed_assigns_js_list(assigns_to_update)
    ampere_updates = (changes_assigns_js ++ injected_updates) |> Enum.uniq()
      
    {:ok, _} = Drab.Core.exec_js(socket, ampere_updates |> Enum.join(";"))

    assigns_to_update = for {k, v} <- assigns_to_update, into: %{}, do: {Atom.to_string(k), v}
    updated_assigns = Map.merge(current_assigns, assigns_to_update)

    #TODO: store in Drab
    # Phoenix.Socket.assign(socket, :__ampere_assigns, updated_assigns)
    priv = socket |> Drab.pid() |> Drab.get_priv()
    socket |> Drab.pid() |> Drab.set_priv(%{priv | ampere_assigns: updated_assigns})

    socket
  end

  defp replace_pattern(pattern, []), do: pattern
  defp replace_pattern(pattern, [{hash, value} | rest]) do
    new_pattern = String.replace(pattern, ~r/{{{{@drab-ampere:[^@}]+@drab-expr-hash:#{hash}}}}}/, value, global: true)
    replace_pattern(new_pattern, rest)
  end

  defp has_common?(lista, listb) do
    if Enum.find(lista, fn xa -> Enum.find(listb, fn xb -> xa == xb end) end), do: true, else: false
  end

  defp expr_with_imports(expr, view, router_helpers, error_helpers, gettext) do
    #TODO: find it in the web.ex
    # Find corresponding View
    quote do 
      import unquote(view)
      import Phoenix.Controller, only: [get_csrf_token: 0, get_flash: 2, view_module: 1]
      use Phoenix.HTML
      import unquote(router_helpers)
      import unquote(error_helpers)
      import unquote(gettext)
      unquote(expr)
    end    
  end

  #TODO: refactor, not very efficient
  defp assigns_for_expr(assigns_in_poke, assigns_in_expr, assigns_in_page) do
    # assigns_in_expr = String.split(assigns_in_expr) |> Enum.map(&String.to_existing_atom/1)
    missing_keys = assigns_in_expr -- Map.keys(assigns_in_poke)
    assigns_in_page = for {k, v} <- assigns_in_page, into: %{}, do: {String.to_existing_atom(k), v}
    stored_assigns = Enum.filter(assigns_in_page, fn {k, _} -> Enum.member?(missing_keys, k) end) |> Map.new()
    Map.merge(stored_assigns, assigns_in_poke) |> Map.to_list()
  end

  defp changed_assigns_js_list(assigns) do
    Enum.map(assigns, fn {k, v} -> 
      "__drab.assigns[#{Drab.Core.encode_js(k)}] = #{Drab.Live.Crypto.encode64(v) |> Drab.Core.encode_js()}" 
    end)
  end

  defp safe_to_encoded_js(safe), do: safe |> safe_to_string() |> encode_js()

  defp safe_to_string(list) when is_list(list), do: Enum.map(list, &safe_to_string/1) |> Enum.join("")
  defp safe_to_string({:safe, _} = safe), do: Phoenix.HTML.safe_to_string(safe)
  defp safe_to_string(safe), do: to_string(safe)

end