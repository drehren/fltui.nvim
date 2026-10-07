;; extends

(function_call
  (dot_index_expression
    field: (identifier) @_method
    (#any-of? @_method "find_word" "col_word"))
  arguments: (arguments
    .
    (_)
    .
    (_)
    .
    (string
      content: (string_content) @injection.content
      (#set! injection.language "luap")
      (#set! injection.include-children)))) 
