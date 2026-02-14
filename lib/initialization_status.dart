import 'package:apex_lsp/message.dart';

sealed class InitializationStatus {}

final class NotInitialized extends InitializationStatus {}

final class Initialized extends InitializationStatus {
  final InitializedParams params;

  Initialized({required this.params});
}
