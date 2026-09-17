;; Local transport fixture used only by tests/restart.scm. No network I/O.
(import (scheme base) (scheme read) (scheme write) (scheme file)
        (scheme process-context) (chibi json))
(define args (cdr (command-line)))
(define request-argument (cadr (member "--data-binary" args)))
(define request-path (substring request-argument 1 (string-length request-argument)))
(define response-path (cadr (member "--output" args)))
(define count-path (get-environment-variable "SKIBIDU_FIXTURE_COUNT"))
(define count (if (file-exists? count-path) (call-with-input-file count-path read) 0))
(define request (call-with-input-file request-path json-read))
(define limited? (and (equal? (get-environment-variable "SKIBIDU_FIXTURE_MODE") "429") (> count 0)))
(define answers
  (map (lambda (q) (cons (car q) '((type . "choice") (choice . "keep") (confidence . 1.0))))
       (cdr (assq 'questions request))))
(call-with-output-file count-path (lambda (p) (write (+ count 1) p)))
(call-with-output-file response-path
  (lambda (p)
    (json-write
      (if limited? '((error . "Test fixture: rate limited"))
          `((model . "test-fixture") (usage (input_tokens . 100) (output_tokens . 0))
            (answers . ,answers))) p)))
(display (if limited? "429" "200"))
