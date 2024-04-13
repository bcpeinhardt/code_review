//// A linter for Gleam, written in Gleam. 

import filepath
import glance
import gleam/dict.{type Dict}
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import rule.{type Rule, type RuleViolation, Rule, RuleViolation}
import rules/no_panic
import rules/no_unnecessary_string_concatenation
import simplifile
import tom

const default_ruleset = [
  no_panic.rule,
  no_unnecessary_string_concatenation.rule,
]

/// The global error type for the linter.
/// This is *NOT* related to the linting, it's
/// the error type for the linter itself.
/// 
pub type CodeReviewError {
  CouldNotGetCurrentDirectory
  CouldNotGetSourceFiles
  CouldNotReadAllSourceFiles
  CouldNotParseAllModules
  CouldNotReadGleamToml
  CouldNotParseGleamToml
}

/// Format an error for printing
/// 
fn code_review_error_to_error_message(input: CodeReviewError) -> String {
  case input {
    CouldNotGetCurrentDirectory -> "Error: Could not get current directory"
    CouldNotGetSourceFiles -> "Error: Could not get source files"
    CouldNotReadAllSourceFiles -> "Error: Could not read all source files"
    CouldNotParseAllModules -> "Error: Could not parse all modules"
    CouldNotReadGleamToml -> "Error: Could not read gleam.toml"
    CouldNotParseGleamToml -> "Error: Could not parse gleam.toml"
  }
}

/// Responsible for printing a rule error to the console
/// TODO: Just an initial repr for testing, someone good at making things pretty 
/// will need to update this
///
pub fn display_rule_violation(input: RuleViolation) -> String {
  "Path: "
  <> input.path
  <> "\n"
  <> "\nLocation Identifier: "
  <> input.location_identifier
  <> "\nRule: "
  <> input.rule
  <> "\nError: "
  <> input.message
  <> "\nDetails: "
  <> string.join(input.details, with: "\n")
}

// Represents information the linter has access to. We want this to include
// as much as possible and provide ergonomic accessors for querying it.
//
type KnowledgeBase {
  KnowledgeBase(
    // The gleam modules in the src folder
    //
    src_modules: List(Module),
    // The gleam.toml
    //
    gloml: Dict(String, tom.Toml),
  )
}

// Represents a parsed code module.
//
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

pub fn main() -> Result(Nil, CodeReviewError) {
  // Get the current directory
  use current_directory <- result.map(
    simplifile.current_directory()
    |> result.replace_error(CouldNotGetCurrentDirectory),
  )

  // Run the linter
  case run(on: current_directory) {
    // If everything worked okay, display
    // each rule violation
    Ok(rule_violations) -> {
      use rule_violation <- list.each(rule_violations)
      rule_violation
      |> display_rule_violation
      |> io.println
    }
    // If errored, print any errors that occured
    Error(error) ->
      error
      |> code_review_error_to_error_message
      |> io.print_error
  }
}

// Run the linter on a project at `directory`
pub fn run(on directory: String) -> Result(List(RuleViolation), CodeReviewError) {
  // Read in all the information the linter needs to make decisions from the project
  use knowledge_base <- result.try(read_project(directory))

  // Look over all the information to generate the rule violations
  let rule_violations = search(over: knowledge_base, applying: default_ruleset)
  Ok(rule_violations)
}

// Read's in all the information the linter needs 
// from the project
fn read_project(
  project_root_path: String,
) -> Result(KnowledgeBase, CodeReviewError) {
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

  // Parse the source files in "modules"
  use modules <- result.try({
    // map over the files
    use file <- list.try_map(src_files)

    // Read each files contents as src code
    use content <- result.try(
      simplifile.read(file)
      |> result.replace_error(CouldNotReadAllSourceFiles),
    )

    // Try to parse the files content as source code
    use module <- result.try(
      glance.module(content)
      |> result.replace_error(CouldNotParseAllModules),
    )

    // Return the parsed glance module indexed by the file path
    Ok(Module(file, module))
  })

  Ok(KnowledgeBase(src_modules: modules, gloml: gloml))
}

fn search(
  over kb: KnowledgeBase,
  applying rules: List(Rule),
) -> List(RuleViolation) {
  use acc, Module(path, module) <- list.fold(kb.src_modules, [])
  visit_module(path, rules, module)
  |> list.append(acc)
}

fn visit_module(
  path: String,
  rules: List(Rule),
  input_module: glance.Module,
) -> List(RuleViolation) {
  visit_expressions(input_module, rules)
  |> list.map(fn(error) { RuleViolation(..error, path: path) })
}

// Extracts all the top level functions out of a glance module.
fn extract_functions(from input: glance.Module) -> List(glance.Function) {
  let glance.Module(functions: function_defs, ..) = input
  use glance.Definition(_, func) <- list.map(function_defs)
  func
}

// Extracts all the constants out of a glance module
fn extract_constants(from input: glance.Module) -> List(glance.Constant) {
  let glance.Module(constants: consts, ..) = input
  use glance.Definition(_, c) <- list.map(consts)
  c
}

fn visit_expressions(
  input: glance.Module,
  rules: List(Rule),
) -> List(RuleViolation) {
  let funcs = extract_functions(input)
  let consts = extract_constants(input)

  let f = fn(location_identifier, expr) {
    list.flat_map(rules, fn(rule) {
      list.flat_map(rule.expression_visitors, fn(visitor) { visitor(expr) })
      |> list.map(fn(error) {
        RuleViolation(
          ..error,
          rule: rule.name,
          location_identifier: location_identifier,
        )
      })
    })
  }

  // Visit all the expressions in top level functions
  let func_results: List(RuleViolation) = {
    use func <- list.flat_map(funcs)
    use stmt <- list.flat_map(func.body)

    let expr = case stmt {
      glance.Use(_, expr) -> expr
      glance.Assignment(value: val, ..) -> val
      glance.Expression(expr) -> expr
    }

    do_visit_expressions(expr, [], fn(expr) { f(func.name, expr) })
    |> list.flatten
  }

  // Visit all the expressions in constants
  let const_results: List(RuleViolation) =
    list.flat_map(consts, fn(c) {
      do_visit_expressions(c.value, [], fn(expr) { f(c.name, expr) })
    })
    |> list.flatten
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
