import 'dart:io';

import 'package:apex_lsp/completion/tree_sitter_bindings.dart';
import 'package:apex_lsp/indexing/local_indexer.dart';
import 'package:apex_lsp/indexing/declarations.dart';
import 'package:apex_lsp/type_name.dart';
import 'package:test/test.dart';

void main() {
  final libPath = Platform.environment['TS_SFAPEX_LIB'];

  final bindings = TreeSitterBindings.load(path: libPath);
  late LocalIndexer indexer;

  setUp(() {
    indexer = LocalIndexer(bindings: bindings);
  });

  group('indexes enums', () {
    test('indexes top level declaration', () {
      final text = '''
public Enum Foo { A, B, C };
      ''';

      final result = indexer.parseAndIndex(text);

      expect(result.first, isA<IndexedEnum>());
      final enumDeclaration = result.first as IndexedEnum;
      expect(enumDeclaration.name.value, 'Foo');
    });

    test('index contains location of the declaration', () {
      final text = 'public Enum Foo { A, B, C }';

      final result = indexer.parseAndIndex(text);

      expect(result.first, isA<IndexedEnum>());
      final enumDeclaration = result.first as IndexedEnum;
      expect(enumDeclaration.location, isNotNull);
      expect(enumDeclaration.location, equals((0, text.length)));
    });

    test('parses member values', () {
      final text = 'public Enum Foo { A, B, C }';

      final result = indexer.parseAndIndex(text);

      expect(result.first, isA<IndexedEnum>());
      final enumDeclaration = result.first as IndexedEnum;
      expect(enumDeclaration.values, hasLength(3));
    });
  });

  group('indexes variables', () {
    test('indexes a simple variable declaration', () {
      final text = "String myVar = 'hello';";

      final result = indexer.parseAndIndex(text);

      expect(result, hasLength(1));
      expect(result.first, isA<IndexedVariable>());
      final variable = result.first as IndexedVariable;
      expect(variable.name.value, 'myVar');
      expect(variable.typeName.value, 'String');
    });

    test('indexes multiple declarators', () {
      final text = 'Integer a, b;';

      final result = indexer.parseAndIndex(text);

      expect(result, hasLength(2));
      final variables = result.whereType<IndexedVariable>().toList();
      expect(variables, hasLength(2));
      expect(variables[0].name.value, 'a');
      expect(variables[0].typeName.value, 'Integer');
      expect(variables[1].name.value, 'b');
      expect(variables[1].typeName.value, 'Integer');
    });

    test('indexes declaration without initializer', () {
      final text = 'String items;';

      final result = indexer.parseAndIndex(text);

      expect(result, hasLength(1));
      final variable = result.first as IndexedVariable;
      expect(variable.name.value, 'items');
      expect(variable.typeName.value, 'String');
    });

    test('indexes final variable', () {
      final text = "final String name = 'test';";

      final result = indexer.parseAndIndex(text);

      expect(result, hasLength(1));
      final variable = result.first as IndexedVariable;
      expect(variable.name.value, 'name');
      expect(variable.typeName.value, 'String');
    });

    test('tracks location', () {
      final text = "String myVar = 'hello';";

      final result = indexer.parseAndIndex(text);

      final variable = result.first as IndexedVariable;
      expect(variable.location, isNotNull);
    });
  });

  group('indexes methods', () {
    test('indexes a simple method declaration', () {
      final text = 'void sampleMethod() { }';

      final result = indexer.parseAndIndex(text);

      expect(result, hasLength(1));
      expect(result.first, isA<MethodDeclaration>());
      final method = result.first as MethodDeclaration;
      expect(method.name.value, 'sampleMethod');
    });

    test('captures return type for void methods', () {
      final text = 'void sampleMethod() { }';

      final result = indexer.parseAndIndex(text);

      final method = result.first as MethodDeclaration;
      expect(method.returnType, 'void');
    });

    test('captures return type for non-void methods', () {
      final text = 'String getName() { return null; }';

      final result = indexer.parseAndIndex(text);

      final method = result.first as MethodDeclaration;
      expect(method.returnType, 'String');
    });

    test('indexes a method with a non-void return type', () {
      final text = 'String getName() { return null; }';

      final result = indexer.parseAndIndex(text);

      expect(result, hasLength(1));
      expect(result.first, isA<MethodDeclaration>());
      final method = result.first as MethodDeclaration;
      expect(method.name.value, 'getName');
    });

    test('tracks location of the method declaration', () {
      final text = 'void sampleMethod() { }';

      final result = indexer.parseAndIndex(text);

      final method = result.first as MethodDeclaration;
      expect(method.location, isNotNull);
      expect(method.location, equals((0, text.length)));
    });

    test('method is marked as non-static', () {
      final text = 'void sampleMethod() { }';

      final result = indexer.parseAndIndex(text);

      final method = result.first as MethodDeclaration;
      expect(method.isStatic, isFalse);
    });
  });

  group('indexes method parameters', () {
    test('captures parameters for signature display', () {
      final text = 'void sampleMethod(String name, Integer count) { }';

      final result = indexer.parseAndIndex(text);

      final methodDeclaration = result.first as MethodDeclaration;
      expect(methodDeclaration.parameters, hasLength(2));
      expect(methodDeclaration.parameters[0], (type: 'String', name: 'name'));
      expect(methodDeclaration.parameters[1], (type: 'Integer', name: 'count'));
    });

    test('indexes a single parameter', () {
      final text = 'void sampleMethod(String name) { }';

      final result = indexer.parseAndIndex(text);

      final methodDeclaration = result.first as MethodDeclaration;

      final variables = methodDeclaration.body.declarations
          .whereType<IndexedVariable>()
          .toList();
      expect(variables, hasLength(1));
      expect(variables.first.name.value, 'name');
      expect(variables.first.typeName.value, 'String');
    });

    test('indexes multiple parameters', () {
      final text = 'void sampleMethod(String name, Integer count) { }';

      final result = indexer.parseAndIndex(text);

      final methodDeclaration = result.first as MethodDeclaration;

      final variables = methodDeclaration.body.declarations
          .whereType<IndexedVariable>()
          .toList();
      expect(variables, hasLength(2));
      expect(variables[0].name.value, 'name');
      expect(variables[0].typeName.value, 'String');
      expect(variables[1].name.value, 'count');
      expect(variables[1].typeName.value, 'Integer');
    });

    test('tracks location of parameters', () {
      final text = 'void sampleMethod(String name) { }';

      final result = indexer.parseAndIndex(text);

      final methodDeclaration = result.first as MethodDeclaration;

      final variable = methodDeclaration.body.declarations
          .whereType<IndexedVariable>()
          .first;
      expect(variable.location, isNotNull);
    });

    test('method with no parameters produces no variables', () {
      final text = 'void sampleMethod() { }';

      final result = indexer.parseAndIndex(text);

      final methodDeclaration = result.whereType<MethodDeclaration>().first;

      final variables = methodDeclaration.body.declarations
          .whereType<IndexedVariable>()
          .toList();
      expect(variables, isEmpty);
    });

    test('parameter visibility is scoped to method body', () {
      final text = 'void sampleMethod(String name) { }';

      final result = indexer.parseAndIndex(text);

      final methodDeclaration = result.whereType<MethodDeclaration>().first;

      final variable = methodDeclaration.body.declarations
          .whereType<IndexedVariable>()
          .first;
      expect(variable.visibility, isA<VisibleBetweenDeclarationAndScopeEnd>());
      final bodyEnd = text.indexOf('}') + 1;
      final visibility =
          variable.visibility as VisibleBetweenDeclarationAndScopeEnd;
      expect(visibility.scopeEnd, bodyEnd);
    });
  });

  group('indexes variables inside method bodies', () {
    test('indexes a variable declared inside a method body', () {
      final text = 'void sampleMethod() { String myTest; }';

      final result = indexer.parseAndIndex(text);

      final methodDeclaration = result.first as MethodDeclaration;

      final variables = methodDeclaration.body.declarations
          .whereType<IndexedVariable>()
          .toList();
      expect(variables, hasLength(1));
      expect(variables.first.name.value, 'myTest');
      expect(variables.first.typeName.value, 'String');
    });

    test('variable inside method body has scoped visibility', () {
      final text = 'void sampleMethod() { String myTest; }';

      final result = indexer.parseAndIndex(text);

      final methodDeclaration = result.first as MethodDeclaration;

      final variable = methodDeclaration.body.declarations
          .whereType<IndexedVariable>()
          .first;
      expect(variable.visibility, isA<VisibleBetweenDeclarationAndScopeEnd>());
      final bodyEnd = text.indexOf('}') + 1;
      final visibility =
          variable.visibility as VisibleBetweenDeclarationAndScopeEnd;
      expect(visibility.scopeEnd, bodyEnd);
    });

    test('indexes both parameters and body variables', () {
      final text = 'void sampleMethod(String param) { Integer local; }';

      final result = indexer.parseAndIndex(text);

      final methodDeclaration = result.first as MethodDeclaration;

      final variables = methodDeclaration.body.declarations
          .whereType<IndexedVariable>()
          .toList();
      expect(variables, hasLength(2));
      expect(variables[0].name.value, 'param');
      expect(variables[1].name.value, 'local');
    });
  });

  group('indexes variables in loop scopes', () {
    test('for loop init variable is scoped to the for statement', () {
      final text = 'void m() { for (Integer i = 0; i < 10; i++) { } }';

      final result = indexer.parseAndIndex(text);

      final methodDeclaration = result.first as MethodDeclaration;

      final variable = methodDeclaration.body.declarations
          .whereType<IndexedVariable>()
          .first;
      expect(variable.name.value, 'i');
      expect(variable.visibility, isA<VisibleBetweenDeclarationAndScopeEnd>());
      // The for statement ends after its body's closing brace (before the outer ' }')
      final visibility =
          variable.visibility as VisibleBetweenDeclarationAndScopeEnd;
      final methodBodyEnd = text.lastIndexOf('}') + 1;
      expect(visibility.scopeEnd, lessThan(methodBodyEnd));
    });

    test('variable inside for body is scoped to the body block', () {
      final text =
          'void m() { for (Integer i = 0; i < 10; i++) { String inner; } }';

      final result = indexer.parseAndIndex(text);

      final methodDeclaration = result.first as MethodDeclaration;

      final variables = methodDeclaration.body.declarations
          .whereType<IndexedVariable>()
          .toList();
      final initVar = variables.firstWhere((v) => v.name.value == 'i');
      final bodyVar = variables.firstWhere((v) => v.name.value == 'inner');

      final initVisibility =
          initVar.visibility as VisibleBetweenDeclarationAndScopeEnd;
      final bodyVisibility =
          bodyVar.visibility as VisibleBetweenDeclarationAndScopeEnd;
      expect(
        bodyVisibility.scopeEnd,
        lessThanOrEqualTo(initVisibility.scopeEnd),
      );
    });

    test('enhanced for iteration variable is scoped to the for statement', () {
      final text =
          'void m() { List<String> items; for (String item : items) { } }';

      final result = indexer.parseAndIndex(text);

      final methodDeclaration = result.first as MethodDeclaration;

      final variable = methodDeclaration.body.declarations.firstWhere(
        (v) => v.name.value == 'item',
      );
      expect(variable.visibility, isA<VisibleBetweenDeclarationAndScopeEnd>());
    });

    test('while loop body variable is scoped to the body block', () {
      final text = 'void m() { while (true) { String loopVar; } }';

      final result = indexer.parseAndIndex(text);

      final methodDeclaration = result.first as MethodDeclaration;

      final variable = methodDeclaration.body.declarations
          .whereType<IndexedVariable>()
          .firstWhere((v) => v.name.value == 'loopVar');
      expect(variable.visibility, isA<VisibleBetweenDeclarationAndScopeEnd>());
      final whileBodyEnd = text.lastIndexOf('}', text.lastIndexOf('}') - 1) + 1;
      final visibility =
          variable.visibility as VisibleBetweenDeclarationAndScopeEnd;
      expect(visibility.scopeEnd, whileBodyEnd);
    });

    test('nested for loops have independent scopes', () {
      final text =
          '''void m() { for (Integer i = 0; i < 10; i++) { for (Integer j = 0; j < 5; j++) { } } }''';

      final result = indexer.parseAndIndex(text);

      final methodDeclaration = result.first as MethodDeclaration;

      final variables = methodDeclaration.body.declarations
          .whereType<IndexedVariable>()
          .toList();
      final outerVar = variables.firstWhere((v) => v.name.value == 'i');
      final innerVar = variables.firstWhere((v) => v.name.value == 'j');

      final outerVisibility =
          outerVar.visibility as VisibleBetweenDeclarationAndScopeEnd;
      final innerVisibility =
          innerVar.visibility as VisibleBetweenDeclarationAndScopeEnd;
      expect(innerVisibility.scopeEnd, lessThan(outerVisibility.scopeEnd));
    });
  });

  group('indexes classes', () {
    test('indexes top level class declaration', () {
      final text = 'public class Foo {}';

      final result = indexer.parseAndIndex(text);

      expect(result, hasLength(1));
      expect(result.first, isA<IndexedClass>());
      final classDeclaration = result.first as IndexedClass;
      expect(classDeclaration.name.value, 'Foo');
    });

    test('indexes static class fields', () {
      final text = 'public class Foo { static String bar; }';

      final result = indexer.parseAndIndex(text);

      expect(result, hasLength(1));
      expect(result.first, isA<IndexedClass>());
      final classDeclaration = result.first as IndexedClass;
      expect(classDeclaration.members, hasLength(1));
      expect(classDeclaration.members.first.name, DeclarationName('bar'));
      expect(classDeclaration.members.first, isA<FieldMember>());
      final fieldDeclaration = classDeclaration.members.first as FieldMember;
      expect(fieldDeclaration.isStatic, true);
    });

    test('indexes instance class fields', () {
      final text = 'public class Foo { String bar; }';

      final result = indexer.parseAndIndex(text);

      expect(result, hasLength(1));
      expect(result.first, isA<IndexedClass>());
      final classDeclaration = result.first as IndexedClass;
      expect(classDeclaration.members, hasLength(1));
      expect(classDeclaration.members.first.name, DeclarationName('bar'));
      expect(classDeclaration.members.first, isA<FieldMember>());
      final fieldDeclaration = classDeclaration.members.first as FieldMember;
      expect(fieldDeclaration.isStatic, false);
    });

    test('indexes field type name', () {
      final text = 'public class Foo { Environment env; }';

      final result = indexer.parseAndIndex(text);

      final classDeclaration = result.first as IndexedClass;
      final fieldDeclaration = classDeclaration.members.first as FieldMember;
      expect(fieldDeclaration.typeName, equals(DeclarationName('Environment')));
    });

    test('indexes static class methods', () {
      final text = 'public class Foo { static String bar() {} }';

      final result = indexer.parseAndIndex(text);

      expect(result, hasLength(1));
      expect(result.first, isA<IndexedClass>());
      final classDeclaration = result.first as IndexedClass;
      expect(classDeclaration.members, hasLength(1));
      expect(classDeclaration.members.first.name, DeclarationName('bar'));
      expect(classDeclaration.members.first, isA<MethodDeclaration>());
      final methodDeclaration =
          classDeclaration.members.first as MethodDeclaration;
      expect(methodDeclaration.isStatic, true);
    });

    test('indexes instance class methods', () {
      final text = 'public class Foo { String bar() {} }';

      final result = indexer.parseAndIndex(text);

      expect(result, hasLength(1));
      expect(result.first, isA<IndexedClass>());
      final classDeclaration = result.first as IndexedClass;
      expect(classDeclaration.members, hasLength(1));
      expect(classDeclaration.members.first.name, DeclarationName('bar'));
      expect(classDeclaration.members.first, isA<MethodDeclaration>());
      final methodDeclaration =
          classDeclaration.members.first as MethodDeclaration;
      expect(methodDeclaration.isStatic, false);
    });

    test('indexes static initializers', () {
      final text =
          "public class Foo { static { System.debug('initialized') } }";

      final result = indexer.parseAndIndex(text);

      expect(result, hasLength(1));
      expect(result.first, isA<IndexedClass>());
      final classDeclaration = result.first as IndexedClass;
      expect(classDeclaration.staticInitializers, hasLength(1));
    });
  });

  group('indexes inner classes', () {
    test('indexes a class declared inside a class as a member', () {
      final text = '''
public class Foo {
  public class Bar {
    String name;
    void doSomething() {}
  }
}''';

      final result = indexer.parseAndIndex(text);

      expect(result, hasLength(1));
      final classDeclaration = result.first as IndexedClass;
      final innerClasses = classDeclaration.members
          .whereType<IndexedClass>()
          .toList();
      expect(innerClasses, hasLength(1));
      expect(innerClasses.first.name.value, 'Bar');
      expect(innerClasses.first.members, hasLength(2));
    });
  });

  group('indexes inner interfaces', () {
    test('indexes an interface declared inside a class as a member', () {
      final text = '''
public class Foo {
  public interface Bar {
    void doSomething();
    String getName();
  }
}''';

      final result = indexer.parseAndIndex(text);

      expect(result, hasLength(1));
      final classDeclaration = result.first as IndexedClass;
      final innerInterfaces = classDeclaration.members
          .whereType<IndexedInterface>()
          .toList();
      expect(innerInterfaces, hasLength(1));
      expect(innerInterfaces.first.name.value, 'Bar');
      expect(innerInterfaces.first.methods, hasLength(2));
    });
  });

  group('indexes inner enums', () {
    test('indexes an enum declared inside a class as a member', () {
      final text = '''
public class Foo {
  public Enum Bar {
    A, B, C
  }
}''';

      final result = indexer.parseAndIndex(text);

      expect(result, hasLength(1));
      final classDeclaration = result.first as IndexedClass;
      final innerEnums = classDeclaration.members
          .whereType<IndexedEnum>()
          .toList();
      expect(innerEnums, hasLength(1));
      expect(innerEnums.first.name.value, 'Bar');
      expect(innerEnums.first.values, hasLength(3));
    });
  });

  group('indexes interfaces', () {
    test('indexes top level interface declaration', () {
      final text = '''
public interface Foo {
  String doSomething();
  void saySomething();
}
      ''';

      final result = indexer.parseAndIndex(text);

      expect(result, hasLength(1));
      expect(result.first, isA<IndexedInterface>());
      final interfaceDeclaration = result.first as IndexedInterface;
      expect(interfaceDeclaration.name.value, 'Foo');
    });

    test('parses method declarations', () {
      final text = '''
public interface Foo {
  String doSomething();
  void saySomething();
}
      ''';

      final result = indexer.parseAndIndex(text);

      final interfaceDeclaration = result.first as IndexedInterface;
      expect(interfaceDeclaration.methods, hasLength(2));
      expect(interfaceDeclaration.methods[0].name.value, 'doSomething');
      expect(interfaceDeclaration.methods[1].name.value, 'saySomething');
    });

    test('methods are marked as non-static', () {
      final text = '''
public interface Foo {
  String doSomething();
}
      ''';

      final result = indexer.parseAndIndex(text);

      final interfaceDeclaration = result.first as IndexedInterface;
      expect(interfaceDeclaration.methods.first.isStatic, isFalse);
    });

    test('index contains location of the declaration', () {
      final text = 'public interface Foo { String doSomething(); }';

      final result = indexer.parseAndIndex(text);

      final interfaceDeclaration = result.first as IndexedInterface;
      expect(interfaceDeclaration.location, isNotNull);
      expect(interfaceDeclaration.location, equals((0, text.length)));
    });

    test('indexes interface with no methods', () {
      final text = 'public interface Empty { }';

      final result = indexer.parseAndIndex(text);

      expect(result, hasLength(1));
      final interfaceDeclaration = result.first as IndexedInterface;
      expect(interfaceDeclaration.name.value, 'Empty');
      expect(interfaceDeclaration.methods, isEmpty);
    });
  });

  group('indexes properties (fields with accessor blocks)', () {
    test('indexes a property with a get block as PropertyDeclaration', () {
      final text = '''
public class Foo {
  public String Name {
    get { return Name; }
  }
}
      ''';

      final result = indexer.parseAndIndex(text);

      final cls = result.first as IndexedClass;
      final property = cls.members.first;
      expect(property, isA<PropertyDeclaration>());
    });

    test('captures property name', () {
      final text = '''
public class Foo {
  public String MyProp {
    get { return MyProp; }
  }
}
      ''';

      final result = indexer.parseAndIndex(text);

      final cls = result.first as IndexedClass;
      final property = cls.members.first as PropertyDeclaration;
      expect(property.name.value, 'MyProp');
    });

    test('captures property type name', () {
      final text = '''
public class Foo {
  public String MyProp {
    get { return MyProp; }
  }
}
      ''';

      final result = indexer.parseAndIndex(text);

      final cls = result.first as IndexedClass;
      final property = cls.members.first as PropertyDeclaration;
      expect(property.typeName?.value, 'String');
    });

    test('captures property location', () {
      final text = 'public class Foo { public String MyProp { get; set; } }';

      final result = indexer.parseAndIndex(text);

      final cls = result.first as IndexedClass;
      final property = cls.members.first as PropertyDeclaration;
      expect(property.location, isNotNull);
    });

    test('marks non-static property as non-static', () {
      final text = '''
public class Foo {
  public String MyProp { get; set; }
}
      ''';

      final result = indexer.parseAndIndex(text);

      final cls = result.first as IndexedClass;
      final property = cls.members.first as PropertyDeclaration;
      expect(property.isStatic, isFalse);
    });

    test('marks static property as static', () {
      final text = '''
public class Foo {
  public static String MyProp { get; set; }
}
      ''';

      final result = indexer.parseAndIndex(text);

      final cls = result.first as IndexedClass;
      final property = cls.members.first as PropertyDeclaration;
      expect(property.isStatic, isTrue);
    });

    test('getter body contains variables declared inside get block', () {
      final text = '''
public class Foo {
  public String Name {
    get {
      String localVar;
      return localVar;
    }
  }
}
      ''';

      final result = indexer.parseAndIndex(text);

      final cls = result.first as IndexedClass;
      final property = cls.members.first as PropertyDeclaration;
      expect(property.getterBody, isNotNull);
      final variables = property.getterBody!.declarations
          .whereType<IndexedVariable>()
          .toList();
      expect(variables, hasLength(1));
      expect(variables.first.name.value, 'localVar');
    });

    test('setter body contains variables declared inside set block', () {
      final text = '''
public class Foo {
  public String Name {
    get;
    set {
      String transformed = value;
    }
  }
}
      ''';

      final result = indexer.parseAndIndex(text);

      final cls = result.first as IndexedClass;
      final property = cls.members.first as PropertyDeclaration;
      expect(property.setterBody, isNotNull);
      final variables = property.setterBody!.declarations
          .whereType<IndexedVariable>()
          .toList();
      expect(variables, hasLength(1));
      expect(variables.first.name.value, 'transformed');
    });

    test('getter body variables are scoped to the getter block', () {
      final text = '''
public class Foo {
  public String Name {
    get {
      String localVar;
      return localVar;
    }
  }
}
      ''';

      final result = indexer.parseAndIndex(text);

      final cls = result.first as IndexedClass;
      final property = cls.members.first as PropertyDeclaration;
      final variable = property.getterBody!.declarations
          .whereType<IndexedVariable>()
          .first;
      expect(variable.visibility, isA<VisibleBetweenDeclarationAndScopeEnd>());
    });

    test('auto-property with semicolons has null getter and setter bodies', () {
      final text = '''
public class Foo {
  public String Name { get; set; }
}
      ''';

      final result = indexer.parseAndIndex(text);

      final cls = result.first as IndexedClass;
      final property = cls.members.first as PropertyDeclaration;
      expect(property.getterBody, isNull);
      expect(property.setterBody, isNull);
    });

    test('plain field without accessor list remains a FieldMember', () {
      final text = '''
public class Foo {
  public String plainField;
}
      ''';

      final result = indexer.parseAndIndex(text);

      final cls = result.first as IndexedClass;
      expect(cls.members.first, isA<FieldMember>());
    });
  });
}
