;; Chibi's JSON representation: symbol-keyed alists, vectors, and 'null.
;; Keep string keys convenient at call sites; encoding/decoding is native.
(define (json-key key) (if (symbol? key) key (string->symbol key)))
(define (object . entries)
  (map (lambda (entry) (cons (json-key (car entry)) (cdr entry))) entries))
(define (field x key . fallback)
  (let ((entry (and (list? x) (assq (json-key key) x))))
    (cond (entry (cdr entry)) ((pair? fallback) (car fallback))
          (else (error "missing object field" key)))))
(define (datum-string x) (with-output-to-string (lambda () (write x))))

;; Reject ambiguous fields, unrepresentable numbers, and trailing input at the
;; API boundary. JSON syntax and Unicode handling belong to (chibi json).
(define (validate-json value)
  (cond
    ((list? value)
     (let loop ((entries value))
       (unless (null? entries)
         (when (assq (caar entries) (cdr entries)) (error "duplicate JSON key" (caar entries)))
         (validate-json (cdar entries)) (loop (cdr entries)))))
    ((vector? value) (vector-for-each validate-json value))
    ((or (string? value) (boolean? value) (eq? value 'null)))
    ((and (real? value) (< -inf.0 value +inf.0)))
    (else (error "invalid JSON value" value))))
(define (json-read text)
  (call-with-port (open-input-string text)
    (lambda (port)
      (let ((value (native-json-read port)))
        (let skip-space ()
          (let ((c (read-char port)))
            (cond ((memv c '(#\space #\tab #\return #\newline)) (skip-space))
                  ((not (eof-object? c)) (error "trailing JSON input")))))
        (validate-json value)
        value))))
