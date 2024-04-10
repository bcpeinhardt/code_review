//// A linter for Gleam, written in Gleam. Staring with a very basic prototype setup:
//// Read in the gleam files, iterate over them searching for common patterns
//// based on the glance module that get's parsed, and produce messages pointing out 
//// the issue.

import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

import filepath
import glance
import simplifile

type WhingeError {
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

type Lint {
  PanicFoundInFunction(module: String, function_name: String)
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
  use src <- result.try(
    list.map(src_files, fn(file) {
      let name =
        filepath.base_name(file)
        |> string.drop_right(6)
      #(name, file)
    })
    |> list.try_map(fn(x) {
      let #(name, file) = x
      use code <- result.try(simplifile.read(file))
      Ok(#(name, code))
    })
    |> result.replace_error(CouldNotReadAllSourceFiles),
  )
  // Parse the contents of each source file as a glance module
  use modules <- result.try(
    list.try_map(src, fn(x) {
      let #(name, src_code) = x
      use module <- result.try(glance.module(src_code))
      Ok(#(name, module))
    })
    |> result.replace_error(CouldNotParseAllModules),
  )
  // Iterate over the modules and run each lint
  list.flat_map(modules, fn(module) {
    let #(name, module) = module
    let lints = contains_panics(module)
    list.map(lints, fn(lint) { lint(name) })
  })
  |> io.debug

  Ok(Nil)
}

fn contains_panics(input_module: glance.Module) -> List(fn(String) -> Lint) {
  // Panics are "expressions", so they'll only be found in functions
  // and in constants. We want to visit and produce errors for these
  // individually because the functions will have location information
  // we want to include in errors

  let function_panics = {
    use func <- list.flat_map(extract_functions(input_module))
    use stmt <- list.flat_map(func.body)

    let expr = case stmt {
      glance.Use(_, expr) -> expr
      glance.Assignment(value: val, ..) -> val
      glance.Expression(expr) -> expr
    }

    do_visit_expressions(expr, [], fn(exp) {
      case exp {
        glance.Panic(_) -> {
          Some(PanicFoundInFunction(_, func.name))
        }
        _ -> None
      }
    })
    |> option.values
  }
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
  do f: fn(glance.Expression) -> a,
) -> List(a) {
  let funcs = extract_functions(input)
  let consts = extract_constants(input)

  // Visit all the expressions in top level functions
  let func_results = {
    use func <- list.flat_map(funcs)
    use stmt <- list.flat_map(func.body)

    let expr = case stmt {
      glance.Use(_, expr) -> expr
      glance.Assignment(value: val, ..) -> val
      glance.Expression(expr) -> expr
    }

    do_visit_expressions(expr, [], f)
  }

  // Visit all the expressions in constants
  let const_results =
    list.flat_map(consts, fn(c) { do_visit_expressions(c.value, [], f) })
  list.append(func_results, const_results)
}

fn do_visit_expressions(
  input: glance.Expression,
  acc: List(a),
  do f: fn(glance.Expression) -> a,
) -> List(a) {
  let acc = [f(input), ..acc]
  case input {
    glance.Todo(_)
    | glance.Panic(_)
    | glance.Int(_)
    | glance.Float(_)
    | glance.String(_)
    | glance.Variable(_) -> acc

    glance.NegateInt(expr) | glance.NegateBool(expr) ->
      do_visit_expressions(expr, acc, f)

    glance.Block(stmts) -> {
      use stmt <- list.flat_map(stmts)
      case stmt {
        // In a use statement, the "expression" should be
        glance.Use(_, expr) -> do_visit_expressions(expr, acc, f)
        glance.Assignment(value: expr, ..) -> do_visit_expressions(expr, acc, f)
        glance.Expression(expr) -> do_visit_expressions(expr, acc, f)
      }
    }
    glance.Tuple(exprs) -> list.flat_map(exprs, do_visit_expressions(_, acc, f))
    glance.List(elements, rest) -> {
      let elms = list.flat_map(elements, do_visit_expressions(_, acc, f))
      case rest {
        Some(expr) -> list.append(elms, do_visit_expressions(expr, acc, f))
        None -> elms
      }
    }
    glance.Fn(arguments: _, return_annotation: _, body: body) -> {
      use stmt <- list.flat_map(body)
      case stmt {
        // In a use statement, the "expression" should be
        glance.Use(_, expr) -> do_visit_expressions(expr, acc, f)
        glance.Assignment(value: expr, ..) -> do_visit_expressions(expr, acc, f)
        glance.Expression(expr) -> do_visit_expressions(expr, acc, f)
      }
    }
    glance.RecordUpdate(
        module: _,
        constructor: _,
        record: record,
        fields: fields,
      ) -> {
      {
        use #(_, expr) <- list.flat_map(fields)
        do_visit_expressions(expr, acc, f)
      }
      |> list.append(do_visit_expressions(record, acc, f))
    }
    glance.FieldAccess(container: container, label: _) ->
      do_visit_expressions(container, acc, f)
    glance.Call(function, arguments) -> {
      list.flat_map(arguments, fn(arg) {
        do_visit_expressions(arg.item, acc, f)
      })
      |> list.append(do_visit_expressions(function, acc, f))
    }
    glance.TupleIndex(tuple, index: _) -> {
      do_visit_expressions(tuple, acc, f)
    }
    glance.FnCapture(
        label: _,
        function: function,
        arguments_before: arguments_before,
        arguments_after: arguments_after,
      ) -> {
      list.flat_map(arguments_before, fn(arg) {
        do_visit_expressions(arg.item, acc, f)
      })
      |> list.append(
        list.flat_map(arguments_after, fn(arg) {
          do_visit_expressions(arg.item, acc, f)
        }),
      )
      |> list.append(do_visit_expressions(function, acc, f))
    }
    glance.BitString(segments) -> {
      use #(expr, _) <- list.flat_map(segments)
      do_visit_expressions(expr, acc, f)
    }
    glance.Case(subjects, clauses) -> {
      list.flat_map(subjects, do_visit_expressions(_, acc, f))
      |> list.append(
        list.flat_map(clauses, fn(c) {
          let glance.Clause(_, guard, body) = c
          let body = do_visit_expressions(body, acc, f)
          case guard {
            Some(expr) -> list.append(body, do_visit_expressions(expr, acc, f))
            None -> body
          }
        }),
      )
    }
    glance.BinaryOperator(name: _, left: left, right: right) -> {
      do_visit_expressions(left, acc, f)
      |> list.append(do_visit_expressions(right, acc, f))
    }
  }
}
