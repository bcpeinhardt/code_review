import filepath
import simplifile

const review_file_name = "review.gleam"

const init_setup_src = "
import code_review
import code_review/rules/no_panic
import code_review/rules/no_unnecessary_string_concatenation
import code_review/rules/no_trailing_underscore
import code_review/rules/no_deprecated

pub fn main() {
  let rules = [
    no_panic.rule(),
    no_unnecessary_string_concatenation.rule(),
    no_trailing_underscore.rule(),
    no_deprecated.rule(),
  ]
  code_review.run(rules)
}
"

pub fn main() {
  let assert Ok(curr_dir) = simplifile.current_directory()
  let assert Ok(_) =
    simplifile.write(
      filepath.join(curr_dir, "test/" <> review_file_name),
      init_setup_src,
    )
}
