/// Client-side Indian Postal Index Number (PIN Code) validator.
/// Accepts valid 6-digit Indian PIN codes not starting with 0.
bool validateIndianPinCode(String? pin) {
  if (pin == null) return false;
  final clean = pin.trim();
  return RegExp(r'^[1-9][0-9]{5}$').hasMatch(clean);
}
