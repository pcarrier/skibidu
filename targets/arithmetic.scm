;; A specification and interface vocabulary only. There is NO seed AST.
((version . 1)
 (assessment . arithmetic)
 (output . "generated/calc.scm")
 (goal . "Build a tiny arithmetic interpreter from an empty AST. Generate every import, definition and function body. Define (calc expression), returning the exact integer value of an already parsed Scheme datum. The complete input grammar is: expression = integer | (+ expression expression) | (* expression expression). Inputs are always valid; + and * each have exactly two operands. Support arbitrary nesting, zero and negative integers. Examples: (calc 7) => 7; (calc '(+ 2 3)) => 5; (calc '(* 4 5)) => 20; (calc '(+ 2 (* 3 4))) => 14; (calc '(* (+ 1 2) (+ 3 4))) => 21. Implement the operator dispatch and recursion yourself; native integer arithmetic is allowed. Only import (scheme base). Do not use eval, load, include or include-ci. No parser, environment, macros, library system, output or CLI is needed. Do not call calc at top level. Use the smallest correct implementation.")
 (runtime . "Chibi Scheme 0.12, R7RS-small (scheme base) only. Supply your own imports. The harness loads your program and calls calc with Scheme data; it handles all reading and printing. Argument evaluation order is unspecified.")
 (symbols calc)
 (literals))
