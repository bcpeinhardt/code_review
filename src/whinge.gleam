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
    path: String,
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

type Rule {
  Rule(
    name: String,
    expression_visitor: option.Option(
      fn(String, String, glance.Expression) -> List(RuleError),
    ),
  )
}

const no_panic_rule: Rule = Rule(
  name: "NoPanic",
  expression_visitor: Some(contains_panic_in_function_expression_visitor),
)

const no_unnecessary_concatenation_rule: Rule = Rule(
  name: "NoUnnecessaryStringConcatenation",
  expression_visitor: Some(unnecessary_concatenation_expression_visitor),
)

const config: List(Rule) = [no_panic_rule, no_unnecessary_concatenation_rule]

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
  let errors = visit_knowledge_base(knowledge_base, config)
  io.debug(errors)
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
    list.try_map(["src/debug.gleam"], fn(file) {
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

fn visit_knowledge_base(kb: KnowledgeBase, rules: List(Rule)) -> List(RuleError) {
  use acc, Module(path, module) <- list.fold(kb.src_modules, [])
  visit_module(path, rules, module)
  |> list.append(acc)
}

fn visit_module(
  path: String,
  rules: List(Rule),
  input_module: glance.Module,
) -> List(RuleError) {
  visit_expressions(input_module, fn(function_name, expr) {
    list.flat_map(rules, fn(rule) {
      case rule.expression_visitor {
        Some(visitor) -> visitor(path, function_name, expr)
        None -> []
      }
    })
  })
  |> list.flatten
}

fn contains_panic_in_function_expression_visitor(
  path: String,
  function_name: String,
  expr: glance.Expression,
) -> List(RuleError) {
  case expr {
    glance.Panic(_) -> {
      [
        RuleError(
          path: path,
          function_name: function_name,
          rule: "NoPanic",
          error: "Found `panic`",
          details: [
            "This keyword should almost never be used! It may be useful in initial prototypes and scripts, but its use in a library or production application is a sign that the design could be improved.",
            "With well designed types the type system can typically be used to make these invalid states unrepresentable.",
          ],
        ),
      ]
    }
    _ -> []
  }
}

fn unnecessary_concatenation_expression_visitor(
  path: String,
  function_name: String,
  expr: glance.Expression,
) -> List(RuleError) {
  let rule_name = "NoUnnecessaryStringConcatenation"
  case expr {
    glance.BinaryOperator(glance.Concatenate, glance.String(""), _)
    | glance.BinaryOperator(glance.Concatenate, _, glance.String("")) -> {
      [
        RuleError(
          path: path,
          function_name: function_name,
          rule: rule_name,
          error: "Unnecessary concatenation with an empty string",
          details: [
            "The result of adding an empty string to an expression is the expression itself.",
            "You can remove the concatenation with \"\".",
          ],
        ),
      ]
    }
    glance.BinaryOperator(
      glance.Concatenate,
      glance.String(_),
      glance.String(_),
    ) -> {
      [
        RuleError(
          path: path,
          function_name: function_name,
          rule: rule_name,
          error: "Unnecessary concatenation of string literals",
          details: [
            "Instead of concatenating these two string literals, they can be written as a single one.",
            "For instance, instead of \"a\" <> \"b\", you could write that as \"ab\".",
          ],
        ),
      ]
    }
    _ -> []
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
  do f: fn(String, glance.Expression) -> a,
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

    do_visit_expressions(expr, [], fn(expr) { f(func.name, expr) })
  }

  // Visit all the expressions in constants
  let const_results =
    list.flat_map(consts, fn(c) {
      do_visit_expressions(c.value, [], fn(expr) { f(c.name, expr) })
    })
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
      use sub_acc, stmt <- list.fold(stmts, acc)
      case stmt {
        // In a use statement, the "expression" should be
        glance.Use(_, expr) -> do_visit_expressions(expr, sub_acc, f)
        glance.Assignment(value: expr, ..) ->
          do_visit_expressions(expr, sub_acc, f)
        glance.Expression(expr) -> do_visit_expressions(expr, sub_acc, f)
      }
    }
    glance.Tuple(exprs) ->
      list.fold(exprs, acc, fn(sub_acc, expr) {
        do_visit_expressions(expr, sub_acc, f)
      })
    glance.List(elements, rest) -> {
      let new_acc =
        list.fold(elements, acc, fn(sub_acc, expr) {
          do_visit_expressions(expr, sub_acc, f)
        })
      case rest {
        Some(expr) -> do_visit_expressions(expr, new_acc, f)
        None -> new_acc
      }
    }
    glance.Fn(arguments: _, return_annotation: _, body: body) -> {
      use sub_acc, stmt <- list.fold(body, acc)
      case stmt {
        // In a use statement, the "expression" should be
        glance.Use(_, expr) -> do_visit_expressions(expr, sub_acc, f)
        glance.Assignment(value: expr, ..) ->
          do_visit_expressions(expr, sub_acc, f)
        glance.Expression(expr) -> do_visit_expressions(expr, sub_acc, f)
      }
    }
    glance.RecordUpdate(
      module: _,
      constructor: _,
      record: record,
      fields: fields,
    ) -> {
      {
        use sub_acc, #(_, expr) <- list.fold(fields, acc)
        do_visit_expressions(expr, sub_acc, f)
      }
      |> do_visit_expressions(record, _, f)
    }
    glance.FieldAccess(container: container, label: _) ->
      do_visit_expressions(container, acc, f)
    glance.Call(function, arguments) -> {
      list.fold(arguments, acc, fn(sub_acc, arg) {
        do_visit_expressions(arg.item, sub_acc, f)
      })
      |> do_visit_expressions(function, _, f)
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
      list.fold(
        list.append(arguments_before, arguments_after),
        acc,
        fn(sub_acc, arg) { do_visit_expressions(arg.item, sub_acc, f) },
      )
      |> do_visit_expressions(function, _, f)
    }
    glance.BitString(segments) -> {
      use sub_acc, #(expr, _) <- list.fold(segments, acc)
      do_visit_expressions(expr, sub_acc, f)
    }
    glance.Case(subjects, clauses) -> {
      let new_acc =
        list.fold(subjects, acc, fn(sub_acc, expr) {
          do_visit_expressions(expr, sub_acc, f)
        })
      list.fold(clauses, new_acc, fn(sub_acc, c) {
        let glance.Clause(_, guard, body) = c
        let sub_acc_2 = do_visit_expressions(body, sub_acc, f)
        case guard {
          Some(expr) -> do_visit_expressions(expr, sub_acc_2, f)
          None -> sub_acc_2
        }
      })
    }
    glance.BinaryOperator(name: _, left: left, right: right) -> {
      do_visit_expressions(left, acc, f)
      |> do_visit_expressions(right, _, f)
    }
  }
}
