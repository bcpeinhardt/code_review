import gleam/bool

pub fn panic_in_use_call() {
  use <- bool.guard(True, panic as "oops")
  Nil
}
