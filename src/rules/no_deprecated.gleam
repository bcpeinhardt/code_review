import glance
import gleam/list
import gleam/set.{type Set}
import rule.{type Rule, type RuleError}

pub fn rule() -> Rule {
  rule.new("no_deprecated", initial_context())
  |> rule.with_function_visitor(function_visitor)
  |> rule.with_expression_visitor(expression_visitor)
  |> rule.to_rule
}

type Context {
  Context(deprecated_functions: Set(String), current_location: String)
}

fn initial_context() {
  Context(deprecated_functions: set.new(), current_location: "")
}

fn function_visitor(
  function: glance.Definition(glance.Function),
  context: Context,
) -> #(List(never), Context) {
  let glance.Definition(attributes, func) = function
  let is_deprecated =
    list.any(attributes, fn(attribute) { attribute.name == "deprecated" })
  let deprecated_functions = case is_deprecated {
    True -> set.insert(context.deprecated_functions, func.name)
    False -> context.deprecated_functions
  }

  #(
    [],
    Context(
      deprecated_functions: deprecated_functions,
      current_location: func.name,
    ),
  )
}

fn expression_visitor(
  expr: glance.Expression,
  context: Context,
) -> #(List(RuleError), Context) {
  case expr {
    glance.Variable(name) ->
      case set.contains(context.deprecated_functions, name) {
        True -> #(
          [
            rule.error(
              message: "Found usage of deprecated function",
              details: ["Don't use this anymore."],
              location: context.current_location,
            ),
          ],
          context,
        )
        False -> #([], context)
      }
    _ -> #([], context)
  }
}
