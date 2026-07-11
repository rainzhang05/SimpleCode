; JSON keys and values are separate semantic roles. Do not capture container nodes:
; doing so paints whole objects or arrays over their child strings and numbers.
(pair
  key: (string) @label)
(string) @string
(number) @number
[
  (true)
  (false)
  (null)
] @constant
(escape_sequence) @string
(comment) @comment
