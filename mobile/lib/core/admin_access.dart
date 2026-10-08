bool isShipdeHopAdmin(Map<String, dynamic>? appMetadata) {
  if (appMetadata == null) return false;
  return appMetadata['role']?.toString().trim().toLowerCase() == 'admin';
}
