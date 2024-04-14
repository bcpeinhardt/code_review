import glance
import gleam/list
import gleam/option
import gleam/string

// TYPES -----------------------------------------------------------------------

pub opaque type Rule {
  Rule(name: String, module_visitor: fn() -> ModuleVisitor)
}

pub type ModuleVisitor {
  ModuleVisitor(
    expression_visitor: option.Option(fn(glance.Expression) -> ModuleVisitor),
    function_visitor: option.Option(
      fn(glance.Definition(glance.Function)) -> ModuleVisitor,
    ),
    get_errors: fn() -> List(Error),
  )
}

pub opaque type RuleSchema(context) {
  RuleSchema(
    name: String,
    initial_context: context,
    function_visitor: option.Option(
      fn(glance.Definition(glance.Function), context) ->
        ErrorsAndContext(context),
    ),
    expression_visitor: option.Option(
      fn(glance.Expression, context) -> ErrorsAndContext(context),
    ),
  )
}

/// An error reported by rules.
///
pub opaque type Error {
  Error(
    path: String,
    location_identifier: String,
    rule: String,
    message: String,
    details: List(String),
  )
}

type ErrorsAndContext(context) =
  #(List(Error), context)

// BUILDING RULES --------------------------------------------------------------

pub fn to_rule(schema: RuleSchema(context)) -> Rule {
  Rule(name: schema.name, module_visitor: fn() {
    rule_to_operations(schema, #([], schema.initial_context))
  })
}

pub fn new(name: String, initial_context: context) -> RuleSchema(context) {
  RuleSchema(
    name: name,
    initial_context: initial_context,
    function_visitor: option.None,
    expression_visitor: option.None,
  )
}

pub fn with_function_visitor(
  schema: RuleSchema(context),
  visitor: fn(glance.Definition(glance.Function), context) ->
    ErrorsAndContext(context),
) -> RuleSchema(context) {
  let new_visitor = combine_visitors(visitor, schema.function_visitor)
  RuleSchema(..schema, function_visitor: option.Some(new_visitor))
}

pub fn with_simple_function_visitor(
  schema: RuleSchema(context),
  visitor: fn(glance.Definition(glance.Function)) -> List(Error),
) -> RuleSchema(context) {
  let simple_visitor = fn(fn_, context) { #(visitor(fn_), context) }
  with_function_visitor(schema, simple_visitor)
}

pub fn with_expression_visitor(
  schema: RuleSchema(context),
  visitor: fn(glance.Expression, context) -> ErrorsAndContext(context),
) -> RuleSchema(context) {
  let new_visitor = combine_visitors(visitor, schema.expression_visitor)
  RuleSchema(..schema, expression_visitor: option.Some(new_visitor))
}

pub fn with_simple_expression_visitor(
  schema: RuleSchema(context),
  visitor: fn(glance.Expression) -> List(Error),
) -> RuleSchema(context) {
  let simple_visitor = fn(expr, context) { #(visitor(expr), context) }
  with_expression_visitor(schema, simple_visitor)
}

fn combine_visitors(
  new_visitor: fn(a, context) -> ErrorsAndContext(context),
  previous_visitor: option.Option(fn(a, context) -> ErrorsAndContext(context)),
) -> fn(a, context) -> ErrorsAndContext(context) {
  case previous_visitor {
    option.None -> new_visitor
    option.Some(previous_visitor) -> fn(a, context) {
      let #(errors_after_first_visit, context_after_first_visit) =
        previous_visitor(a, context)
      let #(errors_after_second_visit, context_after_second_visit) =
        new_visitor(a, context_after_first_visit)
      let all_errors =
        list.append(errors_after_first_visit, errors_after_second_visit)

      #(all_errors, context_after_second_visit)
    }
  }
}

fn set_rule_name_on_errors(errors: List(Error), name: String) -> List(Error) {
  list.map(errors, fn(error) { Error(..error, rule: name) })
}

fn rule_to_operations(
  schema: RuleSchema(context),
  errors_and_context: ErrorsAndContext(context),
) -> ModuleVisitor {
  let raise = fn(new_errors_and_context: ErrorsAndContext(context)) {
    // Instead of being recursive, this could simply mutate `errors_and_context`
    // and return the originally created `ModuleVisitor` below.
    rule_to_operations(schema, new_errors_and_context)
  }

  ModuleVisitor(
    expression_visitor: create_visitor(
      schema.name,
      raise,
      errors_and_context,
      schema.expression_visitor,
    ),
    function_visitor: create_visitor(
      schema.name,
      raise,
      errors_and_context,
      schema.function_visitor,
    ),
    get_errors: fn() { errors_and_context.0 },
  )
}

fn create_visitor(
  rule_name: String,
  raise: fn(ErrorsAndContext(context)) -> a,
  errors_and_context: ErrorsAndContext(context),
  maybe_visitor: option.Option(fn(b, context) -> ErrorsAndContext(context)),
) -> option.Option(fn(b) -> a) {
  use visitor <- option.map(maybe_visitor)
  fn(node) {
    raise(accumulate(
      rule_name,
      fn(context) { visitor(node, context) },
      errors_and_context,
    ))
  }
}

/// Concatenate the errors of the previous step and of the last step, and take
/// the last step's context.
///
fn accumulate(
  rule_name: String,
  visitor: fn(context) -> ErrorsAndContext(context),
  errors_and_context: ErrorsAndContext(context),
) {
  let #(previous_errors, previous_context) = errors_and_context
  let #(new_errors, new_context) = visitor(previous_context)

  #(
    list.append(set_rule_name_on_errors(new_errors, rule_name), previous_errors),
    new_context,
  )
}

// GETTING A VISITORS OUT OF RULES ---------------------------------------------

pub fn module_visitor(from rule: Rule) -> ModuleVisitor {
  rule.module_visitor()
}

// RULE ERRORS -----------------------------------------------------------------

pub fn error(
  message message: String,
  details details: List(String),
  at location: String,
) -> Error {
  Error(
    path: "",
    location_identifier: location,
    rule: "",
    message: message,
    details: details,
  )
}

/// TODO: this could be internal as well.
///
pub fn set_error_path(error: Error, path: String) -> Error {
  Error(..error, path: path)
}

/// TODO: Just an initial repr for testing, someone good at making things pretty
///       will need to update this.
///
pub fn pretty_print_error(error: Error) -> String {
  let Error(
    path: path,
    location_identifier: location_identifier,
    rule: rule,
    message: message,
    details: details,
  ) = error

  [
    "Path: " <> path <> "\n",
    "Location Identifier: " <> location_identifier,
    "Rule: " <> rule,
    "Error: " <> message,
    "Details: " <> string.join(details, with: "\n"),
  ]
  |> string.join(with: "\n")
}
