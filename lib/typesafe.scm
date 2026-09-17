;; Credentials go to curl through stdin, never argv or an execution report.
(define transport-record (make-parameter (lambda (event) #f)))
(define (typesafe-oracle state questions)
  (let ((key (get-environment-variable "TYPESAFE_API_KEY"))
        (model (or (get-environment-variable "TYPESAFE_MODEL") "jev-latest"))
        (endpoint (or (get-environment-variable "TYPESAFE_URL") "https://api.typesafe.ai/v1/systemone")))
    (unless (and key (> (string-length key) 0)) (error "set TYPESAFE_API_KEY"))
    (when (or (string-index key #\newline) (string-index key #\return)) (error "invalid API key"))
    (call-with-scratch
      (lambda (directory)
        (let ((request-path (string-append directory "/request.json"))
              (response-path (string-append directory "/response.json")))
          (call-with-output-file request-path
            (lambda (p) (json-write (object (cons "model" model) (cons "state" state)
                                           (cons "questions" questions)) p)))
          (let retry ((attempt 1))
            ((transport-record) (list 'http-attempt
              (object (cons "attempt" attempt) (cons "endpoint" endpoint) (cons "model" model))))
            (let* ((started (current-milliseconds))
                   (result
                    (run-command
                      (list "curl" "--silent" "--show-error" "--connect-timeout" "10" "--max-time" "60"
                            "--config" "-" "--header" "Content-Type: application/json"
                            "--data-binary" (string-append "@" request-path)
                            "--output" response-path "--write-out" "%{http_code}" endpoint)
                      (string-append "header = " (json-string (string-append "Authorization: Bearer " key)) "\n")))
                   (status (or (string->number (car result)) 0))
                   (body (if (file-exists? response-path) (call-with-input-file response-path read-all) "")))
              ((transport-record) (list 'http-result
                (object (cons "status" status) (cons "curl_exit" (caddr result))
                        (cons "attempt" attempt) (cons "duration_ms" (- (current-milliseconds) started))
                        (cons "body" body) (cons "stderr" (cadr result)))))
              (unless (zero? (caddr result)) (error "HTTP transport failed" (caddr result) (cadr result)))
              (cond ((and (memv status '(429 500 502 503 504 529)) (< attempt 4))
                     ((transport-record) (list 'http-retry attempt (expt 2 (- attempt 1))))
                     (sleep (expt 2 (- attempt 1))) (retry (+ attempt 1)))
                    ((not (<= 200 status 299)) (error (string-append "TypeSafe HTTP " (number->string status) ": " body)))
                    (else (json-read body))))))))))
