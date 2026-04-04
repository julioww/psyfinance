/// Stub implementation — used on non-web platforms.
/// On desktop the caller is responsible for saving via File; this is a no-op.
Future<void> triggerBrowserDownload(List<int> bytes, String filename) async {
  // No-op on non-web. Desktop path is handled by DashboardRepository.
}
