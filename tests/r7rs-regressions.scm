;; Regression probes for runtime behavior that failed before the Chibi migration.
;; These are now mandatory acceptance cases, alongside tests/r7rs-cases.scm.
((fold-case "#!fold-case (DEFINE UPPER 42) (WRITE upper) #!no-fold-case" "42")
 (reader-escape "(write (string=? \"A\\x42;C\" \"ABC\"))" "#t")
 (export-rename "(define-library (test renamed) (import (scheme base)) (export (rename internal public)) (begin (define internal 42))) (import (test renamed)) (write public)" "42")
 (cyclic-equal "(define a (list 1)) (define b (list 1)) (set-cdr! a a) (set-cdr! b b) (write (equal? a b))" "#t"))
