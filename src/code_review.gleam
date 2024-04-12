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
import rule.{type Rule, type RuleError, Rule, RuleError}
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
  let errors = visit_knowledge_base(knowledge_base, config())
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
  visit_expressions(input_module, rules)
  |> list.map(fn(error) { RuleError(..error, path: path) })
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

fn visit_expressions(input: glance.Module, rules: List(Rule)) -> List(RuleError) {
  let funcs = extract_functions(input)
  let consts = extract_constants(input)

  let f = fn(location_identifier, expr) {
    apply_visitor(expr, rules, fn(rule) { rule.expression_visitors })
    |> list.map(fn(error) {
      RuleError(..error, location_identifier: location_identifier)
    })
  }

  // Visit all constants
  let results_after_const: List(RuleError) =
    list.fold(consts, [], fn(const_acc, c) {
      do_visit_expressions(c.value, const_acc, fn(expr) { f(c.name, expr) })
    })

  // Visit all top level functions
  let results_after_functions: List(RuleError) = {
    use acc0, func <- list.fold(funcs, results_after_const)
    use acc1, stmt <- list.fold(func.body, acc0)

    let expr = case stmt {
      glance.Use(_, expr) -> expr
      glance.Assignment(value: val, ..) -> val
      glance.Expression(expr) -> expr
    }

    do_visit_expressions(expr, acc1, fn(expr) { f(func.name, expr) })
  }

  results_after_functions
}

fn apply_visitor(
  a: a,
  rules: List(Rule),
  visitor_fn: fn(Rule) -> List(fn(a) -> List(RuleError)),
) {
  list.flat_map(rules, fn(rule) {
    list.flat_map(visitor_fn(rule), fn(visitor) { visitor(a) })
    |> list.map(fn(error) { RuleError(..error, rule: rule.name) })
  })
}

fn do_visit_expressions(
  input: glance.Expression,
  acc: List(RuleError),
  do f: fn(glance.Expression) -> List(RuleError),
) -> List(RuleError) {
  let acc: List(RuleError) = list.append(f(input), acc)
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
