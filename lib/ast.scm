;; Generic S-expression AST. No interpreter fragment is embedded here.
;; The program root is a list of top-level forms; all nodes start as holes.
(define (node-kind node) (vector-ref node 0))
(define (pending-node? node) (memq (node-kind node) '(hole token spell)))
(define (node-children node)
  (case (node-kind node)
    ((program list vector) (vector-ref node 1))
    ((pair) (list (vector-ref node 1) (vector-ref node 2)))
    (else '())))
(define (node-with-children node children)
  (if (eq? (node-kind node) 'pair)
      (vector 'pair (car children) (cadr children))
      (vector (node-kind node) children)))
(define (map-indexed procedure xs)
  (let loop ((xs xs) (i 0))
    (if (null? xs) '() (cons (procedure i (car xs)) (loop (cdr xs) (+ i 1))))))
(define (integers-from start count)
  (let loop ((i start)) (if (= i (+ start count)) '() (cons i (loop (+ i 1))))))
(define (ast-at node path)
  (if (null? path) node (ast-at (list-ref (node-children node) (car path)) (cdr path))))
(define (ast-replace node path replacement)
  (if (null? path) replacement
      (node-with-children node
        (map-indexed (lambda (i child)
                       (if (= i (car path)) (ast-replace child (cdr path) replacement) child))
                     (node-children node)))))
(define (ast-complete? node)
  (and (not (pending-node? node)) (all? ast-complete? (node-children node))))
(define (ast-datum node)
  (case (node-kind node)
    ((atom) (vector-ref node 1))
    ((program list) (map ast-datum (node-children node)))
    ((pair) (cons (ast-datum (vector-ref node 1)) (ast-datum (vector-ref node 2))))
    ((vector) (list->vector (map ast-datum (node-children node))))
    (else (cons '? (vector->list node)))))
(define (ast-regions tree)
  (let walk ((node tree) (path '()))
    (cons (list path node)
          (apply append
            (map-indexed (lambda (i child) (walk child (append path (list i))))
                         (node-children node))))))
(define (ast-size tree) (length (ast-regions tree)))
(define (ast-construction-key node)
  ;; Hole IDs identify checkpoint nodes, not progress. A backtrack followed by
  ;; the same construction must compare equal even after allocating fresh IDs.
  (cond ((pending-node? node) (cons (node-kind node) (cddr (vector->list node))))
        ((eq? (node-kind node) 'atom) node)
        (else (cons (node-kind node) (map ast-construction-key (node-children node))))))
(define (ast-symbols tree extras)
  (let ((out extras))
    (for-each (lambda (region)
                (let ((node (cadr region)))
                  (when (and (eq? (node-kind node) 'atom) (symbol? (vector-ref node 1))
                             (not (memq (vector-ref node 1) out)))
                    (set! out (cons (vector-ref node 1) out))))) (ast-regions tree))
    (reverse out)))

;; Parents precede children; operator and binding positions precede dependent
;; bodies. Independent arguments share a model request and its context.
(define (ast-frontier tree)
  (define (walk node path)
    (define (child i n) (walk n (append path (list i))))
    (define (first-incomplete children)
      (let loop ((xs children) (i 0))
        (cond ((null? xs) '())
              ((not (ast-complete? (car xs))) (child i (car xs)))
              (else (loop (cdr xs) (+ i 1))))))
    (let ((children (node-children node)))
      (cond ((pending-node? node) (list (list path node)))
            ((null? children) '())
            ((or (eq? (node-kind node) 'program)
                 (and (eq? (node-kind node) 'list)
                      (or (not (ast-complete? (car children)))
                          (memq (ast-datum (car children))
                                '(define define-values define-syntax lambda case-lambda
                                  let let* letrec letrec* let-values let*-values
                                  let-syntax letrec-syntax define-library import begin)))))
             (first-incomplete children))
            (else (apply append (map-indexed child children))))))
  (walk tree '()))

;; A vocabulary, not a program. Names not listed here can be spelled from
;; characters and then reused through the "seen" group.
(define scheme-vocabulary
  '((syntax quote quasiquote unquote unquote-splicing lambda if set! begin cond case
      and or when unless else => let let* letrec letrec* let-values let*-values
      define define-values define-syntax syntax-rules let-syntax letrec-syntax
      define-record-type define-library export import only except prefix rename
      include include-ci cond-expand do parameterize guard case-lambda)
    (base + - * / = < > <= >= zero? positive? negative? odd? even? abs max min
      quotient remainder modulo floor ceiling round truncate expt sqrt exact inexact
      number? integer? exact? real? not boolean? eq? eqv? equal? procedure? apply
      values call-with-values call/cc call-with-current-continuation dynamic-wind
      make-parameter error raise raise-continuable with-exception-handler error-object?)
    (data cons car cdr caar cadr cdar cddr caadr caddr cdddr cadddr set-car! set-cdr!
      list list? pair? null? length append reverse list-ref list-tail map for-each
      member memq memv assoc assq assv symbol? symbol->string string->symbol
      string? string string-length string-ref string-set! string-append substring
      string=? string<? string-copy string->list list->string number->string
      string->number char? char=? char<? char->integer integer->char vector vector?
      make-vector vector-length vector-ref vector-set! vector->list list->vector
      bytevector bytevector? bytevector-length bytevector-u8-ref bytevector-u8-set!)
    (io read write display newline read-char peek-char read-line read-string
      eof-object? eof-object current-input-port current-output-port current-error-port
      open-input-string open-output-string get-output-string close-input-port
      close-output-port open-input-file open-output-file call-with-input-file
      call-with-output-file with-input-from-file with-output-to-file call-with-port
      flush-output flush-output-port read-u8 write-u8 file-exists? delete-file)
    (runtime eval environment mutable-environment repl-import interaction-environment load command-line
      resolve-import module-env load-module %import
      get-environment-variable exit emergency-exit current-directory change-directory
      with-directory path-directory path-absolute? path-resolve port->string file->string)
    (libraries scheme base read write eval repl load file char cxr lazy inexact
      complex process-context time case-lambda chibi io pathname filesystem meta ast)
    (names a b c d e f g h i j k n m p q r s x y z xs ys args v0 v1 v2 v3 v4 v5)))

(define (spell-value kind text)
  ;; Return a tagged result so the literal #f cannot be confused with failure.
  (case kind
    ((string) (list text))
    ((number) (let ((n (string->number text))) (and n (list n))))
    ((symbol)
     (and (> (string-length text) 0)
          (guard (ex (else #f))
            (with-input-from-string text
              (lambda ()
                (let ((x (read)))
                  (and (symbol? x) (eof-object? (read)) (list x))))))))))

;; Offer only viable plain identifier prefixes. Let Chibi check peculiar names
;; such as +, -, and .x; a trailing letter allows incomplete prefixes like ".".
;; Delimiters belong to AST constructors, not to identifier spelling.
(define (symbol-prefix? text)
  (and (all? (lambda (c) (or (char-alphabetic? c) (char-numeric? c)
                             (string-index "!$%&*/:<=>?^_~+-.@" c)))
             (string->list text))
       (or (string=? text "") (spell-value 'symbol text)
           (spell-value 'symbol (string-append text "a")))))

(define (spelling-problem node max-literal)
  (and (eq? (node-kind node) 'spell)
       (let ((kind (vector-ref node 2)) (text (vector-ref node 3)))
         (cond ((and (eq? kind 'symbol) (not (spell-value kind text)) (not (symbol-prefix? text)))
                "Invalid identifier prefix. Choose restart to rebuild this node, or backspace to correct it.")
               ((>= (string-length text) max-literal)
                "Spelling length limit reached. Choose end if available, otherwise backspace or restart.")
               (else #f)))))

;; Describe the decision in source-language terms, not just our internal AST
;; instruction set. No target implementation or compound source is supplied.
(define (construction-role tree path)
  (if (null? path) "Program container: its children are top-level forms, not arguments of a Scheme call."
      (let* ((parent (ast-at tree (take-up-to path (- (length path) 1))))
             (index (car (reverse path))))
        (if (eq? (node-kind parent) 'program)
            "One top-level form. Imports and definitions require a list; a bare name only refers to a variable."
            (string-append "Child " (number->string index) " of "
                           (short-text (datum-string (ast-datum parent)) 200))))))
(define (constructor-description plan root? tree symbols)
  ;; Keep the machine plan readable as the first datum for local test oracles.
  (string-append (datum-string plan) " ; "
    (case (car plan)
      ((list) (string-append (number->string (cadr plan))
                             (if root? " top-level forms in the program." " children in a proper list, including its head.")))
      ((vector) (string-append (number->string (cadr plan)) " elements in a vector datum."))
      ((pair) "Dotted pair with car and cdr children.")
      ((atom) (case (cadr plan)
                ((define) "Define a variable or function.") ((import) "Import library bindings.")
                ((begin) "Group forms in sequence.")
                (else (if (symbol? (cadr plan)) "Use this identifier." "Use this literal value."))))
      ((spell) (string-append "Spell a new " (symbol->string (cadr plan)) " one character at a time."))
      ((append-char) (string-append "Append " (datum-string (string (cadr plan))) " to the prefix."))
      ((restart) "Discard this unfinished token and choose its structure again.")
      ((backspace) "Remove the last prefix character.")
      ((backtrack) "The enclosing structure is wrong; choose an ancestor to rebuild.")
      ((tokens)
       (case (cadr plan)
         ((seen) (string-append "Choose an existing name: " (short-text (datum-string (ast-symbols tree symbols)) 180)))
         ((syntax) "Choose a syntax keyword, e.g. import, define, lambda, if, let, quote.")
         ((base) "Choose arithmetic, predicates, equality or control procedures.")
         ((data) "Choose list, pair, string, symbol or vector procedures.")
         ((io) "Choose reading, printing or port procedures.")
         ((runtime) "Choose host evaluation, environment or process procedures.")
         ((libraries) "Choose a library name component, e.g. scheme, base, chibi.")
         ((names) "Choose a short variable name.")
         ((characters) "Choose one character literal.")
         (else "Choose a token page.")))
      (else "Choose this constructor."))))

;; A small declaration grammar for targets requiring imports and definitions.
;; It constrains individual nodes, without supplying any function body.
(define (scheme-node-role tree path)
  (if (null? path) 'program
      (let* ((parent-path (take-up-to path (- (length path) 1)))
             (parent (ast-at tree parent-path)) (role (scheme-node-role tree parent-path))
             (index (car (reverse path)))
             (children (node-children parent))
             (head (and (pair? children) (ast-datum (car children)))))
        (case role
          ((program) 'declaration)
          ((declaration)
           (cond ((zero? index) 'declaration-keyword)
                 ((eq? head 'import) 'base-import)
                 ((and (eq? head 'define) (= index 1)) 'definition-target)
                 ((eq? head 'begin) 'declaration)
                 (else 'expression)))
          ((base-import) (if (zero? index) 'scheme-name 'base-name))
          ((definition-target) 'identifier)
          ((expression)
           (cond ((zero? index) 'expression-head)
                 ((memq head '(quote quasiquote)) 'datum)
                 ;; Binding and clause grammars remain generic data; their
                 ;; bodies will still be checked by the sandbox.
                 ((and (= index 1) (memq head '(lambda let let* letrec letrec*))) 'datum)
                 ((memq head '(cond case)) 'datum)
                 (else 'expression)))
          ((datum) 'datum)
          (else 'expression)))))
(define (scheme-syntax-options tree path symbols options)
  (let* ((role (scheme-node-role tree path))
         (parent (and (pair? path) (ast-at tree (take-up-to path (- (length path) 1)))))
         (keywords (if (and parent (>= (length (node-children parent)) 3))
                       '(import define begin) '(import begin)))
         (terminals (case role ((declaration-keyword) keywords) ((scheme-name) '(scheme))
                              ((base-name) '(base)) (else #f))))
    (define (identifier? value)
      (and (symbol? value) (not (memq value (cdr (assq 'syntax scheme-vocabulary))))))
    (define (accept? plan)
      (let ((kind (car plan)))
        (or (memq kind '(restart backspace backtrack))
            (case role
              ((program) (and (eq? kind 'list) (> (cadr plan) 0)))
              ((declaration) (and (eq? kind 'list) (>= (cadr plan) 2)))
              ((base-import) (and (eq? kind 'list) (= (cadr plan) 2)))
              ((declaration-keyword scheme-name base-name)
               (or (and (eq? kind 'atom)
                        (memq (cadr plan) (case role ((declaration-keyword) keywords)
                                                 ((scheme-name) '(scheme)) (else '(base)))))
                   (and (eq? kind 'tokens)
                        (eq? (cadr plan) (if (eq? role 'declaration-keyword) 'syntax 'libraries)))))
              ((definition-target identifier)
               (or (and (eq? role 'definition-target) (eq? kind 'list) (> (cadr plan) 0))
                   (and (eq? kind 'atom) (identifier? (cadr plan)))
                   (and (eq? kind 'tokens) (memq (cadr plan) '(seen names)))
                   (and (eq? kind 'spell) (eq? (cadr plan) 'symbol))
                   (and (eq? kind 'append-char) (eq? (vector-ref (ast-at tree path) 2) 'symbol))))
              ((expression expression-head)
               (case kind
                 ((atom) (if (eq? role 'expression-head) (symbol? (cadr plan))
                             (or (not (symbol? (cadr plan))) (identifier? (cadr plan)))))
                 ((list) (> (cadr plan) 0))
                 ((tokens) (or (eq? role 'expression-head) (not (eq? (cadr plan) 'syntax))))
                 ((spell) (or (eq? role 'expression) (eq? (cadr plan) 'symbol)))
                 ((append-char) #t)
                 (else (eq? role 'expression))))
              (else #t)))))
    (if terminals
        ;; Competing keywords must be equally visible. Offering a seen import
        ;; directly while hiding define behind a group caused repeated imports.
        (append (map-indexed (lambda (i value) (cons (string-append "terminal:" (number->string i)) (list 'atom value))) terminals)
                (select (lambda (option) (memq (cadr option) '(restart backspace))) options))
        (select (lambda (option) (accept? (cdr option)))
      (append
        ;; Direct reuse avoids spelling a known name such as the target's API.
        (if (eq? (node-kind (ast-at tree path)) 'hole)
            (map-indexed (lambda (i name) (cons (string-append "known:" (number->string i)) (list 'atom name)))
                         (take-up-to (ast-symbols tree symbols) (max 0 (min 64 (- 254 (length options)))))) '())
        options)))))

;; Return (label . constructor) entries. The selected constructor creates only
;; one node; every child remains an independently model-generated hole.
(define (ast-options tree path extra-symbols literal-hints max-depth max-width max-literal)
  (let ((node (ast-at tree path)))
    (define (labeled prefix values make)
      (map (lambda (v) (cons (string-append prefix (number->string v)) (make v))) values))
    (case (node-kind node)
      ((hole)
       (let ((lists (labeled "list:" (integers-from 0 (+ max-width 1)) (lambda (n) (list 'list n)))))
         (if (null? path) lists
             (append
               (if (< (length path) max-depth)
                   (append lists (labeled "vector:" (integers-from 0 (+ max-width 1))
                                         (lambda (n) (list 'vector n)))
                           (list (cons "pair" '(pair))))
                   (list (cons "list:0" '(list 0)) (cons "vector:0" '(vector 0))))
               (map (lambda (group) (cons (string-append "symbols:" (symbol->string group))
                                          (list 'tokens group #f)))
                    (append (if (pair? (ast-symbols tree extra-symbols)) '(seen) '())
                            (map car scheme-vocabulary)))
               (list (cons "new-symbol" '(spell symbol ""))
                     (cons "string" '(spell string "")) (cons "number" '(spell number ""))
                     (cons "character" '(tokens characters #f))
                     (cons "false" '(atom #f)) (cons "true" '(atom #t)))
               (map-indexed (lambda (i value) (cons (string-append "literal:" (number->string i))
                                                   (list 'atom value)))
                            (append '("" 0 1 -1 2 3 4 5 8 10 16 32 64 100 255 256 1000) literal-hints))))))
      ((token)
       (let* ((group (vector-ref node 2)) (page (vector-ref node 3))
              (tokens (cond ((eq? group 'seen) (ast-symbols tree extra-symbols))
                            ((eq? group 'characters) (map integer->char (integers-from 0 128)))
                            (else (cdr (assq group scheme-vocabulary)))))
              (pages (batches tokens 200)))
         (cons '("restart" restart)
          (if (and (not page) (> (length pages) 1))
             (labeled "page:" (integers-from 0 (length pages))
                      (lambda (n) (list 'tokens group n (list-ref pages n))))
             (map-indexed (lambda (i atom) (cons (string-append "atom:" (number->string i))
                                                (list 'atom atom)))
                          (if (null? pages) '() (list-ref pages (or page 0))))))))
      ((spell)
       (let* ((kind (vector-ref node 2)) (text (vector-ref node 3))
              (value (spell-value kind text)))
         (append (if (and value (<= (string-length text) max-literal))
                     (list (cons "end" (list 'atom (car value)))) '())
                 '(("restart" restart))
                 (if (string=? text "") '()
                     '(("backspace" backspace)))
                 (if (< (string-length text) max-literal)
                     (labeled "char:"
                       (select (lambda (code)
                                 (or (not (eq? kind 'symbol))
                                     (symbol-prefix? (string-append text (string (integer->char code))))))
                               (integers-from 32 95))
                       (lambda (code) (list 'append-char (integer->char code))))
                     '()))))
      (else (fail 'ast "node is already constructed" path)))))

(define (ast-construct plan previous root? hole)
  (case (car plan)
    ((restart) (vector 'hole (vector-ref previous 1)))
    ((backspace)
     (let ((text (vector-ref previous 3)))
       (vector 'spell (vector-ref previous 1) (vector-ref previous 2)
               (substring text 0 (- (string-length text) 1)))))
    ((append-char)
     (vector 'spell (vector-ref previous 1) (vector-ref previous 2)
             (string-append (vector-ref previous 3) (string (cadr plan)))))
    ((atom) (vector 'atom (cadr plan)))
    ((list vector)
     (vector (if root? 'program (car plan))
             (map (lambda (i) (hole)) (integers-from 0 (cadr plan)))))
    ((pair) (vector 'pair (hole) (hole)))
    ((tokens) (vector 'token (vector-ref previous 1) (cadr plan) (caddr plan)))
    ((spell) (vector 'spell (vector-ref previous 1) (cadr plan) (caddr plan)))
    (else (fail 'ast "unknown constructor" plan))))

(define (validate-ast tree max-nodes max-depth)
  (let ((remaining max-nodes) (ids '()))
    (define (walk node depth root?)
      (set! remaining (- remaining 1))
      (unless (and (>= remaining 0) (<= depth max-depth) (vector? node)
                   (>= (vector-length node) 2)) (fail 'ast "invalid or oversized AST"))
      (let ((kind (node-kind node)))
        (when (pending-node? node)
          (let ((id (vector-ref node 1)))
            (unless (and (integer? id) (>= id 0) (not (memv id ids)))
              (fail 'ast "invalid or duplicate hole id"))
            (set! ids (cons id ids))))
        (unless (if root? (memq kind '(program hole)) (not (eq? kind 'program)))
          (fail 'ast "invalid program root"))
        (case kind
          ((hole) (unless (= 2 (vector-length node)) (fail 'ast "invalid hole")))
          ((token)
           (unless (and (= 4 (vector-length node))
                        (or (memq (vector-ref node 2) '(seen characters))
                            (assq (vector-ref node 2) scheme-vocabulary))
                        (or (eq? #f (vector-ref node 3))
                            (and (integer? (vector-ref node 3)) (>= (vector-ref node 3) 0))))
             (fail 'ast "invalid token node")))
          ((spell)
           (unless (and (= 4 (vector-length node)) (memq (vector-ref node 2) '(symbol string number))
                        (string? (vector-ref node 3))) (fail 'ast "invalid spelling node")))
          ((atom)
           (unless (and (= 2 (vector-length node))
                        (let ((x (vector-ref node 1)))
                          (or (symbol? x) (string? x) (number? x) (char? x) (boolean? x))))
             (fail 'ast "invalid atom")))
          ((program list vector)
           (unless (and (= 2 (vector-length node)) (list? (vector-ref node 1)))
             (fail 'ast "invalid child list")))
          ((pair) (unless (= 3 (vector-length node)) (fail 'ast "invalid pair")))
          (else (fail 'ast "unknown node kind" kind)))
        (for-each (lambda (child) (walk child (+ depth 1) #f)) (node-children node))))
    (walk tree 0 #t)
    ids))
