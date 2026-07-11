(identifier) @variable
(field_identifier) @variable

(comment) @comment
(string_literal) @string
(raw_string_literal) @string
(char_literal) @string
(number_literal) @number
(primitive_type) @type
(type_identifier) @type
(sized_type_specifier) @type

[
  "break" "case" "catch" "class" "const" "constexpr" "consteval"
  "constinit" "continue" "default" "delete" "do" "else" "enum" "explicit"
  "extern" "for" "friend" "if" "inline" "mutable" "namespace" "new"
  "noexcept" "operator" "private" "protected" "public" "return" "sizeof"
  "static" "struct" "switch" "template" "throw" "try" "typedef" "typename"
  "union" "using" "virtual" "volatile" "while"
] @keyword

(function_declarator
  declarator: (identifier) @function)
(function_declarator
  declarator: (field_identifier) @function)
(call_expression
  function: (identifier) @function)
(call_expression
  function: (field_expression
    field: (field_identifier) @function))

(preproc_include) @preprocessor
(preproc_def) @preprocessor
(preproc_function_def) @preprocessor
(preproc_call) @preprocessor
(preproc_if) @preprocessor
(preproc_ifdef) @preprocessor
(preproc_else) @preprocessor
(preproc_elif) @preprocessor
