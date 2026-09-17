;; TEST FIXTURE ONLY. Never supplied to the live model.
(import (scheme base))
(define (calc expression)
  (if (integer? expression)
      expression
      (let ((left (calc (car (cdr expression))))
            (right (calc (car (cdr (cdr expression))))))
        (if (eq? (car expression) '+)
            (+ left right)
            (* left right)))))
