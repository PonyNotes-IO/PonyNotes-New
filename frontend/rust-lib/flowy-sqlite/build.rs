fn main() {
  // embed_migrations! cannot track added migration directories by itself.
  println!("cargo:rerun-if-changed=migrations");
}
