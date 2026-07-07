; Vendored, UNMODIFIED copy of the Swift tree-sitter grammar's highlight query.
;
; Source:  https://github.com/alex-pinkus/tree-sitter-swift
; Version: 0.7.3-with-generated-files (pinned dependency version; see project.yml)
; File:    queries/highlights.scm
; License: MIT (c) Alex Pinkus and contributors — see upstream repository LICENSE.
;
; This project depends on `alex-pinkus/tree-sitter-swift` as a Swift Package Manager
; dependency for the compiled grammar (`TreeSitterSwift` C target). That target has no
; Swift sources, so SwiftPM does not synthesize a stable bundle accessor for its
; bundled `queries/` resources. Rather than relying on the resource bundle's internal,
; undocumented file-naming convention across a package boundary, this file is vendored
; verbatim into this app's own resources (with attribution preserved). Do not hand-edit;
; replace wholesale if the pinned grammar version changes.

[
  "."
  ";"
  ":"
  ","
] @punctuation.delimiter

[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
] @punctuation.bracket

; Identifiers
(type_identifier) @type

[
  (self_expression)
  (super_expression)
] @variable.builtin

; Declarations
[
  "func"
  "deinit"
] @keyword.function

[
  (visibility_modifier)
  (member_modifier)
  (function_modifier)
  (property_modifier)
  (parameter_modifier)
  (inheritance_modifier)
  (mutation_modifier)
] @keyword.modifier

(simple_identifier) @variable

(function_declaration
  (simple_identifier) @function.method)

(protocol_function_declaration
  name: (simple_identifier) @function.method)

(init_declaration
  "init" @constructor)

(parameter
  external_name: (simple_identifier) @variable.parameter)

(parameter
  name: (simple_identifier) @variable.parameter)

(type_parameter
  (type_identifier) @variable.parameter)

(inheritance_constraint
  (identifier
    (simple_identifier) @variable.parameter))

(equality_constraint
  (identifier
    (simple_identifier) @variable.parameter))

[
  "protocol"
  "extension"
  "indirect"
  "nonisolated"
  "override"
  "convenience"
  "required"
  "some"
  "any"
  "weak"
  "unowned"
  "didSet"
  "willSet"
  "subscript"
  "let"
  "var"
  (throws)
  (where_keyword)
  (getter_specifier)
  (setter_specifier)
  (modify_specifier)
  (else)
  (as_operator)
] @keyword

[
  "enum"
  "struct"
  "class"
  "typealias"
] @keyword.type

[
  "async"
  "await"
] @keyword.coroutine

(shebang_line) @keyword.directive

(class_body
  (property_declaration
    (pattern
      (simple_identifier) @variable.member)))

(protocol_property_declaration
  (pattern
    (simple_identifier) @variable.member))

(navigation_expression
  (navigation_suffix
    (simple_identifier) @variable.member))

(value_argument
  name: (value_argument_label
    (simple_identifier) @variable.member))

(import_declaration
  "import" @keyword.import)

(enum_entry
  "case" @keyword)

(modifiers
  (attribute
    "@" @attribute
    (user_type
      (type_identifier) @attribute)))

; Function calls
(call_expression
  (simple_identifier) @function.call) ; foo()

(call_expression
  ; foo.bar.baz(): highlight the baz()
  (navigation_expression
    (navigation_suffix
      (simple_identifier) @function.call)))

(call_expression
  (prefix_expression
    (simple_identifier) @function.call)) ; .foo()

((navigation_expression
  (simple_identifier) @type) ; SomeType.method(): highlight SomeType as a type
  (#match? @type "^[A-Z]"))

(directive) @keyword.directive

; See https://docs.swift.org/swift-book/documentation/the-swift-programming-language/lexicalstructure/#Keywords-and-Punctuation
[
  (diagnostic)
  (availability_condition)
  (playground_literal)
  (key_path_string_expression)
  (selector_expression)
  (external_macro_definition)
