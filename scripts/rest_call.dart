import 'dart:convert';
import 'dart:io';

Future<Map<String, dynamic>> getSfCredentials(String alias) async {
  final result = await Process.run('sf', [
    'org',
    'display',
    '--target-org',
    alias,
    '--json',
  ]);

  if (result.exitCode != 0) {
    throw Exception('sf CLI error: ${result.stderr}');
  }

  final json = jsonDecode(result.stdout as String);
  return json['result'] as Map<String, dynamic>;
}

Future<Map<String, dynamic>> sfGet(
  String accessToken,
  String instanceUrl,
  String path, {
  String apiVersion = 'v60.0',
}) async {
  final uri = Uri.parse('$instanceUrl/services/data/$apiVersion$path');

  final client = HttpClient();
  final request = await client.getUrl(uri);

  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
  request.headers.set(HttpHeaders.acceptHeader, 'application/json');

  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();

  client.close();

  if (response.statusCode >= 400) {
    throw Exception('Salesforce API error ${response.statusCode}: $body');
  }

  return jsonDecode(body) as Map<String, dynamic>;
}

/// Queries the Tooling API for the SymbolTable of the Apex class with [className].
///
/// Returns the SymbolTable map, or null if no class with that name is found.
Future<Map<String, dynamic>?> getSymbolTable(
  String accessToken,
  String instanceUrl,
  String className, {
  String apiVersion = 'v60.0',
}) async {
  final query = Uri.encodeQueryComponent(
    "SELECT SymbolTable FROM ApexClass WHERE Name = '$className' LIMIT 1",
  );

  final result = await sfGet(
    accessToken,
    instanceUrl,
    '/tooling/query?q=$query',
    apiVersion: apiVersion,
  );

  final records = result['records'] as List<dynamic>?;
  if (records == null || records.isEmpty) {
    return null;
  }

  return (records.first as Map<String, dynamic>)['SymbolTable']
      as Map<String, dynamic>?;
}

void main() async {
  final creds = await getSfCredentials('org-name');

  final accessToken = creds['accessToken'] as String;
  final instanceUrl = creds['instanceUrl'] as String;

  final symbolTable = await getSymbolTable(
    accessToken,
    instanceUrl,
    'ClassName',
  );

  print(symbolTable);
}
