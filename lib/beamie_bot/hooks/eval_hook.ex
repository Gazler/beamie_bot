defmodule EvalHook do
  def run(_sender, msg) do
    result = case msg do
      "~~" <> rest -> parse_version(rest, "elixir", prefix: "v", version: "master")

      "erl~r16" <> <<x::utf8>> <> expr when x in [? , ? ] ->
        {expr, lang: "erlang", version: "R16B03-1"}
      "erl~" <> rest -> parse_version(rest, "erlang", version: "17.1")

      "lfe~" <> rest -> parse_version(rest, "lfe", version: "latest")

      "eval~" <> rest -> parse_version(rest, "elixir", prefix: "v", version: "master")

      _ -> nil
    end

    if result do
      {expr, opts} = result

      expr = String.strip(expr)
      output = Evaluator.eval(expr, opts)

      cond do
        output == "Timed out." ->
          {:notice, output}
        output ->
          lines = String.split(output, "\n")
          lines_to_msg(lines, {expr, output})
        true -> nil
      end
    end
  end

  @re Regex.compile!("([\\d.]+)\\s+", [:unicode, :ucp])

  defp parse_version(str, lang, opts) do
    case Regex.split(@re, str, parts: 2) do
      [expr] ->
        version = Keyword.get(opts, :version)
        {expr, lang: lang, version: version}

      [_, version, expr] ->
        prefix = Keyword.get(opts, :prefix, "")
        {expr, lang: lang, version: prefix<>version}

      _ -> nil
    end
  end

  @maxlines 3

  defp lines_to_msg(lines, data), do:
    lines_to_msg(lines, @maxlines, [], data)

  defp lines_to_msg([], _, acc, _), do:
    Enum.reverse(acc)

  defp lines_to_msg(_, 0, acc, data) do
    link = gist_text(data)
    Enum.reverse([{:msg, "Output truncated: #{link}"}|acc])
  end

  defp lines_to_msg([line|rest], n, acc, data), do:
    lines_to_msg(rest, n-1, [{:msg, line}|acc], data)


  defp gist_text({expr, output}) do
    output = "# #{escape_newlines(expr)}\n" <> output
    # replace \# with # in the json
    inspected = Regex.replace(~r/(?<=[^\\])\\#/, inspect(output), "#")
    json = """
    {
      "description": "",
      "public": true,
      "files": {
        "output": {
          "content": #{inspected}
        }
      }
    }
    """
    result = :httpc.request(:post, {'https://api.github.com/gists', [{'User-Agent', 'beamie bot'}], 'application/json', json}, [], [sync: true])
    case result do
      {:error, _reason} ->
        IO.inspect _reason
        "*failed to gist the output*"
      {:ok, {status, _headers, data} } ->
        IO.inspect status
        case status do
          {_, 201, _} ->
            json = List.to_string(data)
            case Regex.run(~r/"html_url":\s*"([^"]+)",/, json) do
              [_, url] -> url
              _        -> "*failed to gist the output*"
            end

          _ ->
            "*failed to gist the output*"
        end
    end
  end


  defp escape_newlines("") do
    ""
  end

  defp escape_newlines(<<?\n::utf8>> <> rest) do
    <<?\\, ?n>> <> escape_newlines(rest)
  end

  defp escape_newlines(<<?\r::utf8>> <> rest) do
    <<?\\, ?r>> <> escape_newlines(rest)
  end

  defp escape_newlines(<<?\t::utf8>> <> rest) do
    <<?\\, ?t>> <> escape_newlines(rest)
  end

  defp escape_newlines(<<c::utf8>> <> rest) do
    <<c::utf8>> <> escape_newlines(rest)
  end
end