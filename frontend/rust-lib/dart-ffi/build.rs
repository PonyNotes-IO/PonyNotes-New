fn main() {
  if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("android") {
    println!("cargo:rustc-link-arg=-Wl,-z,max-page-size=16384");
  }
  flowy_codegen::protobuf_file::dart_gen(env!("CARGO_PKG_NAME"));
}
