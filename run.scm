;; Loader only. All interpreter and CLI behavior lives in the generated AST.
(import (scheme base) (scheme eval) (scheme load) (scheme process-context)
        (only (meta) mutable-environment))
(let ((arguments (cdr (command-line))))
  (when (null? arguments) (error "usage: chibi-scheme run.scm INTERPRETER.scm [arguments ...]"))
  (let ((scope (mutable-environment '(rename (only (meta) repl-import) (repl-import import)))))
    (load (car arguments) scope)
    ((eval 'main scope) (cdr arguments))))
