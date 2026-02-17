# Tree-Sitter-SFApex Reference

Comprehensive reference for the [tree-sitter-sfapex](https://github.com/aheber/tree-sitter-sfapex) Apex parser.
Covers all named node types, their fields, children, and supertypes. SOQL/SOSL nodes are omitted
(they live in `soql/` and `sosl/` grammars and are only reachable via `query_expression`).

Source: `apex/grammar.js` and `apex/src/node-types.json` from the repository.

## Grammar Notes

- **Case-insensitive keywords**: All Apex keywords use `ci()` (case-insensitive matching).
- **Root node**: `parser_output` — contains zero or more `statement` children.
- **Inline rules** (expanded at parse time, never appear as nodes): `_name`, `_simple_type`, `_class_body_declaration`, `_variable_initializer`.
- **Field access**: Use `ts_node_child_by_field_name(node, "fieldName")` to access named fields.
- **Operator precedence** (high to low): parens/object-access (18) → array/unary (16-17) → cast/new (15) → mult (14) → add (13) → shift (12) → relational (11) → equality (10) → bitwise (7-9) → logical (5-6) → null-coalesce (4) → ternary (3) → assign (1).

---

## 1. Supertype Nodes (Abstract)

These are union types — they never appear as concrete nodes but define sets of alternatives.

### `_literal`
`boolean` | `decimal_floating_point_literal` | `int` | `null_literal` | `string_literal`

### `_simple_type`
`boolean_type` | `generic_type` | `java_type` | `scoped_type_identifier` | `type_identifier` | `void_type`

### `_type`
`_unannotated_type` | `annotated_type`

### `_unannotated_type`
`_simple_type` | `array_type`

### `declaration`
`class_declaration` | `enum_declaration` | `interface_declaration` | `method_declaration` | `trigger_declaration`

### `expression`
`assignment_expression` | `binary_expression` | `cast_expression` | `dml_expression` | `instanceof_expression` | `primary_expression` | `ternary_expression` | `unary_expression` | `update_expression`

### `primary_expression`
`_literal` | `array_access` | `array_creation_expression` | `class_literal` | `field_access` | `identifier` | `java_field_access` | `map_creation_expression` | `method_invocation` | `object_creation_expression` | `parenthesized_expression` | `query_expression` | `this` | `version_expression`

### `statement`
`;` | `block` | `break_statement` | `continue_statement` | `declaration` | `do_statement` | `enhanced_for_statement` | `expression_statement` | `for_statement` | `if_statement` | `local_variable_declaration` | `return_statement` | `run_as_statement` | `switch_expression` | `throw_statement` | `try_statement` | `while_statement`

---

## 2. Top-Level / Declarations

### `parser_output`
Root node of every parse tree.
- children (optional, multiple): `statement`

### `class_declaration`
```
[modifiers] class name [type_parameters] [superclass] [interfaces] body
```
- field `body` (required, single): `class_body`
- field `interfaces` (optional, single): `interfaces`
- field `name` (required, single): `identifier`
- field `superclass` (optional, single): `superclass`
- field `type_parameters` (optional, single): `type_parameters`
- children (optional, single): `modifiers`

### `class_body`
- children (optional, multiple): `block` | `class_declaration` | `constructor_declaration` | `enum_declaration` | `field_declaration` | `interface_declaration` | `method_declaration` | `static_initializer`

### `interface_declaration`
```
[modifiers] interface name [type_parameters] [extends_interfaces] body
```
- field `body` (required, single): `interface_body`
- field `name` (required, single): `identifier`
- field `type_parameters` (optional, single): `type_parameters`
- children (optional, multiple): `extends_interfaces` | `modifiers`

### `interface_body`
- children (optional, multiple): `class_declaration` | `constant_declaration` | `enum_declaration` | `interface_declaration` | `method_declaration`

### `enum_declaration`
```
[modifiers] enum name [interfaces] body
```
- field `body` (required, single): `enum_body`
- field `interfaces` (optional, single): `interfaces`
- field `name` (required, single): `identifier`
- children (optional, single): `modifiers`

### `enum_body`
- children (optional, multiple): `enum_constant`

### `enum_constant`
- field `name` (required, single): `identifier`
- children (optional, single): `modifiers`

### `trigger_declaration`
```
trigger name on object (events) body
```
- field `body` (required, single): `trigger_body`
- field `events` (required, multiple): `trigger_event`
- field `name` (required, single): `identifier`
- field `object` (required, single): `identifier`

### `trigger_body`
- children (required, single): `block`

---

## 3. Methods, Constructors & Parameters

### `method_declaration`
```
[modifiers] [type_parameters] type name parameters [dimensions] (body | ;)
```
- field `body` (optional, single): `block` — absent for interface method signatures (semicolon instead)
- field `dimensions` (optional, single): `dimensions`
- field `name` (required, single): `identifier`
- field `parameters` (required, single): `formal_parameters`
- field `type` (required, single): `_unannotated_type` — the return type
- field `type_parameters` (optional, single): `type_parameters`
- children (optional, multiple): `annotation` | `modifiers`

**Parse tree example:**
```
// Source: public void method1(String param1, Integer param2) { ... }
(method_declaration
  (modifiers (modifier (public)))
  (void_type)                          ← field "type" (return type)
  (identifier)                         ← field "name"
  (formal_parameters                   ← field "parameters"
    (formal_parameter
      (type_identifier)                ← field "type" on formal_parameter
      (identifier))                    ← field "name" on formal_parameter
    (formal_parameter
      (type_identifier)
      (identifier)))
  (block ...))                         ← field "body"
```

**Parse tree example (non-void):**
```
// Source: private Integer method1(Integer param1) { return param1; }
(method_declaration
  (modifiers (modifier (private)))
  (type_identifier)                    ← field "type" = "Integer"
  (identifier)                         ← field "name" = "method1"
  (formal_parameters
    (formal_parameter
      (type_identifier)
      (identifier)))
  (block (return_statement (identifier))))
```

**Parse tree example (generic return type):**
```
// Source: public List<String> getNames() { ... }
(method_declaration
  (modifiers (modifier (public)))
  (generic_type                        ← field "type"
    (type_identifier)                  ← "List"
    (type_arguments
      (type_identifier)))              ← "String"
  (identifier)                         ← field "name" = "getNames"
  (formal_parameters)
  (block ...))
```

### `constructor_declaration`
```
[modifiers] [type_parameters] name parameters body
```
- field `body` (required, single): `constructor_body`
- field `name` (required, single): `identifier`
- field `parameters` (required, single): `formal_parameters`
- field `type_parameters` (optional, single): `type_parameters`
- children (optional, single): `modifiers`

Note: Constructors have NO `type` field (no return type).

### `constructor_body`
- children (optional, multiple): `explicit_constructor_invocation` | `statement`

### `explicit_constructor_invocation`
- field `arguments` (required, single): `argument_list`
- field `constructor` (required, single): `super` | `this`
- field `object` (optional, single): `primary_expression`
- field `type_arguments` (optional, single): `type_arguments`

### `formal_parameters`
Container for zero or more `formal_parameter` nodes.
- children (optional, multiple): `formal_parameter`

### `formal_parameter`
```
[modifiers] type name [dimensions]
```
- field `dimensions` (optional, single): `dimensions`
- field `name` (required, single): `identifier`
- field `type` (required, single): `_unannotated_type`
- children (optional, single): `modifiers`

### `argument_list`
- children (optional, multiple): `expression`

---

## 4. Class Members

### `field_declaration`
```
[modifiers] type declarator(s) (accessor_list | ;)
```
- field `declarator` (required, multiple): `variable_declarator`
- field `type` (required, single): `_unannotated_type`
- children (optional, multiple): `accessor_list` | `modifiers`

### `constant_declaration`
```
[modifiers] type declarator(s) ;
```
- field `declarator` (required, multiple): `variable_declarator`
- field `type` (required, single): `_unannotated_type`
- children (optional, single): `modifiers`

### `accessor_list`
- children (required, multiple): `accessor_declaration`

### `accessor_declaration`
```
[modifiers] (get | set) (body | ;)
```
- field `accessor` (required, single): `get` | `set` (anonymous tokens)
- field `body` (optional, single): `block`
- children (optional, single): `modifiers`

### `static_initializer`
```
static block
```
- children (required, single): `block`

---

## 5. Variables & Declarators

### `variable_declarator`
```
name [dimensions] [= value]
```
- field `dimensions` (optional, single): `dimensions`
- field `name` (required, single): `identifier`
- field `value` (optional, single): `array_initializer` | `expression`
- children (optional, single): `assignment_operator`

### `local_variable_declaration`
```
[modifiers] type declarator(s) ;
```
- field `declarator` (required, multiple): `variable_declarator`
- field `type` (required, single): `_unannotated_type`
- children (optional, single): `modifiers`

### `array_initializer`
- children (optional, multiple): `array_initializer` | `expression`

### `map_initializer`
- children (optional, multiple): `map_key_initializer`

### `map_key_initializer`
- children (required, multiple): `expression` (key `=>` value)

---

## 6. Type System

### `annotated_type`
```
@annotation(s) type
```
- children (required, multiple): `_unannotated_type` | `annotation`

### `array_type`
```
element[]
```
- field `dimensions` (required, single): `dimensions`
- field `element` (required, single): `_unannotated_type`

### `generic_type`
```
TypeName<TypeArgs>
```
- children (required, multiple): `scoped_type_identifier` | `type_arguments` | `type_identifier`

Example: `List<String>` → `(generic_type (type_identifier) (type_arguments (type_identifier)))`

Example: `Map<String, Integer>` → `(generic_type (type_identifier) (type_arguments (type_identifier) (type_identifier)))`

### `scoped_type_identifier`
```
OuterType.InnerType
```
- children (required, multiple): `annotation` | `generic_type` | `scoped_type_identifier` | `type_identifier`

### `java_type`
```
java:scoped_type_identifier
```
- children (required, single): `scoped_type_identifier`

### `type_arguments`
```
<type, type, ...>
```
- children (optional, multiple): `_type`

### `type_parameters`
```
<T, U extends Foo, ...>
```
- children (required, multiple): `type_parameter`

### `type_parameter`
- children (required, multiple): `annotation` | `type_bound` | `type_identifier`

### `type_bound`
```
extends Type & Type ...
```
- children (required, multiple): `_type`

### `type_list`
- children (required, multiple): `_type`

### `superclass`
```
extends Type
```
- children (required, single): `_type`

### `interfaces`
```
implements TypeList
```
- children (required, single): `type_list`

### `extends_interfaces`
```
extends TypeList
```
- children (required, single): `type_list`

### Leaf type nodes (no fields, no children):
- `boolean_type` — the `boolean` keyword
- `void_type` — the `void` keyword
- `type_identifier` — aliased from `identifier` in type position
- `dimensions` — `[]` brackets

---

## 7. Statements

### `block`
- children (optional, multiple): `statement`

### `if_statement`
- field `alternative` (optional, single): `statement`
- field `condition` (required, single): `parenthesized_expression`
- field `consequence` (required, single): `statement`

### `for_statement`
- field `body` (required, single): `statement`
- field `condition` (optional, single): `expression`
- field `init` (optional, multiple): `expression` | `local_variable_declaration`
- field `update` (optional, multiple): `expression`

### `enhanced_for_statement`
```
for ([modifiers] type name : value) body
```
- field `body` (required, single): `statement`
- field `dimensions` (optional, single): `dimensions`
- field `name` (required, single): `identifier`
- field `type` (required, single): `_unannotated_type`
- field `value` (required, single): `expression`
- children (optional, single): `modifiers`

### `while_statement`
- field `body` (required, single): `statement`
- field `condition` (required, single): `parenthesized_expression`

### `do_statement`
- field `body` (required, single): `block`
- field `condition` (required, single): `parenthesized_expression`

### `try_statement`
- field `body` (required, single): `block`
- children (required, multiple): `catch_clause` | `finally_clause`

### `catch_clause`
- field `body` (required, single): `block`
- children (required, single): `formal_parameter`

### `finally_clause`
- children (required, single): `block`

### `switch_expression`
```
switch on condition body
```
- field `body` (required, single): `switch_block`
- field `condition` (required, single): `expression`

### `switch_block`
- children (required, multiple): `switch_rule`

### `switch_rule`
- children (required, multiple): `block` | `switch_label`

### `switch_label`
```
when (expression, ...) | when SObjectType var | when else
```
- children (optional, multiple): `expression` | `when_sobject_type`

### `when_sobject_type`
- children (required, multiple): `_unannotated_type` | `identifier`

### `return_statement`
- children (optional, single): `expression`

### `throw_statement`
- children (required, single): `expression`

### `break_statement`
- children (optional, single): `identifier`

### `continue_statement`
- children (optional, single): `identifier`

### `expression_statement`
- children (required, single): `expression`

### `run_as_statement`
```
System.runAs(user) { ... }
```
- field `user` (required, single): `parenthesized_expression`
- children (required, single): `block`

---

## 8. Expressions

### `assignment_expression`
- field `left` (required, single): `array_access` | `field_access` | `identifier`
- field `operator` (required, single): `assignment_operator`
- field `right` (required, single): `expression`

### `binary_expression`
- field `left` (required, single): `expression`
- field `operator` (required, single): one of `!=` `!==` `%` `&` `&&` `*` `+` `-` `/` `<` `<<` `<=` `<>` `==` `===` `>` `>=` `>>` `>>>` `??` `^` `|` `||`
- field `right` (required, single): `expression`

### `ternary_expression`
- field `alternative` (required, single): `expression`
- field `condition` (required, single): `expression`
- field `consequence` (required, single): `expression`

### `unary_expression`
- field `operand` (required, single): `expression`
- field `operator` (required, single): `!` | `+` | `-` | `~`

### `update_expression`
- field `operand` (required, single): `expression`
- field `operator` (required, single): `update_operator` (`++` | `--`)

### `cast_expression`
- field `type` (required, single): `_type`
- field `value` (required, single): `expression`

### `instanceof_expression`
- field `left` (required, single): `expression`
- field `right` (required, single): `_type`

### `dml_expression`
- field `merge_with` (optional, single): `expression`
- field `security_mode` (optional, multiple): `dml_security_mode`
- field `target` (required, single): `expression`
- field `upsert_key` (optional, single): `_unannotated_type`
- children (required, single): `dml_type`

### `dml_type`
- children (required, single): `delete` | `insert` | `merge` | `undelete` | `update` | `upsert`

### `dml_security_mode`
- children (required, single): `system` | `user`

### `method_invocation`
```
[object.] [type_arguments] name arguments
```
- field `arguments` (required, single): `argument_list`
- field `name` (required, single): `identifier`
- field `object` (optional, single): `primary_expression` | `super`
- field `type_arguments` (optional, single): `type_arguments`
- children (optional, single): `safe_navigation_operator`

### `field_access`
```
object.field  OR  object?.field
```
- field `field` (required, single): `identifier` | `this`
- field `object` (required, single): `primary_expression` | `super`
- children (optional, single): `safe_navigation_operator`

### `java_field_access`
```
java:object.field
```
- children (required, single): `field_access`

### `array_access`
- field `array` (required, single): `primary_expression`
- field `index` (required, single): `expression`

### `object_creation_expression`
```
new [type_arguments] type arguments [class_body]
```
- field `arguments` (required, single): `argument_list`
- field `type` (required, single): `_simple_type`
- field `type_arguments` (optional, single): `type_arguments`
- children (optional, single): `class_body`

### `array_creation_expression`
- field `dimensions` (optional, multiple): `dimensions` | `dimensions_expr`
- field `type` (required, single): `_simple_type`
- field `value` (optional, single): `array_initializer`

### `map_creation_expression`
- field `type` (required, single): `_simple_type`
- field `value` (required, single): `map_initializer`

### `parenthesized_expression`
- children (required, single): `expression`

### `class_literal`
```
Type.class
```
- children (required, single): `_unannotated_type`

### `version_expression`
```
Package.Version.Request  OR  Package.Version.1.2
```
- field `version_num` (optional, single): `version_number`

### `query_expression`
```
[SOQL or SOSL query]
```
- children (required, single): `soql_query_body` | `sosl_query_body`

---

## 9. Modifiers & Annotations

### `modifiers`
- children (required, multiple): `annotation` | `modifier`

### `modifier`
One of: `abstract` | `final` | `global` | `inherited_sharing` | `override` | `private` | `protected` | `public` | `static` | `testMethod` | `transient` | `virtual` | `webservice` | `with_sharing` | `without_sharing`

All modifier values are named leaf nodes (no fields, no children).

### `annotation`
```
@Name or @Name(args)
```
- field `arguments` (optional, single): `annotation_argument_list`
- field `name` (required, single): `identifier` | `scoped_identifier`

### `annotation_argument_list`
- field `value` (optional, single): `annotation` | `element_value_array_initializer` | `expression`
- children (optional, multiple): `annotation_key_value`

### `annotation_key_value`
- field `key` (required, single): `identifier`
- field `value` (required, single): `annotation` | `element_value_array_initializer` | `expression`
- children (required, single): `assignment_operator`

### `element_value_array_initializer`
- children (optional, multiple): `annotation` | `element_value_array_initializer` | `expression`

### `scoped_identifier`
- field `name` (required, single): `identifier`
- field `scope` (required, single): `identifier` | `scoped_identifier`

---

## 10. Trigger Events (Leaf Nodes)

`before_insert` | `before_update` | `before_delete` | `after_insert` | `after_update` | `after_delete` | `after_undelete`

---

## 11. DML Keywords (Leaf Nodes)

`insert` | `update` | `delete` | `upsert` | `merge` | `undelete`

---

## 12. Literals (Leaf Nodes)

- `boolean` — `true` / `false`
- `int` — integer literals (e.g. `42`, `100L`)
- `decimal_floating_point_literal` — decimal/float (e.g. `3.14`, `1.0e10`)
- `string_literal` — single-quoted strings (e.g. `'hello'`)
- `null_literal` — `null`

---

## 13. Other Leaf Nodes

- `identifier` — names for variables, types, methods, etc.
- `type_identifier` — aliased from `identifier` when in type position
- `this` — the `this` keyword
- `super` — the `super` keyword
- `safe_navigation_operator` — `?.`
- `assignment_operator` — `=`, `+=`, `-=`, `*=`, `/=`, `&=`, `|=`, `^=`, `%=`, `<<=`, `>>=`, `>>>=`
- `update_operator` — `++`, `--`
- `version_number` — version literal in `Package.Version` expressions
- `boolean_type` — the `boolean` primitive type keyword
- `void_type` — the `void` keyword
- `dimensions` — `[]` array dimension brackets
- `line_comment` — `// ...`
- `block_comment` — `/* ... */`
- `system` — DML security mode keyword
- `user` — DML security mode keyword

---

## Quick Reference: Field Name → Meaning

| Field | Common Nodes | Meaning |
|---|---|---|
| `name` | class/method/constructor/enum/interface/trigger/formal_parameter/variable_declarator/method_invocation | Identifier name |
| `body` | class/method/constructor/trigger/do_statement/for/while/accessor_declaration/catch_clause | Block content |
| `type` | method_declaration/field_declaration/local_variable_declaration/formal_parameter/enhanced_for_statement/cast_expression/array_creation_expression | Type annotation |
| `parameters` | method_declaration/constructor_declaration | `formal_parameters` node |
| `condition` | if/for/while/do/switch/ternary | Condition expression |
| `left` / `right` | binary_expression/assignment_expression/instanceof_expression | Operands |
| `operator` | binary/unary/update/assignment expressions | Operator token |
| `value` | variable_declarator/enhanced_for/array_creation/map_creation/annotation | Initial/assigned value |
| `arguments` | method_invocation/object_creation/explicit_constructor_invocation/annotation | Argument list |
| `object` | method_invocation/field_access/trigger_declaration | Receiver object |
| `field` | field_access | Accessed field name |
| `superclass` | class_declaration | `extends Type` |
| `interfaces` | class_declaration/enum_declaration | `implements TypeList` |
| `type_parameters` | class/interface/method/constructor | `<T, U>` generic params |
| `type_arguments` | method_invocation/object_creation/explicit_constructor | `<Type>` generic args |
| `dimensions` | method/formal_parameter/variable_declarator/array_type/array_creation/enhanced_for | `[]` |
| `declarator` | field_declaration/constant_declaration/local_variable_declaration | Variable declarator(s) |
| `init` / `update` | for_statement | Loop init/update |
| `alternative` / `consequence` | if_statement/ternary_expression | Branches |
| `accessor` | accessor_declaration | `get` or `set` |
