; Base identifiers are intentionally captured first so declarations and calls below
; can take precedence in the final semantic pass.
(identifier) @variable
(field_identifier) @variable

(comment) @comment
(string_literal) @string
(char_literal) @string
(number_literal) @number
(primitive_type) @type
(type_identifier) @type
(sized_type_specifier) @type

[
  "break" "case" "const" "continue" "default" "do" "else" "enum"
  "extern" "for" "goto" "if" "inline" "register" "return" "sizeof"
  "static" "struct" "switch" "typedef" "union" "volatile" "while"
] @keyword

(function_declarator
  declarator: (identifier) @function)
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
