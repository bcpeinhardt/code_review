import glance
import rule.{type Rule, type RuleError}

pub fn rule() -> Rule {
  rule.new("NoUnnecessaryStringConcatenation", initial_context)
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
    glance.BinaryOperator(glance.Concatenate, glance.String(""), _)
    | glance.BinaryOperator(glance.Concatenate, _, glance.String("")) -> {
      #(
        [
          rule.error(
            message: "Unnecessary concatenation with an empty string",
            details: [
              "The result of adding an empty string to an expression is the expression itself.",
              "You can remove the concatenation with \"\".",
            ],
            location: context.current_location,
          ),
        ],
        context,
      )
    }
    glance.BinaryOperator(
        glance.Concatenate,
        glance.String(_),
        glance.String(_),
      ) -> {
      #(
        [
          rule.error(
            message: "Unnecessary concatenation of string literals",
            details: [
              "Instead of concatenating these two string literals, they can be written as a single one.",
              "For instance, instead of \"a\" <> \"b\", you could write that as \"ab\".",
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
