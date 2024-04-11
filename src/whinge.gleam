//// A linter for Gleam, written in Gleam. Staring with a very basic prototype setup:
//// Read in the gleam files, iterate over them searching for common patterns
//// based on the glance module that get's parsed, and produce messages pointing out 
//// the issue.

import gleam/dict.{type Dict}
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import filepath
import glance
import simplifile
import tom

type WhingeError {
  CouldNotGetCurrentDirectory
  CouldNotGetSourceFiles
  CouldNotReadAllSourceFiles
  CouldNotParseAllModules
  CouldNotReadGleamToml
  CouldNotParseGleamToml
}

fn whinge_error_to_error_message(input: WhingeError) -> String {
  case input {
    CouldNotGetCurrentDirectory -> "Error: Could not get current directory"
    CouldNotGetSourceFiles -> "Error: Could not get source files"
    CouldNotReadAllSourceFiles -> "Error: Could not read all source files"
    CouldNotParseAllModules -> "Error: Could not parse all modules"
    CouldNotReadGleamToml -> "Error: Could not read gleam.toml"
    CouldNotParseGleamToml -> "Error: Could not parse gleam.toml"
  }
}

// Represents an error reported by a rule.
type RuleError {
  RuleError(
    module: String,
    function_name: String,
    rule: String,
    error: String,
    details: List(String),
  )
}

// Represents information the linter has access to. We want this to include
// as much as possible and provide ergonomic accessors for querying it.
type KnowledgeBase {
  KnowledgeBase(
    // The gleam modules in the src folder
    src_modules: List(Module),
    // The gleam.toml
    gloml: Dict(String, tom.Toml),
  )
}

type Module {
  Module(
    // The "name" of the module is the path from the root
    // of the project to the file with the .gleam ending removed.
    //
    name: String,
    // The parsed source code in the module
    //
    src: glance.Module,
  )
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
  use curr_dir <- result.try(
    simplifile.current_directory()
    |> result.replace_error(CouldNotGetCurrentDirectory),
  )
  use knowledge_base <- result.try(read_project(curr_dir))
  io.debug(contains_panics(knowledge_base))
  Ok(Nil)
}

// Read's in all the information the linter needs 
// from the project
fn read_project(project_root_path: String) -> Result(KnowledgeBase, WhingeError) {
  // Read and parse the gleam.toml
  use gloml_src <- result.try(
    simplifile.read(filepath.join(project_root_path, "gleam.toml"))
    |> result.replace_error(CouldNotReadGleamToml),
  )
  use gloml <- result.try(
    tom.parse(gloml_src)
    |> result.replace_error(CouldNotParseGleamToml),
  )
  // Read in the source modules
  use src_files <- result.try(
    simplifile.get_files(filepath.join(project_root_path, "src"))
    |> result.replace_error(CouldNotGetSourceFiles),
  )
  use modules <- result.try(
    list.try_map(src_files, fn(file) {
      let path =
        file
        |> string.drop_right(6)
      use content <- result.try(
        simplifile.read(file)
        |> result.replace_error(CouldNotReadAllSourceFiles),
      )
      use module <- result.try(
        glance.module(content)
        |> result.replace_error(CouldNotParseAllModules),
      )
      Ok(Module(path, module))
    }),
  )

  Ok(KnowledgeBase(src_modules: modules, gloml: gloml))
}

fn contains_panics(kb: KnowledgeBase) -> List(RuleError) {
  use acc, Module(path, module) <- list.fold(kb.src_modules, [])
  single_module_contains_panic(module)
  |> list.append(concat_string_literals(module))
  |> list.map(fn(f) { f(path) })
  |> list.append(acc)
}

fn single_module_contains_panic(
  input_module: glance.Module,
) -> List(fn(String) -> RuleError) {
  // Panics are "expressions", so they'll only be found in functions
  // and in constants.

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
          Some(RuleError(
            module: _,
            function_name: func.name,
            rule: "PanicFoundInFunction",
            error: "Found `panic`",
            details: [
              "This keyword should almost never be used! It may be useful in initial prototypes and scripts, but its use in a library or production application is a sign that the design could be improved.",
              "With well designed types the type system can typically be used to make these invalid states unrepresentable.",
            ],
          ))
        }
        _ -> None
      }
    })
    |> option.values
  }

  // I don't think this is actually possible in Gleam, but it's
  // possible within the logical structur of Glance so I'll keep
  // it for now
  let constant_panics = {
    use const_ <- list.flat_map(extract_constants(input_module))
    do_visit_expressions(const_.value, [], fn(exp) {
      contains_panic_in_function_expression_visitor(const_.name, exp)
    })
    |> option.values
  }

  list.append(constant_panics, function_panics)
}

fn contains_panic_in_function_expression_visitor(
  function_name: String,
  expr: glance.Expression,
) {
  case expr {
    glance.Panic(_) -> {
      Some(RuleError(
        module: _,
        function_name: function_name,
        rule: "PanicFoundInFunction",
        error: "Found `panic`",
        details: [
          "This keyword should almost never be used! It may be useful in initial prototypes and scripts, but its use in a library or production application is a sign that the design could be improved.",
          "With well designed types the type system can typically be used to make these invalid states unrepresentable.",
        ],
      ))
    }
    _ -> None
  }
}

fn contains_panic_in_constant_expression_visitor(
  function_name: String,
  expr: glance.Expression,
) {
  case expr {
    glance.Panic(_) -> {
      Some(RuleError(
        module: _,
        function_name: function_name,
        rule: "PanicFoundInConstant",
        error: "Found `panic`",
        details: [
          "Using `panic` in a constant will prevent the application from running. It is only useful in functions, and even then, it should rarely be used.",
        ],
      ))
    }
    _ -> None
  }
}

fn concat_string_literals(
  input_module: glance.Module,
) -> List(fn(String) -> RuleError) {
  // Panics are "expressions", so they'll only be found in functions
  // and in constants. We want to visit and produce errors for these
  // individually because the functions will have location information
  // we want to include in errors

  let rule = {
    use func <- list.flat_map(extract_functions(input_module))
    use stmt <- list.flat_map(func.body)

    let expr = case stmt {
      glance.Use(_, expr) -> expr
      glance.Assignment(value: val, ..) -> val
      glance.Expression(expr) -> expr
    }

    do_visit_expressions(expr, [], fn(expr_) {
      unnecessary_concatenation_expression_visitor(func.name, expr_)
    })
    |> option.values
  }
}

fn unnecessary_concatenation_expression_visitor(
  function_name: String,
  expr: glance.Expression,
) {
  let rule_name = "UnnecessaryStringConcatenation"
  case expr {
    glance.BinaryOperator(glance.Concatenate, glance.String(""), _)
    | glance.BinaryOperator(glance.Concatenate, _, glance.String("")) -> {
      Some(RuleError(
        module: _,
        function_name: function_name,
        rule: rule_name,
        error: "Unnecessary concatenation with an empty string",
        details: [
          "The result of adding an empty string to an expression is the expression itself.",
          "You can remove the concatenation with \"\".",
        ],
      ))
    }
    glance.BinaryOperator(
      glance.Concatenate,
      glance.String(_),
      glance.String(_),
    ) -> {
      Some(RuleError(
        module: _,
        function_name: function_name,
        rule: rule_name,
        error: "Unnecessary concatenation of string literals",
        details: [
          "Instead of concatenating these two string literals, they can be written as a single one.",
          "For instance, instead of \"a\" <> \"b\", you could write that as \"ab\".",
        ],
      ))
    }
    _ -> None
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
