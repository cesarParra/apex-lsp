final class DeclarationName {
  final String value;
  const DeclarationName(this.value);

  bool startsWith(String prefix) =>
      value.toLowerCase().startsWith(prefix.toLowerCase());

  @override
  bool operator ==(Object other) =>
      other is DeclarationName && value.toLowerCase() == other.value.toLowerCase();

  @override
  int get hashCode => value.toLowerCase().hashCode;

  @override
  String toString() => value;
}
