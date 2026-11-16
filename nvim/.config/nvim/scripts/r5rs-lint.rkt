#lang racket/base
;; Strict R5RS checker for Neovim (nvim-lint).
;; Reads Scheme source on stdin, expands it as an R5RS module WITHOUT running
;; it, and prints "line:col:severity:message" for:
;;   - read errors (unbalanced parens, bad tokens)
;;   - syntax errors and identifiers that are not in R5RS (or not defined)
;;   - class rule: `define` may only define functions
;; Usage: racket r5rs-lint.rkt <display-name> < file.scm

(define name (let ([args (current-command-line-arguments)])
               (if (> (vector-length args) 0) (vector-ref args 0) "stdin")))

(define (report line col sev msg)
  (printf "~a:~a:~a:~a\n" (or line 1) (or col 0) sev
          (regexp-replace* #rx"\n" msg " ")))

(define (report-exn e)
  (define locs (if (exn:srclocs? e) ((exn:srclocs-accessor e) e) '()))
  ;; first line only, minus the "file:line:col: " prefix Racket adds
  (define msg (regexp-replace #rx"^[^ ]*:[0-9]+:[0-9]+: "
                              (car (regexp-split #rx"\n  " (exn-message e))) ""))
  (if (null? locs)
      (report 1 0 "error" msg)
      (let ([l (car locs)])
        (report (srcloc-line l) (srcloc-column l) "error" msg))))

;; Class rule: (define name value) is only OK when value is a lambda.
(define (check-defines stx)
  (define e (syntax-e stx))
  (when (pair? e)
    (define items (syntax->list stx))
    (when items
      (when (and (>= (length items) 2)
                 (eq? (syntax-e (car items)) 'define)
                 (symbol? (syntax-e (cadr items))))
        (define val (and (= (length items) 3) (syntax-e (caddr items))))
        (unless (and (pair? val) (eq? (syntax-e (car val)) 'lambda))
          (report (syntax-line stx) (syntax-column stx) "warning"
                  (format "class rule: only functions may be defined; `~a` is a variable"
                          (syntax-e (cadr items))))))
      (for-each check-defines items))))

(define in (current-input-port))
(port-count-lines! in)

(with-handlers ([exn:fail? report-exn])
  (define forms
    ;; same reader settings as `#lang r5rs` / plt-r5rs
    (parameterize ([read-accept-reader #f] [read-accept-lang #f]
                   [read-case-sensitive #f] [read-accept-infix-dot #f]
                   [read-curly-brace-as-paren #f]
                   [read-square-bracket-as-paren #f])
      (let loop ()
        (define s (read-syntax name in))
        (if (eof-object? s) '() (cons s (loop))))))
  (for-each check-defines forms)
  (parameterize ([current-namespace (make-base-namespace)])
    ;; context-free module form, like a #lang reader produces
    (void (expand (datum->syntax #f (list* 'module 'r5rs-lint 'r5rs forms))))))
