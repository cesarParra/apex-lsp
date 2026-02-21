import 'package:json_annotation/json_annotation.dart';

part 'message.g.dart';

/// Severity levels for LSP log and show messages.
///
/// Maps to the LSP `MessageType` enumeration with corresponding numeric codes.
///
/// See also:
///  * [LogMessage], which uses this type for logging.
///  * [ShowMessage], which uses this type for user notifications.
enum MessageType {
  /// Error message (code 1) - indicates a failure or critical issue.
  error(code: 1),

  /// Warning message (code 2) - indicates a potential problem.
  warning(code: 2),

  /// Info message (code 3) - indicates general informational output.
  info(code: 3),

  /// Log message (code 4) - indicates debug or trace-level output.
  log(code: 4);

  const MessageType({required this.code});

  /// The numeric code as defined by the LSP specification.
  final int code;
}

int messageTypeToJson(MessageType type) => type.code;

MessageType messageTypeFromJson(int code) =>
    MessageType.values.firstWhere((t) => t.code == code);

/// LSP completion item kinds mapped to their protocol integer values.
///
/// Only includes the kinds used by this server. See the LSP specification
/// for the full list.
enum CompletionItemKind {
  method(value: 2),
  field(value: 5),
  variable(value: 6),
  classKind(value: 7),
  interfaceKind(value: 8),
  enumKind(value: 13),
  enumMember(value: 20);

  const CompletionItemKind({required this.value});

  /// The numeric value as defined by the LSP specification.
  final int value;
}

int? _completionItemKindToJson(CompletionItemKind? kind) => kind?.value;

/// JSON-RPC 2.0 error codes as defined by the specification.
///
/// Includes both standard JSON-RPC codes (-327xx) and LSP-specific
/// extensions (-328xx and -32002).
///
/// See also:
///  * [ResponseError], which uses these codes in error responses.
enum JsonRpcErrorCode {
  /// Invalid JSON was received by the server.
  /// An error occurred on the server while parsing the JSON text.
  parseError(code: -32700),

  /// The JSON sent is not a valid Request object.
  invalidRequest(code: -32600),

  /// The method does not exist or is not available.
  methodNotFound(code: -32601),

  /// Invalid method parameter(s).
  invalidParams(code: -32602),

  /// Internal JSON-RPC error.
  internalError(code: -32603),

  /// The request was cancelled by the client (LSP-specific).
  requestCancelled(code: -32800),

  /// The server has not been initialized yet (LSP-specific).
  serverNotInitialized(code: -32002);

  const JsonRpcErrorCode({required this.code});

  /// The numeric error code as defined by the JSON-RPC specification.
  final int code;
}

// ----------- Incoming requests and notifications-----------------
// The LSP protocol defines 2 types of incoming messages: requests and notifications.

/// Base class for all incoming LSP messages from the client.
///
/// LSP defines two types of incoming messages:
/// - **Requests** ([RequestMessage]): Have an `id` and expect a response
/// - **Notifications** ([IncomingNotificationMessage]): No `id`, no response expected
///
/// See also:
///  * [RequestMessage], for messages requiring a response.
///  * [IncomingNotificationMessage], for fire-and-forget messages.
sealed class IncomingMessage {
  const IncomingMessage();
}

/// Base class for LSP request messages that require a response.
///
/// Requests include an `id` field that must be included in the response.
/// The server must send either a [SuccessResponseMessage] or [ErrorResponseMessage]
/// for each request received.
///
/// See also:
///  * [RequestMessageWithParams], for requests with typed parameters.
sealed class RequestMessage extends IncomingMessage {
  /// The request identifier that must be included in the response.
  final Object id;

  /// The LSP method name (e.g., 'initialize', 'textDocument/completion').
  String get method;

  const RequestMessage(this.id);
}

sealed class RequestMessageWithParams<TParams> extends RequestMessage {
  final TParams params;

  const RequestMessageWithParams(super.id, this.params);
}

/// A position in a text document expressed as zero-based line and character offset.
///
/// A position is between two characters like an insert cursor in an editor.
/// Line and character values are zero-based.
///
/// Example:
/// ```dart
/// final pos = Position(line: 0, character: 5);
/// // Represents the position after the 5th character on the first line
/// ```
@JsonSerializable()
final class Position {
  /// Zero-based line number.
  final int line;

  /// Zero-based character offset within the line.
  final int character;

  const Position({required this.line, required this.character});

  factory Position.fromJson(Map<String, Object?> json) =>
      _$PositionFromJson(json);

  Map<String, Object?> toJson() => _$PositionToJson(this);
}

@JsonSerializable()
final class TextDocumentIdentifierWithUri {
  final String uri;

  const TextDocumentIdentifierWithUri({required this.uri});

  factory TextDocumentIdentifierWithUri.fromJson(Map<String, Object?> json) =>
      _$TextDocumentIdentifierWithUriFromJson(json);

  Map<String, Object?> toJson() => _$TextDocumentIdentifierWithUriToJson(this);
}

/// Parameters for a `textDocument/completion` request.
///
/// Contains the document and cursor position where completion was triggered.
///
/// See also:
///  * [CompletionRequest], which uses these parameters.
///  * [CompletionList], the response type.
@JsonSerializable()
final class CompletionParams {
  /// The text document where completion was requested.
  final TextDocumentIdentifierWithUri textDocument;

  /// The cursor position where completion was triggered.
  final Position position;

  const CompletionParams({required this.textDocument, required this.position});

  factory CompletionParams.fromJson(Map<String, Object?> json) =>
      _$CompletionParamsFromJson(json);

  Map<String, Object?> toJson() => _$CompletionParamsToJson(this);
}

/// LSP `textDocument/completion` request.
///
/// Sent by the client to request completion suggestions at a specific
/// cursor position in a text document.
///
/// The server responds with a [CompletionList] containing completion items.
final class CompletionRequest
    extends RequestMessageWithParams<CompletionParams> {
  @override
  String get method => 'textDocument/completion';

  const CompletionRequest(super.id, super.params);
}

/// A single completion suggestion returned to the client.
///
/// Represents one possible completion at the requested position.
/// The [label] is displayed in the completion menu, while [insertText]
/// is what gets inserted when the item is selected.
///
/// Example:
/// ```dart
/// final item = CompletionItem(
///   label: 'Account',
///   insertText: 'Account',
/// );
/// ```
@JsonSerializable(createFactory: false, includeIfNull: false)
final class CompletionItemLabelDetails {
  /// Additional information that appears right after the label.
  /// Typically used for parameter signatures, e.g. `(String name)`.
  final String? detail;

  /// Additional information shown after [detail], typically the return type.
  final String? description;

  const CompletionItemLabelDetails({this.detail, this.description});

  @JsonKey(includeToJson: false)
  @override
  int get hashCode => Object.hash(detail, description);

  Map<String, Object?> toJson() => _$CompletionItemLabelDetailsToJson(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompletionItemLabelDetails &&
          runtimeType == other.runtimeType &&
          detail == other.detail &&
          description == other.description;
}

/// A single completion suggestion returned to the client.
///
/// Represents one possible completion at the requested position.
/// The [label] is displayed in the completion menu, while [insertText]
/// is what gets inserted when the item is selected.
///
/// Example:
/// ```dart
/// final item = CompletionItem(
///   label: 'Account',
///   insertText: 'Account',
/// );
/// ```
@JsonSerializable(createFactory: false, includeIfNull: false)
final class CompletionItem {
  /// The label shown in the completion menu.
  final String label;

  /// The text to insert. Defaults to [label] if not specified.
  final String? insertText;

  /// The kind of this completion item, used by the editor for icon rendering.
  @JsonKey(toJson: _completionItemKindToJson)
  final CompletionItemKind? kind;

  /// A human-readable string with additional information about this item,
  /// like type or symbol information.
  final String? detail;

  /// Additional label details displayed inline by the editor.
  final CompletionItemLabelDetails? labelDetails;

  const CompletionItem({
    required this.label,
    String? insertText,
    this.kind,
    this.detail,
    this.labelDetails,
  }) : insertText = insertText ?? label;

  Map<String, Object?> toJson() => _$CompletionItemToJson(this);

  @override
  String toString() {
    return 'CompletionItem{label: $label, kind: $kind, detail: $detail, labelDetails: $labelDetails}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompletionItem &&
          runtimeType == other.runtimeType &&
          label == other.label &&
          kind == other.kind &&
          detail == other.detail &&
          labelDetails == other.labelDetails;

  @override
  @JsonKey(includeToJson: false)
  int get hashCode => Object.hash(label, kind, detail, labelDetails);
}

/// Response to a completion request containing a list of completion items.
///
/// When [isIncomplete] is `true`, the client may re-request completions as
/// the user continues typing to get more specific results.
///
/// Example:
/// ```dart
/// final list = CompletionList(
///   isIncomplete: false,
///   items: [
///     CompletionItem(label: 'Account'),
///     CompletionItem(label: 'Contact'),
///   ],
/// );
/// ```
@JsonSerializable(createFactory: false)
final class CompletionList {
  /// Whether the list is incomplete. When `true`, more items may be available.
  final bool isIncomplete;

  /// The completion items to present to the user.
  final List<CompletionItem> items;

  const CompletionList({required this.isIncomplete, required this.items});

  Map<String, Object?> toJson() => _$CompletionListToJson(this);

  @override
  String toString() {
    return 'CompletionList{isIncomplete: $isIncomplete, items: $items}';
  }
}

/// LSP `initialize` request.
///
/// The first request sent from client to server to initialize the LSP session.
/// Must be sent before any other requests (except `shutdown`).
///
/// The server responds with its capabilities and version information.
///
/// See also:
///  * [InitializedMessage], sent by the client after receiving the response.
final class InitializeRequest
    extends RequestMessageWithParams<InitializedParams> {
  @override
  String get method => 'initialize';

  const InitializeRequest(super.id, super.params);

  @override
  String toString() {
    return 'InitializeRequest{id: $id, params: $params}';
  }
}

@JsonSerializable()
final class WorkspaceFolder {
  final String uri;
  final String name;

  const WorkspaceFolder(this.uri, this.name);

  factory WorkspaceFolder.fromJson(Map<String, dynamic> json) =>
      _$WorkspaceFolderFromJson(json);

  Map<String, dynamic> toJson() => _$WorkspaceFolderToJson(this);

  @override
  String toString() {
    return 'WorkspaceFolder{uri: $uri, name: $name}';
  }
}

@JsonSerializable()
final class InitializedParams {
  final List<WorkspaceFolder>? workspaceFolders;

  const InitializedParams(this.workspaceFolders);

  factory InitializedParams.fromJson(Map<String, dynamic> json) =>
      _$InitializedParamsFromJson(json);

  Map<String, dynamic> toJson() => _$InitializedParamsToJson(this);

  @override
  String toString() {
    return 'InitializedParams{workspaceFolders: $workspaceFolders}';
  }
}

/// LSP `shutdown` request.
///
/// Requests that the server prepares to exit. The server must not exit
/// until it receives an [ExitMessage] notification.
///
/// After responding to this request, the server should stop accepting
/// new requests and finish processing ongoing requests.
final class ShutdownRequest extends RequestMessage {
  @override
  String get method => 'shutdown';

  const ShutdownRequest(super.id);
}

/// Base class for LSP notification messages that don't require a response.
///
/// Notifications are fire-and-forget messages sent from client to server.
/// Unlike requests, they have no `id` field and the server does not send
/// a response.
///
/// See also:
///  * [RequestMessage], for messages that require responses.
sealed class IncomingNotificationMessage extends IncomingMessage {
  /// The LSP method name (e.g., 'initialized', 'textDocument/didOpen').
  String get method;

  const IncomingNotificationMessage();
}

/// Common base for notifications that include typed `params`.
sealed class IncomingNotificationMessageWithParams<TParams>
    extends IncomingNotificationMessage {
  TParams get params;

  const IncomingNotificationMessageWithParams();
}

/// LSP `initialized` notification.
///
/// Sent by the client after receiving the response to an [InitializeRequest].
/// Signals that the client is ready for normal operation and the server
/// can begin sending notifications and performing initialization work like
/// workspace indexing.
class InitializedMessage extends IncomingNotificationMessage {
  @override
  String get method => 'initialized';

  const InitializedMessage();
}

/// LSP `exit` notification.
///
/// Instructs the server to exit its process. The server should exit with
/// code 0 if a [ShutdownRequest] was received previously, otherwise with
/// code 1.
class ExitMessage extends IncomingNotificationMessage {
  @override
  String get method => 'exit';

  const ExitMessage();
}

/// LSP `textDocument/didOpen` notification.
///
/// Sent when a text document is opened in the client. The server should
/// track the document content and may begin analysis or diagnostics.
///
/// See also:
///  * [TextDocumentDidChangeMessage], for content changes.
///  * [TextDocumentDidCloseMessage], when the document is closed.
class TextDocumentDidOpenMessage
    extends IncomingNotificationMessageWithParams<DidOpenTextDocumentParams> {
  @override
  String get method => 'textDocument/didOpen';

  @override
  final DidOpenTextDocumentParams params;

  const TextDocumentDidOpenMessage(this.params);
}

@JsonSerializable()
final class DidOpenTextDocumentParams {
  final TextDocumentItem textDocument;

  const DidOpenTextDocumentParams({required this.textDocument});

  factory DidOpenTextDocumentParams.fromJson(Map<String, Object?> json) =>
      _$DidOpenTextDocumentParamsFromJson(json);

  Map<String, Object?> toJson() => _$DidOpenTextDocumentParamsToJson(this);
}

@JsonSerializable()
final class TextDocumentItem {
  final String uri;
  final String text;

  const TextDocumentItem({required this.uri, required this.text});

  factory TextDocumentItem.fromJson(Map<String, Object?> json) =>
      _$TextDocumentItemFromJson(json);

  Map<String, Object?> toJson() => _$TextDocumentItemToJson(this);
}

/// LSP `textDocument/didChange` notification.
///
/// Sent when the content of a text document changes. The server should
/// update its internal representation of the document content.
///
/// This implementation uses full document sync, so each change contains
/// the complete new document content.
class TextDocumentDidChangeMessage
    extends IncomingNotificationMessageWithParams<DidChangeTextDocumentParams> {
  @override
  String get method => 'textDocument/didChange';

  @override
  final DidChangeTextDocumentParams params;

  const TextDocumentDidChangeMessage(this.params);
}

/// LSP `textDocument/didClose` notification.
///
/// Sent when a text document is closed in the client. The server should
/// stop tracking the document and may clean up associated resources.
class TextDocumentDidCloseMessage
    extends IncomingNotificationMessageWithParams<DidCloseTextDocumentParams> {
  @override
  String get method => 'textDocument/didClose';

  @override
  final DidCloseTextDocumentParams params;

  const TextDocumentDidCloseMessage(this.params);
}

/// LSP `$/cancelRequest` notification.
///
/// Sent by the client to cancel a previously sent request. The server should
/// stop processing the request if possible and return a RequestCancelled error.
class CancelRequestNotification
    extends IncomingNotificationMessageWithParams<CancelRequestParams> {
  @override
  String get method => r'$/cancelRequest';

  @override
  final CancelRequestParams params;

  const CancelRequestNotification(this.params);
}

@JsonSerializable()
final class CancelRequestParams {
  final Object id;

  const CancelRequestParams({required this.id});

  factory CancelRequestParams.fromJson(Map<String, Object?> json) =>
      _$CancelRequestParamsFromJson(json);

  Map<String, Object?> toJson() => _$CancelRequestParamsToJson(this);
}

@JsonSerializable()
final class DidCloseTextDocumentParams {
  final TextDocumentIdentifier textDocument;

  const DidCloseTextDocumentParams({required this.textDocument});

  factory DidCloseTextDocumentParams.fromJson(Map<String, Object?> json) =>
      _$DidCloseTextDocumentParamsFromJson(json);

  Map<String, Object?> toJson() => _$DidCloseTextDocumentParamsToJson(this);
}

@JsonSerializable()
final class TextDocumentIdentifier {
  final String uri;

  const TextDocumentIdentifier({required this.uri});

  factory TextDocumentIdentifier.fromJson(Map<String, Object?> json) =>
      _$TextDocumentIdentifierFromJson(json);

  Map<String, Object?> toJson() => _$TextDocumentIdentifierToJson(this);
}

@JsonSerializable()
final class TextDocumentContentChangeEvent {
  final String text;

  const TextDocumentContentChangeEvent({required this.text});

  factory TextDocumentContentChangeEvent.fromJson(Map<String, Object?> json) =>
      _$TextDocumentContentChangeEventFromJson(json);

  Map<String, Object?> toJson() => _$TextDocumentContentChangeEventToJson(this);
}

@JsonSerializable()
final class DidChangeTextDocumentParams {
  final TextDocumentIdentifier textDocument;
  final List<TextDocumentContentChangeEvent> contentChanges;

  const DidChangeTextDocumentParams({
    required this.textDocument,
    required this.contentChanges,
  });

  factory DidChangeTextDocumentParams.fromJson(Map<String, Object?> json) =>
      _$DidChangeTextDocumentParamsFromJson(json);

  Map<String, Object?> toJson() => _$DidChangeTextDocumentParamsToJson(this);
}

//  ---------- Outgoing requests and notifications -------------

/// Base class for all LSP messages sent from server to client.
///
/// All outgoing messages include the JSON-RPC version field set to "2.0".
///
/// See also:
///  * [ResponseMessage], for responses to client requests.
///  * [OutgoingNotificationMessage], for server-initiated notifications.
sealed class OutgoingMessage {
  /// The JSON-RPC protocol version. Always "2.0" for LSP.
  final String jsonrpc = '2.0';

  const OutgoingMessage();

  /// Serializes this message to a JSON-encodable map.
  Map<String, Object?> toJson();
}

sealed class ResponseMessage extends OutgoingMessage {
  final Object? id;

  const ResponseMessage(this.id);
}

@JsonSerializable(createFactory: false)
class SuccessResponseMessage extends ResponseMessage {
  final Object? result;

  const SuccessResponseMessage(super.id, this.result);

  @override
  Map<String, Object?> toJson() => _$SuccessResponseMessageToJson(this);
}

@JsonSerializable(createFactory: false)
class ResponseError {
  final int code;
  final String message;
  final Object? data;

  const ResponseError(this.code, this.message, this.data);

  Map<String, Object?> toJson() => _$ResponseErrorToJson(this);
}

@JsonSerializable(createFactory: false)
class ErrorResponseMessage extends ResponseMessage {
  final ResponseError error;

  const ErrorResponseMessage(super.id, this.error);

  @override
  Map<String, Object?> toJson() => _$ErrorResponseMessageToJson(this);
}

sealed class OutgoingNotificationMessage extends OutgoingMessage {
  String get method;

  const OutgoingNotificationMessage();
}

/// Common base for notifications that include typed `params`.
sealed class OutgoingNotificationMessageWithParams<TParams>
    extends OutgoingNotificationMessage {
  TParams get params;

  const OutgoingNotificationMessageWithParams();
}

// todo: this should be withparams
@JsonSerializable(createFactory: false)
class LogMessage extends OutgoingNotificationMessage {
  @override
  String get method => 'window/logMessage';
  final MessageParams params;

  const LogMessage(this.params);

  @override
  Map<String, Object?> toJson() => _$LogMessageToJson(this);
}

// todo: this should be withparams
@JsonSerializable(createFactory: false)
class ShowMessage extends OutgoingNotificationMessage {
  @override
  String get method => 'window/showMessage';
  final MessageParams params;

  const ShowMessage(this.params);

  @override
  Map<String, Object?> toJson() => _$ShowMessageToJson(this);
}

@JsonSerializable(createFactory: false)
class MessageParams {
  @JsonKey(fromJson: messageTypeFromJson, toJson: messageTypeToJson)
  final MessageType type;
  final String message;

  const MessageParams({required this.type, required this.message});

  Map<String, Object?> toJson() => _$MessageParamsToJson(this);
}

/// A progress token identifier for LSP work-done progress reporting.
///
/// As defined by the LSP specification, a progress token can be either an
/// integer or a string. This class provides type-safe constructors for both.
///
/// Example:
/// ```dart
/// final token1 = ProgressToken.integer(42);
/// final token2 = ProgressToken.string('indexing-123');
/// ```
///
/// See also:
///  * [WorkDoneProgressCreateRequest], which creates a progress indicator.
///  * [WorkDoneProgressParams], which updates progress.
final class ProgressToken {
  /// The underlying token value (either int or String).
  final Object value;

  const ProgressToken._(this.value);

  /// Creates a progress token with an integer value.
  const ProgressToken.integer(int value) : this._(value);

  /// Creates a progress token with a string value.
  const ProgressToken.string(String value) : this._(value);

  factory ProgressToken.fromJson(Object? json) => switch (json) {
    final int v => ProgressToken.integer(v),
    final String v => ProgressToken.string(v),
    _ => throw ArgumentError.value(
      json,
      'json',
      'ProgressToken must be an int or a string',
    ),
  };

  Object toJson() => value;

  @override
  String toString() => 'ProgressToken($value)';
}

@JsonSerializable(createFactory: false)
final class WorkDoneProgressCreateParams {
  final ProgressToken token;

  const WorkDoneProgressCreateParams({required this.token});

  Map<String, Object?> toJson() => _$WorkDoneProgressCreateParamsToJson(this);
}

@JsonSerializable(createFactory: false)
final class WorkDoneProgressCreateRequest extends OutgoingMessage {
  final Object id;

  final String method = 'window/workDoneProgress/create';

  final WorkDoneProgressCreateParams params;

  const WorkDoneProgressCreateRequest({required this.id, required this.params});

  @override
  Map<String, Object?> toJson() => _$WorkDoneProgressCreateRequestToJson(this);
}

@JsonSerializable(createFactory: false)
final class WorkDoneProgressNotification extends OutgoingNotificationMessage {
  @override
  String get method => r'$/progress';

  final WorkDoneProgressParams params;

  const WorkDoneProgressNotification(this.params);

  @override
  Map<String, Object?> toJson() => _$WorkDoneProgressNotificationToJson(this);
}

@JsonSerializable(createFactory: false)
final class WorkDoneProgressParams {
  final ProgressToken token;
  final WorkDoneProgressValue value;

  const WorkDoneProgressParams({required this.token, required this.value});

  Map<String, Object?> toJson() => _$WorkDoneProgressParamsToJson(this);

  @override
  String toString() {
    return 'WorkDoneProgressParams{token: $token, value: $value}';
  }
}

sealed class WorkDoneProgressValue {
  const WorkDoneProgressValue();

  Map<String, Object?> toJson();
}

@JsonSerializable(createFactory: false)
final class WorkDoneProgressBegin extends WorkDoneProgressValue {
  final String kind = 'begin';
  final String title;
  final bool? cancellable;
  final String? message;
  final int? percentage;

  const WorkDoneProgressBegin({
    required this.title,
    this.cancellable,
    this.message,
    this.percentage,
  });

  @override
  Map<String, Object?> toJson() => _$WorkDoneProgressBeginToJson(this);

  @override
  String toString() {
    return 'WorkDoneProgressBegin{kind: $kind, title: $title, cancellable: $cancellable, message: $message, percentage: $percentage}';
  }
}

@JsonSerializable(createFactory: false)
final class WorkDoneProgressReport extends WorkDoneProgressValue {
  final String kind = 'report';
  final bool? cancellable;
  final String? message;
  final int? percentage;

  const WorkDoneProgressReport({
    this.cancellable,
    this.message,
    this.percentage,
  });

  @override
  Map<String, Object?> toJson() => _$WorkDoneProgressReportToJson(this);

  @override
  String toString() {
    return 'WorkDoneProgressReport{kind: $kind, cancellable: $cancellable, message: $message, percentage: $percentage}';
  }
}

@JsonSerializable(createFactory: false)
final class WorkDoneProgressEnd extends WorkDoneProgressValue {
  final String kind = 'end';
  final String? message;

  const WorkDoneProgressEnd({this.message});

  @override
  Map<String, Object?> toJson() => _$WorkDoneProgressEndToJson(this);

  @override
  String toString() {
    return 'WorkDoneProgressEnd{kind: $kind, message: $message}';
  }
}
