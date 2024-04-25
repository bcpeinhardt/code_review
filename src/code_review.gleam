//// A linter for Gleam, written in Gleam. Staring with a very basic prototype
//// setup: read in the gleam files, iterate over them searching for common
//// patterns based on the glance module that gets parsed, and produce messages
//// pointing out the issue.

import code_review/internal/project.{type Project}
import code_review/rule.{type Rule}
import glance
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result

// RUNNING THE LINTER ----------------------------------------------------------

pub fn main(rules: List(Rule)) -> Nil {
  case run(on: project.root(), with_rules: rules) {
    Ok(rule_errors) ->
      list.each(rule_errors, fn(rule_error) {
        rule.pretty_print_error(rule_error)
        |> io.println_error
      })

    Error(project_error) ->
      project.explain_error(project_error)
      |> io.println_error
  }
}

/// Run the linter for a project at the given path.
///
fn run(
  on project_root: String,
  with_rules rules: List(Rule),
) -> Result(List(rule.Error), project.Error) {
  use knowledge_base <- result.try(project.read(project_root))
  Ok(visit(knowledge_base, rules))
}

/// TODO: once Gleam goes v1.1 this could be marked as internal, I don't think
///       we should expose it in the public API.
///       I feel the `code_review` module should only publicly expose the `main`
///       function that acts as the CLI entry point.
pub fn visit(project: Project, rules: List(Rule)) -> List(rule.Error) {
  let rule_visitors = list.map(rules, rule.module_visitor)

  use acc, project.Module(path, module) <- list.fold(project.src_modules, [])
  visit_module(module, rule_visitors)
  |> list.flat_map(fn(rule) { rule.get_errors() })
  |> list.map(rule.set_error_path(_, path))
  |> list.append(acc)
}

fn visit_module(
  module: glance.Module,
  rules: List(rule.ModuleVisitor),
) -> List(rule.ModuleVisitor) {
  let glance.Module(constants: constants, functions: functions, ..) = module

  rules
  |> visit_constants(constants)
  |> visit_functions(functions)
}

fn visit_constants(
  rules: List(rule.ModuleVisitor),
  constants: List(glance.Definition(glance.Constant)),
) -> List(rule.ModuleVisitor) {
  use rules_acc, constant_with_definition <- list.fold(constants, rules)
  let glance.Definition(_, c) = constant_with_definition
  do_visit_expressions(rules_acc, c.value)
}

fn visit_functions(
  rules: List(rule.ModuleVisitor),
  functions: List(glance.Definition(glance.Function)),
) -> List(rule.ModuleVisitor) {
  list.fold(functions, rules, visit_function)
}

fn visit_function(
  rules_before_visit: List(rule.ModuleVisitor),
  function: glance.Definition(glance.Function),
) -> List(rule.ModuleVisitor) {
  let rules_after_function_visit: List(rule.ModuleVisitor) =
    apply_visitor(function, rules_before_visit, fn(rule) {
      rule.function_visitor
    })

  let glance.Definition(_, func) = function
  list.fold(func.body, rules_after_function_visit, visit_statement)
}

fn visit_statement(
  rules: List(rule.ModuleVisitor),
  statement: glance.Statement,
) -> List(rule.ModuleVisitor) {
  case statement {
    glance.Use(_, expr) -> do_visit_expressions(rules, expr)
    glance.Assignment(value: val, ..) -> do_visit_expressions(rules, val)
    glance.Expression(expr) -> do_visit_expressions(rules, expr)
  }
}

fn apply_visitor(
  a: a,
  rules: List(rule.ModuleVisitor),
  get_visitor: fn(rule.ModuleVisitor) ->
    option.Option(fn(a) -> rule.ModuleVisitor),
) -> List(rule.ModuleVisitor) {
  use rule <- list.map(rules)
  case get_visitor(rule) {
    option.None -> rule
    option.Some(visitor) -> visitor(a)
  }
}

fn do_visit_expressions(
  rules_before_visit: List(rule.ModuleVisitor),
  input: glance.Expression,
) -> List(rule.ModuleVisitor) {
  let rules: List(rule.ModuleVisitor) =
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
  initial_rules: List(rule.ModuleVisitor),
  statements: List(glance.Statement),
) -> List(rule.ModuleVisitor) {
  use rules, stmt <- list.fold(statements, initial_rules)
  case stmt {
    glance.Use(_, expr) -> do_visit_expressions(rules, expr)
    glance.Assignment(value: expr, ..) -> do_visit_expressions(rules, expr)
    glance.Expression(expr) -> do_visit_expressions(rules, expr)
  }
}
