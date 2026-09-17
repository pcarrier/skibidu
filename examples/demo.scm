(define-library (example arithmetic)
  (export twice)
  (import (scheme base))
  (begin
    (define-syntax twice
      (syntax-rules ()
        ((_ expression)
         (let ((value expression)) (+ value value)))))))

(import (scheme base) (scheme write) (example arithmetic))
(write (list (twice 21)
             (let loop ((n 42) (answer 0))
               (if (zero? n) answer (loop (- n 1) (+ answer 1))))))
(newline)
