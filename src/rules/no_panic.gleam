import glance
import rule.{type Rule, type RuleError}

pub fn rule() -> Rule {
  rule.new("no_panic", initial_context)
  |> rule.with_function_visitor(function_visitor)
  |> rule.with_expression_visitor(expression_visitor)
  |> rule.to_rule
}

type Context {
  Context(current_location: String)
}

const initial_context: Context = Context(current_location: "")

fn function_visitor(
  function: glance.Definition(glance.Function),
  _: Context,
) -> #(List(never), Context) {
  let glance.Definition(_, func) = function
  #([], Context(current_location: func.name))
}

fn expression_visitor(
  expr: glance.Expression,
  context: Context,
) -> #(List(RuleError), Context) {
  case expr {
    glance.Panic(_) -> {
      #(
        [
          rule.error(
            message: "Found `panic`",
            details: [
              "This keyword should almost never be used! It may be useful in initial prototypes and scripts, but its use in a library or production application is a sign that the design could be improved.",
              "With well designed types the type system can typically be used to make these invalid states unrepresentable.",
            ],
            location: context.current_location,
          ),
        ],
        context,
      )
    }
    _ -> #([], context)
  }
}
