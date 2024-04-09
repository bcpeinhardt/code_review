//// A linter for Gleam, written in Gleam. Staring with a very basic prototype setup:
//// Read in the gleam files, iterate over them searching for common patterns
//// based on the glance module that get's parsed, and produce messages pointing out 
//// the issue.

import gleam/io
import gleam/list
import gleam/option
import gleam/result
import gleam/string

import glance
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
  let src_files =
    list.filter(src_files, string.ends_with(_, ".gleam"))
    // Temporarily filter out the whinge module for debug purposes
    |> list.filter(fn(x) { !string.contains(x, "whinge.gleam") })

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

fn contains_panics(input_module: glance.Module) -> Nil {
  visit_expressions(input_module, fn(exp) {
    case exp {
      glance.Panic(_) -> io.println_error("Error: panic found")
      _ -> Nil
    }
  })
}

// Extracts all the top level functions out of a glance module.
fn extract_functions(from input: glance.Module) -> List(glance.Function) {
  let glance.Module(functions: function_defs, ..) = input
  let _functions =
    list.map(function_defs, fn(def) {
      let glance.Definition(_, func) = def
      func
    })
}

fn extract_constants(from input: glance.Module) -> List(glance.Constant) {
  let glance.Module(constants: consts, ..) = input
  list.map(consts, fn(const_) {
    let glance.Definition(_, c) = const_
    c
  })
}

fn visit_expressions(
  input: glance.Module,
  do f: fn(glance.Expression) -> Nil,
) -> Nil {
  let funcs = extract_functions(input)
  let consts = extract_constants(input)

  // Visit all the expressions in top level functions
  {
    use func <- list.each(funcs)
    use stmt <- list.each(func.body)

    let expr = case stmt {
      glance.Use(_, expr) -> expr
      glance.Assignment(value: val, ..) -> val
      glance.Expression(expr) -> expr
    }

    do_visit_expressions(expr, f)
  }

  // Visit all the expressions in constants
  list.each(consts, fn(c) { do_visit_expressions(c.value, f) })
}

fn do_visit_expressions(
  input: glance.Expression,
  do f: fn(glance.Expression) -> Nil,
) -> Nil {
  f(input)
  case input {
    glance.Todo(_)
    | glance.Panic(_)
    | glance.Int(_)
    | glance.Float(_)
    | glance.String(_)
    | glance.Variable(_) -> Nil

    glance.NegateInt(expr) | glance.NegateBool(expr) -> f(expr)

    glance.Block(stmts) -> {
      use stmt <- list.each(stmts)
      case stmt {
        // In a use statement, the "expression" should be
        glance.Use(_, expr) -> f(expr)
        glance.Assignment(value: val, ..) -> f(val)
        glance.Expression(expr) -> f(expr)
      }
    }
    glance.Tuple(exprs) -> list.each(exprs, f)
    glance.List(elements, rest) -> {
      list.each(elements, f)
      option.map(rest, f)
      Nil
    }
    glance.Fn(arguments: _, return_annotation: _, body: body) -> {
      use stmt <- list.each(body)
      case stmt {
        // In a use statement, the "expression" should be
        glance.Use(_, expr) -> f(expr)
        glance.Assignment(value: val, ..) -> f(val)
        glance.Expression(expr) -> f(expr)
      }
    }
    glance.RecordUpdate(
        module: _,
        constructor: _,
        record: record,
        fields: fields,
      ) -> {
      f(record)
      use #(_, expr) <- list.each(fields)
      f(expr)
    }
    glance.FieldAccess(container: container, label: _) -> f(container)
    glance.Call(function, arguments) -> {
      f(function)
      list.each(arguments, fn(arg) { f(arg.item) })
    }
    glance.TupleIndex(tuple, index: _) -> {
      f(tuple)
    }
    glance.FnCapture(
        label: _,
        function: function,
        arguments_before: arguments_before,
        arguments_after: arguments_after,
      ) -> {
      f(function)
      list.each(arguments_before, fn(arg) { f(arg.item) })
      list.each(arguments_after, fn(arg) { f(arg.item) })
    }
    glance.BitString(segments) -> {
      use #(expr, _) <- list.each(segments)
      f(expr)
    }
    glance.Case(subjects, clauses) -> {
      list.each(subjects, f)
      list.each(clauses, fn(c) {
        let glance.Clause(_, guard, body) = c
        option.map(guard, f)
        f(body)
      })
    }
    glance.BinaryOperator(name: _, left: left, right: right) -> {
      f(left)
      f(right)
    }
  }
}
