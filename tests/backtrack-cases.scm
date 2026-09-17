;; Included by tests/run.scm: local oracles only, no provider requests.
(let* ((tree '#(program (#(list (#(atom +)
                               #(list (#(atom bad) #(hole 1) #(hole 2) #(hole 3)))
                               #(hole 4))))))
       (target '((+ 0 1))))
  (define (oracle root?)
    (lambda (state questions)
      (answers questions
        (lambda (id q)
          (case (string->symbol (field state "phase"))
            ((backtrack) (if (and root? (string=? id "(0 1 1)")) "up:3" "up:1"))
            ((confirm) "keep")
            (else
             (if (zero? (vector-length (field state "recent_abandonments")))
                 (if (member id '("(0 1 1)" "(0 1 2)")) "backtrack" "literal:2")
                 (fixture-construct (if root? '(1) target) id q))))))))
  (for-each
    (lambda (root?)
      (let* ((run (exercise (oracle root?) passing
                           (object (cons "ast" tree) (cons "next_id" 5) (cons "max_calls" 20))))
             (events (cadr run))
             (backtracks (select (lambda (e) (eq? 'backtrack (car e))) events))
             (discarded (select (lambda (e) (eq? 'discarded-choice (car e))) events)))
        (check (list 'backtrack-result root?) (equal? (if root? '(1) target) (cdr (assq 'source (car run)))))
        (check (list 'overlapping-backtracks-merge root?) (= 1 (length backtracks)))
        (check (list 'ancestor-target root?) (equal? (if root? "()" "(0 1)") (field (cadar backtracks) "target")))
        (check (list 'stale-batch-choices-discarded root?) (= (if root? 2 1) (length discarded)))
        (check 'history-fed-back
          (pair? (select (lambda (e) (and (eq? 'request (car e))
                                         (> (vector-length (field (caddr e) "recent_abandonments")) 0))) events)))))
    '(#f #t))
  ;; Exhaust the budget immediately after the ancestor choice, then resume
  ;; using the checkpoint's new hole ID and recovery history.
  (let ((saved #f))
    (check 'backtrack-interruption
      (raises? (lambda ()
        (synthesize-ast "local recovery test" (oracle #f) passing
          (object (cons "ast" tree) (cons "next_id" 5) (cons "max_calls" 2))
          (lambda (e) (when (eq? (car e) 'checkpoint) (set! saved e)) (record e))))))
    (check 'backtrack-checkpoint-preserves-sibling (equal? '#(atom 1) (ast-at (caddr saved) '(0 2))))
    (check 'backtrack-checkpoint-has-new-hole (equal? '#(hole 5) (ast-at (caddr saved) '(0 1))))
    (check 'backtrack-checkpoint-remembers (= 1 (length (list-ref saved 6))))
    (let ((run (exercise (fixture-oracle target) passing
                 (object (cons "ast" (caddr saved)) (cons "next_id" (cadddr saved))
                         (cons "recovery_history" (list-ref saved 6)) (cons "max_calls" 4)))))
      (check 'backtrack-resume (equal? target (cdr (assq 'source (car run))))))))

(let* ((target '(#(0 1)))
       (run (exercise
              (lambda (state questions)
                (answers questions (lambda (id q)
                  (case (string->symbol (field state "phase"))
                    ((confirm) "keep") ((backtrack) "up:1")
                    (else (if (zero? (vector-length (field state "recent_abandonments")))
                              "backtrack" (fixture-construct target id q)))))))
              passing (object (cons "ast" '#(program (#(vector (#(list (#(atom bad) #(hole 1)))
                                                                 #(list (#(atom bad) #(hole 2))))))))
                              (cons "next_id" 3) (cons "max_calls" 5)))))
  (check 'disjoint-ancestors-rebuilt (equal? target (cdr (assq 'source (car run)))))
  (check 'disjoint-backtracks-recorded (= 2 (length (select (lambda (e) (eq? 'backtrack (car e))) (cadr run))))))

(let* ((history (map (lambda (n) (object (cons "path" "(0)") (cons "action" "backtrack")
                                        (cons "source" (number->string n)))) (integers-from 0 8)))
       (run (exercise
              (lambda (state questions)
                (answers questions (lambda (id q)
                  (cond ((equal? (field state "phase") "confirm") "keep")
                        ((assq 'restart (field q "criteria")) "restart")
                        (else "literal:1")))))
              passing (object (cons "ast" (vector 'program (list (vector 'spell 1 'symbol (make-string 300 #\x)))))
                              (cons "next_id" 2) (cons "recovery_history" history) (cons "max_calls" 4))))
       (saved (list-ref (car (select (lambda (e) (eq? 'checkpoint (car e))) (reverse (cadr run)))) 6)))
  (check 'history-bounded (= 8 (length saved)))
  (check 'history-source-truncated (<= (string-length (field (car saved) "source")) 243))
  (check 'history-oldest-evicted (not (member (list-ref history 7) saved)))
  (check 'history-keeps-recent (equal? (car history) (cadr saved))))

(let* ((run (exercise
              (lambda (state questions)
                (answers questions (lambda (id q)
                  (case (string->symbol (field state "phase"))
                    ((confirm) (if (and (= 1 (field state "pass")) (string=? id "(0)")) "rebake" "keep"))
                    ((revise) "replace")
                    (else (fixture-construct '(0 0) id q))))))
              passing (tiny-config (cons "max_calls" 6))))
       (events (cadr run)))
  (check 'history-change-invalidates-approval (= 2 (times-asked "(1)" events))))

;; Prefixes belong in the current AST once, not in all 95 character choices.
(let* ((text (make-string 100 #\x))
       (tree (vector 'program (list (vector 'spell 1 'string text))))
       (choices (ast-options tree '(0) '() '() 64 16 128))
       (compact (json-string (apply object (map (lambda (p) (cons (car p) (datum-string (cdr p)))) choices))))
       (old (json-string (apply object
              (map (lambda (p)
                     (cons (car p) (datum-string
                       (if (eq? 'append-char (cadr p))
                           (list 'spell 'string (string-append text (string (caddr p)))) (cdr p))))) choices)))))
  (check 'spelling-criteria-compact (< (string-length compact) (/ (string-length old) 2)))
  (progress "Spelling criteria JSON: " (string-length old) " -> " (string-length compact) " characters (100-character prefix)"))
