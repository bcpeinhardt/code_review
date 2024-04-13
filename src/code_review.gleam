//// A linter for Gleam, written in Gleam. Staring with a very basic prototype setup:
//// Read in the gleam files, iterate over them searching for common patterns
//// based on the glance module that get's parsed, and produce messages pointing out 
//// the issue.

import filepath
import glance
import gleam/dict.{type Dict}
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import review_config.{config}
import rule.{type RuleError, RuleError}
import simplifile
import tom

pub type WhingeError {
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

// Responsible for printing a rule error to the console
// TODO: Just an initial repr for testing, someone good at making things pretty 
// will need to update this
pub fn display_rule_error(input: RuleError) -> String {
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

pub fn main() -> Result(Nil, WhingeError) {
  // Get the current directory
  use curr_dir <- result.map(
    simplifile.current_directory()
    |> result.replace_error(CouldNotGetCurrentDirectory),
  )

  // Run the linter
  case run(curr_dir) {
    Ok(errors) ->
      list.each(errors, fn(e) {
        e
        |> display_rule_error
        |> io.println
      })
    Error(e) ->
      io.print_error(
        e
        |> whinge_error_to_error_message,
      )
  }
}

// Run the linter on a project at `directory`
pub fn run(on directory: String) -> Result(List(RuleError), WhingeError) {
  use knowledge_base <- result.try(read_project(directory))
  let rule_visitors = list.map(config(), fn(rule) { rule.module_visitor() })
  let errors = visit_knowledge_base(knowledge_base, rule_visitors)
  Ok(errors)
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
      use content <- result.try(
        simplifile.read(file)
        |> result.replace_error(CouldNotReadAllSourceFiles),
      )
      use module <- result.try(
        glance.module(content)
        |> result.replace_error(CouldNotParseAllModules),
      )
      Ok(Module(file, module))
    }),
  )

  Ok(KnowledgeBase(src_modules: modules, gloml: gloml))
}

fn visit_knowledge_base(
  kb: KnowledgeBase,
  rules: List(rule.ModuleVisitorOperations),
) -> List(RuleError) {
  use acc, Module(path, module) <- list.fold(kb.src_modules, [])
  visit_module(module, rules)
  |> list.flat_map(fn(rule) { rule.get_errors() })
  |> list.map(fn(error) { RuleError(..error, path: path) })
  |> list.append(acc)
}

fn visit_module(
  input: glance.Module,
  rules: List(rule.ModuleVisitorOperations),
) -> List(rule.ModuleVisitorOperations) {
  let glance.Module(constants: constants, functions: functions, ..) = input

  // Visit all constants
  rules
  |> visit_constants(constants)
  |> visit_functions(functions)
}

fn visit_constants(
  rules: List(rule.ModuleVisitorOperations),
  constants: List(glance.Definition(glance.Constant)),
) -> List(rule.ModuleVisitorOperations) {
  use rules_acc, constant_with_definition <- list.fold(constants, rules)
  let glance.Definition(_, c) = constant_with_definition
  do_visit_expressions(rules_acc, c.value)
}

fn visit_functions(
  rules: List(rule.ModuleVisitorOperations),
  functions: List(glance.Definition(glance.Function)),
) -> List(rule.ModuleVisitorOperations) {
  list.fold(functions, rules, visit_function)
}

fn visit_function(
  rules_before_visit: List(rule.ModuleVisitorOperations),
  function: glance.Definition(glance.Function),
) -> List(rule.ModuleVisitorOperations) {
  let rules_after_function_visit: List(rule.ModuleVisitorOperations) =
    apply_visitor(function, rules_before_visit, fn(rule) {
      rule.function_visitor
    })

  let glance.Definition(_, func) = function
  list.fold(func.body, rules_after_function_visit, visit_statement)
}

fn visit_statement(
  rules: List(rule.ModuleVisitorOperations),
  statement: glance.Statement,
) -> List(rule.ModuleVisitorOperations) {
  case statement {
    glance.Use(_, expr) -> do_visit_expressions(rules, expr)
    glance.Assignment(value: val, ..) -> do_visit_expressions(rules, val)
    glance.Expression(expr) -> do_visit_expressions(rules, expr)
  }
}

fn apply_visitor(
  a: a,
  rules: List(rule.ModuleVisitorOperations),
  get_visitor: fn(rule.ModuleVisitorOperations) ->
    option.Option(fn(a) -> rule.ModuleVisitorOperations),
) -> List(rule.ModuleVisitorOperations) {
  use rule <- list.map(rules)
  case get_visitor(rule) {
    option.None -> rule
    option.Some(visitor) -> visitor(a)
  }
}

fn do_visit_expressions(
  rules_before_visit: List(rule.ModuleVisitorOperations),
  input: glance.Expression,
) -> List(rule.ModuleVisitorOperations) {
  let rules: List(rule.ModuleVisitorOperations) =
    apply_visitor(input, rules_before_visit, fn(rule) {
      rule.expression_visitor
    })

  case input {
    glance.Todo(_)
    | glance.Panic(_)
    | glance.Int(_)
    | glance.Float(_)
    | glance.String(_)
    | glance.Variable(_) -> rules

    glance.NegateInt(expr) | glance.NegateBool(expr) ->
      do_visit_expressions(rules, expr)

    glance.Block(statements) -> {
      visit_statements(rules, statements)
    }
    glance.Tuple(exprs) -> list.fold(exprs, rules, do_visit_expressions)
    glance.List(exprs, rest) -> {
      list.fold(exprs, rules, do_visit_expressions)
      |> fn(new_rules) {
        case rest {
          Some(rest_expr) -> do_visit_expressions(new_rules, rest_expr)
          None -> new_rules
        }
      }
    }
    glance.Fn(arguments: _, return_annotation: _, body: statements) -> {
      visit_statements(rules, statements)
    }
    glance.RecordUpdate(
        module: _,
        constructor: _,
        record: record,
        fields: fields,
      ) -> {
      let new_rules = do_visit_expressions(rules, record)

      use acc_rules, #(_, expr) <- list.fold(fields, new_rules)
      do_visit_expressions(acc_rules, expr)
    }
    glance.FieldAccess(container: container, label: _) ->
      do_visit_expressions(rules, container)
    glance.Call(function, arguments) -> {
      let new_rules = do_visit_expressions(rules, function)

      use acc_rules, arg <- list.fold(arguments, new_rules)
      do_visit_expressions(acc_rules, arg.item)
    }
    glance.TupleIndex(expr, index: _) -> {
      do_visit_expressions(rules, expr)
    }
    glance.FnCapture(
        label: _,
        function: function,
        arguments_before: arguments_before,
        arguments_after: arguments_after,
      ) -> {
      list.fold(
        list.append(arguments_before, arguments_after),
        rules,
        fn(acc_rules, arg) { do_visit_expressions(acc_rules, arg.item) },
      )
      |> do_visit_expressions(function)
    }
    glance.BitString(segments) -> {
      use acc_rules, #(expr, _) <- list.fold(segments, rules)
      do_visit_expressions(acc_rules, expr)
    }
    glance.Case(subjects, clauses) -> {
      let new_rules = list.fold(subjects, rules, do_visit_expressions)

      use acc_rules, c <- list.fold(clauses, new_rules)
      let glance.Clause(_, guard, body) = c
      let acc_rules_2 = do_visit_expressions(acc_rules, body)
      case guard {
        Some(expr) -> do_visit_expressions(rules, expr)
        None -> acc_rules_2
      }
    }
    glance.BinaryOperator(name: _, left: left, right: right) -> {
      rules
      |> do_visit_expressions(left)
      |> do_visit_expressions(right)
    }
  }
}

fn visit_statements(
  initial_rules: List(rule.ModuleVisitorOperations),
  statements: List(glance.Statement),
) -> List(rule.ModuleVisitorOperations) {
  use rules, stmt <- list.fold(statements, initial_rules)
  case stmt {
    glance.Use(_, expr) -> do_visit_expressions(rules, expr)
    glance.Assignment(value: expr, ..) -> do_visit_expressions(rules, expr)
    glance.Expression(expr) -> do_visit_expressions(rules, expr)
  }
}
