import 'package:apex_lsp/type_name.dart';

typedef Location = (int startByte, int endByte);

typedef MethodParameter = ({String type, String name});

sealed class Visibility {
  const Visibility();

  bool isVisibleAt(int cursorOffset, Location? location);
}

final class NeverVisible extends Visibility {
  const NeverVisible();

  @override
  bool isVisibleAt(int cursorOffset, Location? location) => false;
}

final class AlwaysVisible extends Visibility {
  const AlwaysVisible();

  @override
  bool isVisibleAt(int cursorOffset, Location? location) => true;
}

final class VisibleAfterDeclaration extends Visibility {
  const VisibleAfterDeclaration();

  @override
  bool isVisibleAt(int cursorOffset, Location? location) {
    if (location == null) return true;
    return cursorOffset >= location.$1;
  }
}

final class VisibleBetweenDeclarationAndScopeEnd extends Visibility {
  final int scopeEnd;

  const VisibleBetweenDeclarationAndScopeEnd({required this.scopeEnd});

  @override
  bool isVisibleAt(int cursorOffset, Location? location) {
    if (location == null) return true;
    return cursorOffset >= location.$1 && cursorOffset <= scopeEnd;
  }
}

sealed class Declaration {
  final DeclarationName name;
  final Location? location;
  final Visibility visibility;

  Declaration(this.name, {this.location, required this.visibility});

  bool isVisibleAt(int cursorOffset) =>
      visibility.isVisibleAt(cursorOffset, location);
}

class Block {
  final List<Declaration> declarations;

  Block({required this.declarations});

  factory Block.empty() => Block(declarations: []);
}

sealed class IndexedType extends Declaration {
  IndexedType(super.name, {super.location, required super.visibility});
}

final class IndexedClass extends IndexedType {
  final List<Block> staticInitializers;
  final List<Declaration> members;
  final String? superClass;

  IndexedClass(
    super.name, {
    required super.visibility,
    this.members = const [],
    this.superClass,
    super.location,
    this.staticInitializers = const [],
  });
}

final class IndexedInterface extends IndexedType {
  final List<MethodDeclaration> methods;
  final String? superInterface;

  IndexedInterface(
    super.name, {
    required this.methods,
    required super.visibility,
    this.superInterface,
    super.location,
  });
}

final class IndexedEnum extends IndexedType {
  final List<EnumValueMember> values;

  IndexedEnum(
    super.name, {
    required this.values,
    required super.visibility,
    super.location,
  });
}

final class FieldMember extends Declaration {
  final DeclarationName? typeName;
  final bool isStatic;

  FieldMember(
    super.name, {
    required this.isStatic,
    required super.visibility,
    this.typeName,
  });
}

final class PropertyDeclaration extends Declaration {
  final DeclarationName? typeName;
  final bool isStatic;
  final Block? getterBody;
  final Block? setterBody;

  PropertyDeclaration(
    super.name, {
    required this.isStatic,
    required super.visibility,
    this.typeName,
    this.getterBody,
    this.setterBody,
    super.location,
  });
}

final class ConstructorDeclaration extends Declaration {
  final Block body;

  ConstructorDeclaration({required this.body, super.location})
    : super(DeclarationName('__constructor__'), visibility: NeverVisible());
}

final class MethodDeclaration extends Declaration {
  final Block body;
  final bool isStatic;
  final String? returnType;
  final List<MethodParameter> parameters;

  MethodDeclaration(
    super.name, {
    required this.body,
    required this.isStatic,
    required super.visibility,
    this.returnType,
    this.parameters = const [],
    super.location,
  });

  factory MethodDeclaration.withoutBody(
    DeclarationName name, {
    required bool isStatic,
    required Visibility visibility,
    String? returnType,
    List<MethodParameter> parameters = const [],
  }) {
    return MethodDeclaration(
      name,
      body: Block.empty(),
      isStatic: isStatic,
      returnType: returnType,
      parameters: parameters,
      visibility: visibility,
    );
  }
}

final class EnumValueMember extends Declaration {
  EnumValueMember(super.name) : super(visibility: AlwaysVisible());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EnumValueMember &&
          runtimeType == other.runtimeType &&
          name == other.name;

  @override
  int get hashCode => name.hashCode;
}

final class IndexedVariable extends Declaration {
  final DeclarationName typeName;

  IndexedVariable(
    super.name, {
    required this.typeName,
    required Location location,
    Visibility? visibility,
  }) : super(
         location: location,
         visibility: visibility ?? VisibleAfterDeclaration(),
       );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IndexedVariable &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          typeName == other.typeName;

  @override
  int get hashCode => Object.hash(name, typeName);
}

extension IndexedTypeStringExtensions on String {
  EnumValueMember enumValueMember() => EnumValueMember(DeclarationName(this));
}
