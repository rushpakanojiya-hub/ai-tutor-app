/// Defensive JSON-value parsing helpers.
///
/// The backend is expected to return well-formed data, but a null field,
/// a numeric-string ("15" instead of 15), or a stray null inside a list
/// should never crash the app. These helpers centralize that tolerance
/// so individual services/models don't each reinvent it.
library;

/// Parses [value] as an int, accepting an actual int, a double (truncated),
/// or a numeric String ("15"). Returns null if [value] is null or cannot
/// be interpreted as a number.
int? safeInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// Like [safeInt], but throws a descriptive [Exception] instead of
/// returning null - for fields the caller has no sane fallback for
/// (e.g. a record's own id).
int safeIntRequired(dynamic value, String fieldName) {
  final parsed = safeInt(value);
  if (parsed == null) {
    throw Exception('Invalid or missing "$fieldName" in server response.');
  }
  return parsed;
}

/// Parses [value] as a String, accepting only actual non-empty Strings.
/// Returns null for null, empty, or non-String values.
String? safeString(dynamic value) {
  if (value is String && value.isNotEmpty) return value;
  return null;
}

/// Parses [value] as a bool, accepting bool, common numeric (1/0) and
/// String ("true"/"false"/"1"/"0") representations. Returns null if
/// [value] can't be interpreted as a boolean.
bool? safeBool(dynamic value) {
  if (value is bool) return value;
  if (value is int) {
    if (value == 1) return true;
    if (value == 0) return false;
    return null;
  }
  if (value is String) {
    final v = value.trim().toLowerCase();
    if (v == 'true' || v == '1') return true;
    if (v == 'false' || v == '0') return false;
    return null;
  }
  return null;
}
