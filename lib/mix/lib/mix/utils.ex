defmodule Mix.Utils do
  @moduledoc """
  Utilities used throughout Mix and tasks.

  ## Command names and module names

  Throughout this module (and Mix), we use two main terms:

  * command names: are names as given from the command line;
    usually all items are in lowercase and uses dashes instead
    of underscores;

  * module names: valid module names according to Elixir;
  
  Some tasks in this module works exactly with converting
  from one to the other. See `command_to_module_name/2`,
  `module_name_to_command/2`, `get_module/2`.
  """

  @doc """
  Gets the source location of a module as a binary.
  """
  def source(module) do
    compile = module.__info__(:compile)

    # Get the source of the compiled module. Due to a bug in Erlang
    # R15 and before, we need to look for the source first in the
    # options and then into the real source.
    options =
      case List.keyfind(compile, :options, 1) do
        { :options, opts } -> opts
        _ -> []
      end

    source  = List.keyfind(options, :source, 1)  || List.keyfind(compile, :source, 1)

    case source do
      { :source, source } -> list_to_binary(source)
      _ -> nil
    end
  end

  @doc """
  Takes a `command` name and try to load a module
  with the command name converted to a module name
  in the given `at` scope.

  Returns `{ :module, module }` in case a module
  exists and is loaded, `{ :error, reason }` otherwise.

  ## Examples

      Mix.Utils.get_module("compile", Mix.Tasks)
      #=> { :module, Mix.Tasks.Compile }

  """
  def get_module(command, at // Elixir) do
    module = Module.concat(at, command_to_module_name(command))
    Code.ensure_loaded(module)
  end

  @doc """
  Returns true if any of `target` is stale compared to `source`.
  If `target` or `source` is a binary, it is expanded using `File.wildcard`.
  """
  def stale?(source, target) do
    source = expand_wildcard(source)
    target = expand_wildcard(target)

    source_stats  = Enum.map(source, fn(file) -> File.stat!(file).mtime end)
    last_modified = Enum.map(target, last_modified(&1))

    Enum.any?(source_stats, fn(source_stat) ->
      Enum.any?(last_modified, source_stat > &1)
    end)
  end

  defp expand_wildcard(wildcard) when is_binary(wildcard) do
    File.wildcard(wildcard)
  end

  defp expand_wildcard(list) when is_list(list) do
    list
  end

  defp last_modified(path) do
    case File.stat(path) do
      { :ok, stat } -> stat.mtime
      { :error, _ } -> { { 1970, 1, 1 }, { 0, 0, 0 } }
    end
  end

  @doc """
  Merges two configs recursively, merging keywords lists
  and concatenating normal lists.
  """
  def config_merge(old, new) do
    Keyword.merge old, new, fn(_, x, y) ->
      if is_list(x) and is_list(y) do
        if is_keyword(x) and is_keyword(y) do
          config_merge(x, y)
        else
          x ++ y
        end
      else
        y
      end
    end
  end

  defp is_keyword(x) do
    Enum.all? x, match?({ atom, _ } when is_atom(atom), &1)
  end

  @doc """
  Converts the given string to underscore format.

  ## Examples

      Mix.Utils.underscore "FooBar" #=> "foo_bar"

  In general, underscore can be thought as the reverse of
  camelize, however, in some cases formatting may be lost:

      Mix.Utils.underscore "SAPExample"  #=> "sap_example"
      Mix.Utils.camelize   "sap_example" #=> "SapExample"

  """
  def underscore(<<h, t | :binary>>) do
    <<to_lower_char(h)>> <> do_underscore(t, h)
  end

  defp do_underscore(<<h, t, rest | :binary>>, _) when h in ?A..?Z and not t in ?A..?Z do
    <<?_, to_lower_char(h), t>> <> do_underscore(rest, t)
  end

  defp do_underscore(<<h, t | :binary>>, prev) when h in ?A..?Z and not prev in ?A..?Z do
    <<?_, to_lower_char(h)>> <> do_underscore(t, h)
  end

  defp do_underscore(<<?-, t | :binary>>, _) do
    <<?_>> <> do_underscore(t, ?-)
  end

  defp do_underscore(<<h, t | :binary>>, _) do
    <<to_lower_char(h)>> <> do_underscore(t, h)
  end

  defp do_underscore(<<>>, _) do
    <<>>
  end

  @doc """
  Converts the given string to camelize format.

  ## Examples

      Mix.Utils.camelize "foo_bar" #=> "FooBar"

  """
  def camelize(<<?_, t | :binary>>) do
    camelize(t)
  end

  def camelize(<<h, t | :binary>>) do
    <<to_upper_char(h)>> <> do_camelize(t)
  end

  defp do_camelize(<<?_, ?_, t | :binary>>) do
    do_camelize(<< ?_, t | :binary >>)
  end

  defp do_camelize(<<?_, h, t | :binary>>) when h in ?a..?z do
    <<to_upper_char(h)>> <> do_camelize(t)
  end

  defp do_camelize(<<?_>>) do
    <<>>
  end

  defp do_camelize(<<h, t | :binary>>) do
    <<h>> <> do_camelize(t)
  end

  defp do_camelize(<<>>) do
    <<>>
  end

  @doc """
  Takes a module and converts it to a command. The nesting
  argument can be given in order to remove the nesting of
  module.

  ## Examples

      module_name_to_command(Mix.Tasks.Compile, 2)
      #=> "compile"

      module_name_to_command("Mix.Tasks.Compile.Elixir", 2)
      #=> "compile.elixir"

  """
  def module_name_to_command(module, nesting // 0)

  def module_name_to_command(module, nesting) when is_atom(module) do
    module_name_to_command(inspect(module), nesting)
  end

  def module_name_to_command(module, nesting) do
    t = Regex.split(%r/\./, to_binary(module))
    t /> Enum.drop(nesting) /> Enum.map(first_to_lower(&1)) /> Enum.join(".")
  end

  @doc """
  Takes a command and converts it to a module name format.
  
  ## Examples

      command_to_module_name("compile.elixir")
      #=> "Compile.Elixir"

  """
  def command_to_module_name(s) do
    Regex.split(%r/\./, to_binary(s)) />
      Enum.map(first_to_upper(&1)) />
      Enum.join(".")
  end

  defp first_to_upper(<<s, t|:binary>>), do: <<to_upper_char(s)>> <> t
  defp first_to_upper(<<>>), do: <<>>

  defp first_to_lower(<<s, t|:binary>>), do: <<to_lower_char(s)>> <> t
  defp first_to_lower(<<>>), do: <<>>

  defp to_upper_char(char) when char in ?a..?z, do: char - 32
  defp to_upper_char(char), do: char

  defp to_lower_char(char) when char in ?A..?Z, do: char + 32
  defp to_lower_char(char), do: char
end