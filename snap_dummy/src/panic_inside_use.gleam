import gleam/bool

pub fn panic_inside_use() {
  use <- bool.guard(False, Nil)
  Nil
  panic as "panic inside use"
}
