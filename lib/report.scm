;; Stable decimal formatting with standard Scheme.
(define (fixed-decimal value places)
  (let* ((digits (number->string (exact (round (* value (expt 10 places))))))
         (padded (if (<= (string-length digits) places)
                     (string-append (make-string (+ 1 (- places (string-length digits))) #\0) digits)
                     digits))
         (split (- (string-length padded) places)))
    (string-append (substring padded 0 split) "." (substring padded split))))
(define (metering-text metrics)
  (string-append
    (number->string (field metrics "calls")) " calls, "
    (number->string (field metrics "reported_input_tokens")) " in / "
    (number->string (field metrics "reported_output_tokens")) " out tokens, estimated $"
    (fixed-decimal (field metrics "estimated_usd_for_reported_usage") 8) ", "
    (fixed-decimal (/ (field metrics "duration_ms") 1000.0) 3) "s"
    (if (field metrics "usage_complete") "" " [usage incomplete; cost covers reported tokens only]")))
