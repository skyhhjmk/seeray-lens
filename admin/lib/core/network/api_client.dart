/// Boundary for the later REST implementation. It deliberately has no API calls in Phase 1.
abstract interface class ApiClient {
  Future<T> get<T>(String path);
}
