import glance
import gleam/list
import gleam/option

pub type RuleSchema(context) {
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

pub fn to_rule(schema: RuleSchema(context)) -> Rule {
  Rule(name: schema.name, module_visitor: fn() {
    rule_to_operations(schema, #([], schema.initial_context))
  })
}

pub type Rule {
  Rule(name: String, module_visitor: fn() -> ModuleVisitorOperations)
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
  RuleSchema(
    ..schema,
    function_visitor: option.Some(combine_visitors(
      visitor,
      schema.function_visitor,
    )),
  )
}

pub fn with_simple_function_visitor(
  schema: RuleSchema(context),
  visitor: fn(glance.Definition(glance.Function)) -> List(RuleError),
) -> RuleSchema(context) {
  RuleSchema(
    ..schema,
    function_visitor: option.Some(combine_visitors(
      fn(node, context) { #(visitor(node), context) },
      schema.function_visitor,
    )),
  )
}

pub fn with_expression_visitor(
  schema: RuleSchema(context),
  visitor: fn(glance.Expression, context) -> ErrorsAndContext(context),
) -> RuleSchema(context) {
  RuleSchema(
    ..schema,
    expression_visitor: option.Some(combine_visitors(
      visitor,
      schema.expression_visitor,
    )),
  )
}

pub fn with_simple_expression_visitor(
  schema: RuleSchema(context),
  visitor: fn(glance.Expression) -> List(RuleError),
) -> RuleSchema(context) {
  RuleSchema(
    ..schema,
    expression_visitor: option.Some(combine_visitors(
      fn(node, context) { #(visitor(node), context) },
      schema.expression_visitor,
    )),
  )
}

fn combine_visitors(
  new_visitor: fn(a, context) -> ErrorsAndContext(context),
  maybe_previous_visitor: option.Option(
    fn(a, context) -> ErrorsAndContext(context),
  ),
) {
  case maybe_previous_visitor {
    option.None -> new_visitor
    option.Some(previous_visitor) -> fn(a: a, context: context) {
      let #(errors_after_first_visit, context_after_first_visit) =
        previous_visitor(a, context)
      let #(errors_after_second_visit, context_after_second_visit) =
        new_visitor(a, context_after_first_visit)

      #(
        list.append(errors_after_first_visit, errors_after_second_visit),
        context_after_second_visit,
      )
    }
  }
}

fn set_rule_name_on_errors(
  errors: List(RuleError),
  name: String,
) -> List(RuleError) {
  list.map(errors, fn(error) { RuleError(..error, rule: name) })
}

// Represents an error reported by a rule.
pub type RuleError {
  RuleError(
    path: String,
    location_identifier: String,
    rule: String,
    message: String,
    details: List(String),
  )
}

pub fn error(
  message message: String,
  details details: List(String),
) -> RuleError {
  RuleError(
    path: "",
    location_identifier: "",
    rule: "",
    message: message,
    details: details,
  )
}

type ErrorsAndContext(context) =
  #(List(RuleError), context)

pub type ModuleVisitorOperations {
  ModuleVisitorOperations(
    expression_visitor: option.Option(
      fn(glance.Expression) -> ModuleVisitorOperations,
    ),
    function_visitor: option.Option(
      fn(glance.Definition(glance.Function)) -> ModuleVisitorOperations,
    ),
    get_errors: fn() -> List(RuleError),
  )
}

fn rule_to_operations(
  schema: RuleSchema(context),
  errors_and_context: ErrorsAndContext(context),
) -> ModuleVisitorOperations {
  let raise = fn(new_errors_and_context: ErrorsAndContext(context)) {
    // Instead of being recursive, this could simply mutate `errors_and_context`
    // and return the originally created `ModuleVisitorOperations` below.
    rule_to_operations(schema, new_errors_and_context)
  }

  ModuleVisitorOperations(
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

/// Concatenate the errors of the previous step and of the last step, and take the last step's context.
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
