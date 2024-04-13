//// This rule checks the code for unnecessary string literal concatenation, 
//// like "a" <> "b" instead of just "ab".

import glance
import rule.{type Rule, type RuleViolation, Rule}

pub const rule = Rule(
  name: "NoUnnecessaryStringConcatenation",
  expression_visitors: [
    check_binary_ops_for_unnecessary_string_literal_concatenation,
  ],
)

pub fn check_binary_ops_for_unnecessary_string_literal_concatenation(
  expr: glance.Expression,
) -> List(RuleViolation) {
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
