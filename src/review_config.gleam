import gleam/option
import glance
import rule.{type Rule, type RuleError, Rule, RuleError}

pub const config: List(Rule) = [
  no_panic_rule,
  no_unnecessary_concatenation_rule,
]

pub const no_panic_rule: Rule = Rule(
  name: "NoPanic",
  expression_visitor: option.Some(contains_panic_in_function_expression_visitor),
)

pub const no_unnecessary_concatenation_rule: Rule = Rule(
  name: "NoUnnecessaryStringConcatenation",
  expression_visitor: option.Some(unnecessary_concatenation_expression_visitor),
)

pub fn contains_panic_in_function_expression_visitor(
  expr: glance.Expression,
) -> List(RuleError) {
  case expr {
    glance.Panic(_) -> {
      [
        rule.error(message: "Found `panic`", details: [
          "This keyword should almost never be used! It may be useful in initial prototypes and scripts, but its use in a library or production application is a sign that the design could be improved.",
          "With well designed types the type system can typically be used to make these invalid states unrepresentable.",
        ]),
      ]
    }
    _ -> []
  }
}

pub fn unnecessary_concatenation_expression_visitor(
  expr: glance.Expression,
) -> List(RuleError) {
  case expr {
    glance.BinaryOperator(glance.Concatenate, glance.String(""), _)
    | glance.BinaryOperator(glance.Concatenate, _, glance.String("")) -> {
      [
        rule.error(
          message: "Unnecessary concatenation with an empty string",
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
        rule.error(
          message: "Unnecessary concatenation of string literals",
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
