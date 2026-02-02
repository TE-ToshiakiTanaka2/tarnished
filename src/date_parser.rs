//! Date expression parser for schedule defaults.
//!
//! Supports the following formats:
//! - `"today"` - Current date
//! - `"+7d"` - 7 days from today
//! - `"+2w"` - 2 weeks from today
//! - `"2024-01-15"` - ISO 8601 date

use chrono::{Days, Local, NaiveDate};

/// Error types for date parsing
#[derive(Debug, thiserror::Error)]
pub enum DateParseError {
    /// Invalid date format
    #[error("Invalid date format: {0}. Expected 'today', '+Nd', '+Nw', or 'YYYY-MM-DD'")]
    InvalidFormat(String),

    /// Date overflow (e.g., adding too many days)
    #[error("Date calculation overflow")]
    Overflow,

    /// Invalid ISO date
    #[error("Invalid ISO date: {0}")]
    InvalidIsoDate(String),
}

/// Parse a date expression and return an ISO 8601 date string (YYYY-MM-DD).
///
/// # Supported Formats
///
/// - `"today"` - Current date
/// - `"+Nd"` - N days from today (e.g., `"+7d"` for 7 days)
/// - `"+Nw"` - N weeks from today (e.g., `"+2w"` for 2 weeks)
/// - `"YYYY-MM-DD"` - ISO 8601 date (passed through after validation)
///
/// # Examples
///
/// ```
/// use erd::date_parser::parse_date_expression;
///
/// // These would return dates relative to "today"
/// let today = parse_date_expression("today").unwrap();
/// let week_later = parse_date_expression("+7d").unwrap();
/// let two_weeks = parse_date_expression("+2w").unwrap();
///
/// // ISO date is validated and returned as-is
/// let specific = parse_date_expression("2024-01-15").unwrap();
/// assert_eq!(specific, "2024-01-15");
/// ```
pub fn parse_date_expression(expr: &str) -> Result<String, DateParseError> {
    let expr = expr.trim().to_lowercase();

    // Handle "today"
    if expr == "today" {
        let today = Local::now().date_naive();
        return Ok(today.format("%Y-%m-%d").to_string());
    }

    // Handle relative dates: +Nd or +Nw
    if expr.starts_with('+') {
        return parse_relative_date(&expr);
    }

    // Handle ISO date (YYYY-MM-DD)
    if let Ok(date) = NaiveDate::parse_from_str(&expr, "%Y-%m-%d") {
        return Ok(date.format("%Y-%m-%d").to_string());
    }

    Err(DateParseError::InvalidFormat(expr))
}

/// Parse a relative date expression (+Nd or +Nw).
fn parse_relative_date(expr: &str) -> Result<String, DateParseError> {
    // Remove the leading '+'
    let rest = &expr[1..];

    // Check if it ends with 'd' (days) or 'w' (weeks)
    let (number_str, multiplier) = if let Some(stripped) = rest.strip_suffix('d') {
        (stripped, 1)
    } else if let Some(stripped) = rest.strip_suffix('w') {
        (stripped, 7)
    } else {
        return Err(DateParseError::InvalidFormat(expr.to_string()));
    };

    // Parse the number
    let number: u64 = number_str
        .parse()
        .map_err(|_| DateParseError::InvalidFormat(expr.to_string()))?;

    let total_days = number * multiplier;

    // Calculate the target date
    let today = Local::now().date_naive();
    let target = today
        .checked_add_days(Days::new(total_days))
        .ok_or(DateParseError::Overflow)?;

    Ok(target.format("%Y-%m-%d").to_string())
}

/// Check if a string is a valid date expression.
pub fn is_valid_date_expression(expr: &str) -> bool {
    parse_date_expression(expr).is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_today() {
        let result = parse_date_expression("today").unwrap();
        let today = Local::now().date_naive();
        assert_eq!(result, today.format("%Y-%m-%d").to_string());
    }

    #[test]
    fn test_parse_today_case_insensitive() {
        let result = parse_date_expression("TODAY").unwrap();
        let today = Local::now().date_naive();
        assert_eq!(result, today.format("%Y-%m-%d").to_string());
    }

    #[test]
    fn test_parse_relative_days() {
        let result = parse_date_expression("+7d").unwrap();
        let expected = Local::now()
            .date_naive()
            .checked_add_days(Days::new(7))
            .unwrap();
        assert_eq!(result, expected.format("%Y-%m-%d").to_string());
    }

    #[test]
    fn test_parse_relative_weeks() {
        let result = parse_date_expression("+2w").unwrap();
        let expected = Local::now()
            .date_naive()
            .checked_add_days(Days::new(14))
            .unwrap();
        assert_eq!(result, expected.format("%Y-%m-%d").to_string());
    }

    #[test]
    fn test_parse_iso_date() {
        let result = parse_date_expression("2024-01-15").unwrap();
        assert_eq!(result, "2024-01-15");
    }

    #[test]
    fn test_parse_iso_date_with_whitespace() {
        let result = parse_date_expression("  2024-01-15  ").unwrap();
        assert_eq!(result, "2024-01-15");
    }

    #[test]
    fn test_invalid_format() {
        assert!(parse_date_expression("invalid").is_err());
        assert!(parse_date_expression("+7").is_err());
        assert!(parse_date_expression("7d").is_err());
        assert!(parse_date_expression("2024/01/15").is_err());
    }

    #[test]
    fn test_is_valid_date_expression() {
        assert!(is_valid_date_expression("today"));
        assert!(is_valid_date_expression("+7d"));
        assert!(is_valid_date_expression("+2w"));
        assert!(is_valid_date_expression("2024-01-15"));
        assert!(!is_valid_date_expression("invalid"));
    }

    #[test]
    fn test_parse_zero_days() {
        let result = parse_date_expression("+0d").unwrap();
        let today = Local::now().date_naive();
        assert_eq!(result, today.format("%Y-%m-%d").to_string());
    }

    #[test]
    fn test_parse_large_number() {
        // 365 days should work
        let result = parse_date_expression("+365d");
        assert!(result.is_ok());
    }
}
