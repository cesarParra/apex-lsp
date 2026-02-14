import 'package:json_annotation/json_annotation.dart';

part 'sfdx_project.g.dart';

/// Represents the contents of a Salesforce `sfdx-project.json`.
///
/// Notes:
/// - This models the common fields used by SFDX projects.
/// - The schema can vary across orgs/tools; unknown fields are ignored.
/// - `sourceApiVersion` is represented as a `String?` because it may appear
///   as `"61.0"` (string) and you likely want to preserve formatting.
///
/// Typical example:
/// ```json
/// {
///   "packageDirectories":[{"path":"force-app","default":true}],
///   "name":"my-project",
///   "namespace":"",
///   "sfdcLoginUrl":"https://login.salesforce.com",
///   "sourceApiVersion":"61.0"
/// }
/// ```
@JsonSerializable()
class SfdxProject {
  final List<SfdxPackageDirectory>? packageDirectories;
  final String? name;
  final String? namespace;
  final String? sfdcLoginUrl;
  final String? sourceApiVersion;
  final String? package;
  final String? versionNumber;
  final String? definitionFile;
  final String? description;

  const SfdxProject({
    this.packageDirectories,
    this.name,
    this.namespace,
    this.sfdcLoginUrl,
    this.sourceApiVersion,
    this.package,
    this.versionNumber,
    this.definitionFile,
    this.description,
  });

  factory SfdxProject.fromJson(Map<String, Object?> json) =>
      _$SfdxProjectFromJson(json);

  Map<String, Object?> toJson() => _$SfdxProjectToJson(this);
}

/// Models an entry in `packageDirectories`.
@JsonSerializable()
class SfdxPackageDirectory {
  /// Directory path (e.g. `force-app`, `packages/foo`).
  final String path;

  /// Whether this directory is the default package directory.
  final bool? defaultPackageDirectory;

  /// Alias as it appears in JSON (`default`).
  ///
  /// `default` is a reserved word in Dart, so we map it.
  @JsonKey(name: 'default')
  final bool? isDefault;

  /// Package name when using unlocked/managed packages.
  final String? package;

  /// Namespace in a packaging context.
  final String? namespace;

  /// Version name/number used in packaging.
  final String? versionName;
  final String? versionNumber;

  /// `unpackagedMetadata` support (varies by tooling).
  final Map<String, Object?>? unpackagedMetadata;

  /// Dependency declarations used in second-generation packaging.
  final List<SfdxPackageDependency>? dependencies;

  /// Some projects include:
  /// - `ignoreOnStage`
  /// - `skipCoverage`
  /// - `apexTestAccess` etc.
  ///
  /// Rather than hard-fail on new keys, we keep a catch-all.
  @JsonKey(includeFromJson: true, includeToJson: false)
  final Map<String, Object?>? extra;

  const SfdxPackageDirectory({
    required this.path,
    this.defaultPackageDirectory,
    this.isDefault,
    this.package,
    this.namespace,
    this.versionName,
    this.versionNumber,
    this.unpackagedMetadata,
    this.dependencies,
    this.extra,
  });

  factory SfdxPackageDirectory.fromJson(Map<String, Object?> json) =>
      _$SfdxPackageDirectoryFromJson(json);

  Map<String, Object?> toJson() => _$SfdxPackageDirectoryToJson(this);
}

/// Models a dependency entry inside a package directory.
///
/// Example:
/// `{ "package": "foo", "versionNumber": "1.2.3.NEXT" }`
@JsonSerializable(fieldRename: FieldRename.none)
class SfdxPackageDependency {
  final String? package;
  final String? versionNumber;

  const SfdxPackageDependency({this.package, this.versionNumber});

  factory SfdxPackageDependency.fromJson(Map<String, Object?> json) =>
      _$SfdxPackageDependencyFromJson(json);

  Map<String, Object?> toJson() => _$SfdxPackageDependencyToJson(this);
}
