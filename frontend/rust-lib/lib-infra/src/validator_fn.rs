use std::path::Path;
use validator::ValidationError;

pub fn required_not_empty_str(s: &str) -> Result<(), ValidationError> {
  if s.is_empty() {
    return Err(ValidationError::new("should not be empty string"));
  }
  Ok(())
}

/// 验证邮箱或手机号格式
/// 支持：
/// - 邮箱：包含@符号的标准邮箱格式
/// - 手机号：纯数字或以+开头的数字（至少6位，最多15位）
pub fn email_or_phone(s: &str) -> Result<(), ValidationError> {
  if s.is_empty() {
    return Err(ValidationError::new("should not be empty"));
  }

  // 检查是否是邮箱（包含@符号）
  if s.contains('@') {
    // 简单的邮箱格式验证
    let parts: Vec<&str> = s.split('@').collect();
    if parts.len() == 2 {
      let domain = parts[1];
      if domain.contains('.') && !domain.starts_with('.') && !domain.ends_with('.') {
        return Ok(());
      }
    }
    return Err(ValidationError::new("invalid email format"));
  }

  // 检查是否是手机号（纯数字或以+开头）
  let cleaned = s.trim().trim_start_matches('+');
  if !cleaned.is_empty() && cleaned.chars().all(|c| c.is_ascii_digit()) {
    let len = cleaned.len();
    // 手机号长度一般在6-15位之间
    if len >= 6 && len <= 15 {
      return Ok(());
    }
  }

  Err(ValidationError::new("invalid email or phone format"))
}

pub fn required_valid_path(s: &str) -> Result<(), ValidationError> {
  let path = Path::new(s);
  match (path.is_absolute(), path.exists()) {
    (true, true) => Ok(()),
    (_, _) => Err(ValidationError::new("invalid_path")),
  }
}

#[macro_export]
/// Macro to implement a custom validator function for a regex expression.
/// This is intended to replace `validator` crate's own regex validator, which
/// isn't compatible with `fancy_regex`.
///
/// # Arguments:
///
/// - name of the validator function
/// - the `fancy_regex::Regex` object
/// - error message of the `ValidationError`
///
macro_rules! impl_regex_validator {
  ($validator: ident, $regex: expr, $error: expr) => {
    pub(crate) fn $validator(arg: &str) -> Result<(), ValidationError> {
      let check = $regex.is_match(arg).unwrap();

      if check {
        Ok(())
      } else {
        Err(ValidationError::new($error))
      }
    }
  };
}
