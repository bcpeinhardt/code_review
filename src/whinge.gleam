//// A linter for Gleam, written in Gleam. Staring with a very basic prototype setup:
//// Read in the gleam files, iterate over them searching for common patterns
//// based on the glance module that get's parsed, and produce messages pointing out 
//// the issue.

import gleam/io
import gleam/list
import gleam/result
import gleam/string

import glance.{type Module, Module}
import simplifile

pub type WhingeError {
  CouldNotGetCurrentDirectory
  CouldNotGetSourceFiles
  CouldNotReadAllSourceFiles
  CouldNotParseAllModules
}

fn whinge_error_to_error_message(input: WhingeError) -> String {
  case input {
    CouldNotGetCurrentDirectory -> "Error: Could not get current directory"
    CouldNotGetSourceFiles -> "Error: Could not get source files"
    CouldNotReadAllSourceFiles -> "Error: Could not read all source files"
    CouldNotParseAllModules -> "Error: Could not parse all modules"
  }
}

pub fn main() {
  case run() {
    Ok(Nil) -> io.println("Done.")
    Error(e) ->
      io.print_error(
        e
        |> whinge_error_to_error_message,
      )
  }
}

fn run() -> Result(Nil, WhingeError) {
  // Get the current directory
  use pwd <- result.try(
    simplifile.current_directory()
    |> result.replace_error(CouldNotGetCurrentDirectory),
  )
  // Read in all the src files
  use src_files <- result.try(
    simplifile.get_files(pwd <> "/src")
    |> result.replace_error(CouldNotGetSourceFiles),
  )
  // Make sure we're only reading in gleam files
  let src_files = list.filter(src_files, string.ends_with(_, ".gleam"))

  // Read the contents of each source file
  use src_code <- result.try(
    list.try_map(src_files, simplifile.read)
    |> result.replace_error(CouldNotReadAllSourceFiles),
  )
  // Parse the contents of each source file as a glance module
  use modules <- result.try(
    list.try_map(src_code, glance.module)
    |> result.replace_error(CouldNotParseAllModules),
  )
  // Iterate over the modules and run each lint
  list.each(modules, fn(module) { contains_panics(module) })

  Ok(Nil)
}

pub fn contains_panics(input: Module) -> Nil {
  let Module(functions: function_defs, ..) = input
  let functions =
    list.map(function_defs, fn(def) {
      let glance.Definition(_, definition) = def
      list.map(definition.body, fn(stmt) {
        case stmt {
          glance.Use(_, function) -> function
          glance.Assignment(value: val, ..) -> val
          glance.Expression(expr) -> expr
        }
      })
    })
  list.map(list.flatten(functions), fn(expr) {
    case expr {
      glance.Panic(_) -> io.println_error("Code contains panic!")
      _ -> Nil
    }
  })
  Nil
}
