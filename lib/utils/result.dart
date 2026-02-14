sealed class Result<T> {}

final class Success<T> extends Result<T> {
  final T value;

  Success(this.value);
}

final class Failure<T> extends Result<T> {
  final String message;

  Failure(this.message);
}
