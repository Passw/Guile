(eval-when (compile) (set-current-module (resolve-module (quote (guile)))))
(if #f #f)

(let ((syntax? (module-ref (current-module) 'syntax?))
      (make-syntax (module-ref (current-module) 'make-syntax))
      (syntax-expression (module-ref (current-module) 'syntax-expression))
      (syntax-wrap (module-ref (current-module) 'syntax-wrap))
      (syntax-module (module-ref (current-module) 'syntax-module))
      (syntax-sourcev (module-ref (current-module) 'syntax-sourcev)))
  (letrec* ((make-void (lambda (src) (make-struct/simple (vector-ref %expanded-vtables 0) src)))
            (make-const (lambda (src exp) (make-struct/simple (vector-ref %expanded-vtables 1) src exp)))
            (make-primitive-ref (lambda (src name) (make-struct/simple (vector-ref %expanded-vtables 2) src name)))
            (make-lexical-ref
             (lambda (src name gensym) (make-struct/simple (vector-ref %expanded-vtables 3) src name gensym)))
            (make-lexical-set
             (lambda (src name gensym exp) (make-struct/simple (vector-ref %expanded-vtables 4) src name gensym exp)))
            (make-module-ref
             (lambda (src mod name public?) (make-struct/simple (vector-ref %expanded-vtables 5) src mod name public?)))
            (make-module-set
             (lambda (src mod name public? exp)
               (make-struct/simple (vector-ref %expanded-vtables 6) src mod name public? exp)))
            (make-toplevel-ref
             (lambda (src mod name) (make-struct/simple (vector-ref %expanded-vtables 7) src mod name)))
            (make-toplevel-set
             (lambda (src mod name exp) (make-struct/simple (vector-ref %expanded-vtables 8) src mod name exp)))
            (make-toplevel-define
             (lambda (src mod name exp) (make-struct/simple (vector-ref %expanded-vtables 9) src mod name exp)))
            (make-conditional
             (lambda (src test consequent alternate)
               (make-struct/simple (vector-ref %expanded-vtables 10) src test consequent alternate)))
            (make-call (lambda (src proc args) (make-struct/simple (vector-ref %expanded-vtables 11) src proc args)))
            (make-primcall
             (lambda (src name args) (make-struct/simple (vector-ref %expanded-vtables 12) src name args)))
            (make-seq (lambda (src head tail) (make-struct/simple (vector-ref %expanded-vtables 13) src head tail)))
            (make-lambda (lambda (src meta body) (make-struct/simple (vector-ref %expanded-vtables 14) src meta body)))
            (make-lambda-case
             (lambda (src req opt rest kw inits gensyms body alternate)
               (make-struct/simple (vector-ref %expanded-vtables 15) src req opt rest kw inits gensyms body alternate)))
            (make-let
             (lambda (src names gensyms vals body)
               (make-struct/simple (vector-ref %expanded-vtables 16) src names gensyms vals body)))
            (make-letrec
             (lambda (src in-order? names gensyms vals body)
               (make-struct/simple (vector-ref %expanded-vtables 17) src in-order? names gensyms vals body)))
            (lambda? (lambda (x) (and (struct? x) (eq? (struct-vtable x) (vector-ref %expanded-vtables 14)))))
            (lambda-src (lambda (x) (struct-ref x 0)))
            (lambda-meta (lambda (x) (struct-ref x 1)))
            (lambda-body (lambda (x) (struct-ref x 2)))
            (top-level-eval (lambda (x mod) (primitive-eval x)))
            (local-eval (lambda (x mod) (primitive-eval x)))
            (global-extend
             (lambda (type sym val) (module-define! (current-module) sym (make-syntax-transformer sym type val))))
            (sourcev-filename (lambda (s) (vector-ref s 0)))
            (sourcev-line (lambda (s) (vector-ref s 1)))
            (sourcev-column (lambda (s) (vector-ref s 2)))
            (sourcev->alist
             (lambda (sourcev)
               (letrec* ((maybe-acons (lambda (k v tail) (if v (acons k v tail) tail))))
                 (and sourcev
                      (maybe-acons
                       'filename
                       (sourcev-filename sourcev)
                       (list (cons 'line (sourcev-line sourcev)) (cons 'column (sourcev-column sourcev))))))))
            (maybe-name-value
             (lambda (name val)
               (if (lambda? val)
                   (let ((meta (lambda-meta val)))
                     (if (assq 'name meta) val (make-lambda (lambda-src val) (acons 'name name meta) (lambda-body val))))
                   val)))
            (build-void make-void)
            (build-call make-call)
            (build-conditional make-conditional)
            (build-lexical-reference make-lexical-ref)
            (build-lexical-assignment
             (lambda (src name var exp) (make-lexical-set src name var (maybe-name-value name exp))))
            (analyze-variable
             (lambda (mod var modref-cont bare-cont)
               (let* ((v mod)
                      (fk (lambda ()
                            (let ((fk (lambda ()
                                        (let ((fk (lambda ()
                                                    (let ((fk (lambda () (error "value failed to match" v))))
                                                      (if (pair? v)
                                                          (let ((vx (car v)) (vy (cdr v)))
                                                            (if (eq? vx 'primitive)
                                                                (syntax-violation
                                                                 #f
                                                                 "primitive not in operator position"
                                                                 var)
                                                                (fk)))
                                                          (fk))))))
                                          (if (pair? v)
                                              (let ((vx (car v)) (vy (cdr v)))
                                                (let ((tk (lambda ()
                                                            (let ((mod vy))
                                                              (if (equal? mod (module-name (current-module)))
                                                                  (bare-cont mod var)
                                                                  (modref-cont mod var #f))))))
                                                  (if (eq? vx 'private)
                                                      (tk)
                                                      (let ((tk (lambda () (tk)))) (if (eq? vx 'hygiene) (tk) (fk))))))
                                              (fk))))))
                              (if (pair? v)
                                  (let ((vx (car v)) (vy (cdr v)))
                                    (if (eq? vx 'public) (let ((mod vy)) (modref-cont mod var #t)) (fk)))
                                  (fk))))))
                 (if (eq? v #f) (bare-cont #f var) (fk)))))
            (build-global-reference
             (lambda (src var mod)
               (analyze-variable
                mod
                var
                (lambda (mod var public?) (make-module-ref src mod var public?))
                (lambda (mod var) (make-toplevel-ref src mod var)))))
            (build-global-assignment
             (lambda (src var exp mod)
               (let ((exp (maybe-name-value var exp)))
                 (analyze-variable
                  mod
                  var
                  (lambda (mod var public?) (make-module-set src mod var public? exp))
                  (lambda (mod var) (make-toplevel-set src mod var exp))))))
            (build-global-definition
             (lambda (src mod var exp) (make-toplevel-define src (and mod (cdr mod)) var (maybe-name-value var exp))))
            (build-simple-lambda
             (lambda (src req rest vars meta exp)
               (make-lambda src meta (make-lambda-case src req #f rest #f '() vars exp #f))))
            (build-case-lambda make-lambda)
            (build-lambda-case make-lambda-case)
            (build-primcall make-primcall)
            (build-primref make-primitive-ref)
            (build-data make-const)
            (build-sequence
             (lambda (src exps)
               (let* ((v exps)
                      (fk (lambda ()
                            (let ((fk (lambda () (error "value failed to match" v))))
                              (if (pair? v)
                                  (let ((vx (car v)) (vy (cdr v)))
                                    (let* ((head vx) (tail vy)) (make-seq src head (build-sequence #f tail))))
                                  (fk))))))
                 (if (pair? v) (let ((vx (car v)) (vy (cdr v))) (let ((tail vx)) (if (null? vy) tail (fk)))) (fk)))))
            (build-let
             (lambda (src ids vars val-exps body-exp)
               (let* ((v (map maybe-name-value ids val-exps))
                      (fk (lambda ()
                            (let* ((fk (lambda () (error "value failed to match" v))) (val-exps v))
                              (make-let src ids vars val-exps body-exp)))))
                 (if (null? v) body-exp (fk)))))
            (build-named-let
             (lambda (src ids vars val-exps body-exp)
               (let* ((v vars) (fk (lambda () (error "value failed to match" v))))
                 (if (pair? v)
                     (let ((vx (car v)) (vy (cdr v)))
                       (let* ((f vx) (vars vy) (v ids) (fk (lambda () (error "value failed to match" v))))
                         (if (pair? v)
                             (let ((vx (car v)) (vy (cdr v)))
                               (let* ((f-name vx) (ids vy) (proc (build-simple-lambda src ids #f vars '() body-exp)))
                                 (make-letrec
                                  src
                                  #f
                                  (list f-name)
                                  (list f)
                                  (list (maybe-name-value f-name proc))
                                  (build-call
                                   src
                                   (build-lexical-reference src f-name f)
                                   (map maybe-name-value ids val-exps)))))
                             (fk))))
                     (fk)))))
            (build-letrec
             (lambda (src in-order? ids vars val-exps body-exp)
               (let* ((v (map maybe-name-value ids val-exps))
                      (fk (lambda ()
                            (let* ((fk (lambda () (error "value failed to match" v))) (val-exps v))
                              (make-letrec src in-order? ids vars val-exps body-exp)))))
                 (if (null? v) body-exp (fk)))))
            (gen-lexical (lambda (id) (module-gensym (symbol->string id))))
            (no-source #f)
            (datum-sourcev
             (lambda (datum)
               (let ((props (source-properties datum)))
                 (and (pair? props) (vector (assq-ref props 'filename) (assq-ref props 'line) (assq-ref props 'column))))))
            (source-annotation (lambda (x) (if (syntax? x) (syntax-sourcev x) (datum-sourcev x))))
            (binding-type (lambda (x) (car x)))
            (binding-value (lambda (x) (cdr x)))
            (null-env '())
            (extend-env
             (lambda (labels bindings r)
               (let* ((v labels)
                      (fk (lambda ()
                            (let ((fk (lambda () (error "value failed to match" v))))
                              (if (pair? v)
                                  (let ((vx (car v)) (vy (cdr v)))
                                    (let* ((label vx)
                                           (labels vy)
                                           (v bindings)
                                           (fk (lambda () (error "value failed to match" v))))
                                      (if (pair? v)
                                          (let ((vx (car v)) (vy (cdr v)))
                                            (let* ((binding vx) (bindings vy))
                                              (extend-env labels bindings (acons label binding r))))
                                          (fk))))
                                  (fk))))))
                 (if (null? v) r (fk)))))
            (extend-var-env
             (lambda (labels vars r)
               (let* ((v labels)
                      (fk (lambda ()
                            (let ((fk (lambda () (error "value failed to match" v))))
                              (if (pair? v)
                                  (let ((vx (car v)) (vy (cdr v)))
                                    (let* ((label vx)
                                           (labels vy)
                                           (v vars)
                                           (fk (lambda () (error "value failed to match" v))))
                                      (if (pair? v)
                                          (let ((vx (car v)) (vy (cdr v)))
                                            (let* ((var vx) (vars vy))
                                              (extend-var-env labels vars (acons label (cons 'lexical var) r))))
                                          (fk))))
                                  (fk))))))
                 (if (null? v) r (fk)))))
            (macros-only-env
             (lambda (r)
               (let* ((v r)
                      (fk (lambda ()
                            (let ((fk (lambda () (error "value failed to match" v))))
                              (if (pair? v)
                                  (let ((vx (car v)) (vy (cdr v)))
                                    (let* ((a vx)
                                           (r vy)
                                           (v a)
                                           (fk (lambda ()
                                                 (let ((fk (lambda () (error "value failed to match" v))))
                                                   (macros-only-env r)))))
                                      (if (pair? v)
                                          (let ((vx (car v)) (vy (cdr v)))
                                            (let ((k vx))
                                              (if (pair? vy)
                                                  (let ((vx (car vy)) (vy (cdr vy)))
                                                    (let ((tk (lambda () (cons a (macros-only-env r)))))
                                                      (if (eq? vx 'macro)
                                                          (tk)
                                                          (let ((tk (lambda () (tk))))
                                                            (if (eq? vx 'syntax-parameter)
                                                                (tk)
                                                                (let ((tk (lambda () (tk))))
                                                                  (if (eq? vx 'ellipsis) (tk) (fk))))))))
                                                  (fk))))
                                          (fk))))
                                  (fk))))))
                 (if (null? v) '() (fk)))))
            (nonsymbol-id? (lambda (x) (and (syntax? x) (symbol? (syntax-expression x)))))
            (id? (lambda (x) (if (symbol? x) #t (and (syntax? x) (symbol? (syntax-expression x))))))
            (id-sym-name (lambda (x) (if (syntax? x) (syntax-expression x) x)))
            (id-sym-name&marks
             (lambda (x w)
               (if (syntax? x)
                   (values (syntax-expression x) (join-marks (wrap-marks w) (wrap-marks (syntax-wrap x))))
                   (values x (wrap-marks w)))))
            (make-wrap (lambda (marks subst) (cons marks subst)))
            (wrap-marks (lambda (wrap) (car wrap)))
            (wrap-subst (lambda (wrap) (cdr wrap)))
            (gen-unique
             (lambda* (#:optional (module (current-module)))
               (if module
                   (vector (module-name module) (module-generate-unique-id! module))
                   (vector '(guile) (gensym "id")))))
            (gen-label (lambda () (gen-unique)))
            (gen-labels
             (lambda (ls)
               (let* ((v ls)
                      (fk (lambda ()
                            (let ((fk (lambda () (error "value failed to match" v))))
                              (if (pair? v)
                                  (let ((vx (car v)) (vy (cdr v))) (let ((ls vy)) (cons (gen-label) (gen-labels ls))))
                                  (fk))))))
                 (if (null? v) '() (fk)))))
            (make-ribcage (lambda (symnames marks labels) (vector 'ribcage symnames marks labels)))
            (ribcage-symnames (lambda (ribcage) (vector-ref ribcage 1)))
            (ribcage-marks (lambda (ribcage) (vector-ref ribcage 2)))
            (ribcage-labels (lambda (ribcage) (vector-ref ribcage 3)))
            (set-ribcage-symnames! (lambda (ribcage x) (vector-set! ribcage 1 x)))
            (set-ribcage-marks! (lambda (ribcage x) (vector-set! ribcage 2 x)))
            (set-ribcage-labels! (lambda (ribcage x) (vector-set! ribcage 3 x)))
            (empty-wrap '(()))
            (top-wrap '((top)))
            (the-anti-mark #f)
            (anti-mark (lambda (w) (make-wrap (cons the-anti-mark (wrap-marks w)) (cons 'shift (wrap-subst w)))))
            (new-mark (lambda () (gen-unique)))
            (make-empty-ribcage (lambda () (make-ribcage '() '() '())))
            (extend-ribcage!
             (lambda (ribcage id label)
               (set-ribcage-symnames! ribcage (cons (syntax-expression id) (ribcage-symnames ribcage)))
               (set-ribcage-marks! ribcage (cons (wrap-marks (syntax-wrap id)) (ribcage-marks ribcage)))
               (set-ribcage-labels! ribcage (cons label (ribcage-labels ribcage)))))
            (make-binding-wrap
             (lambda (ids labels w)
               (let* ((v ids)
                      (fk (lambda ()
                            (let ((fk (lambda () (error "value failed to match" v))))
                              (if (pair? v)
                                  (let ((vx (car v)) (vy (cdr v)))
                                    (make-wrap
                                     (wrap-marks w)
                                     (cons (let* ((labelvec (list->vector labels))
                                                  (n (vector-length labelvec))
                                                  (symnamevec (make-vector n))
                                                  (marksvec (make-vector n)))
                                             (let f ((ids ids) (i 0))
                                               (let* ((v ids)
                                                      (fk (lambda ()
                                                            (let ((fk (lambda () (error "value failed to match" v))))
                                                              (if (pair? v)
                                                                  (let ((vx (car v)) (vy (cdr v)))
                                                                    (let* ((id vx) (ids vy))
                                                                      (call-with-values
                                                                       (lambda () (id-sym-name&marks id w))
                                                                       (lambda (symname marks)
                                                                         (vector-set! symnamevec i symname)
                                                                         (vector-set! marksvec i marks)
                                                                         (f ids (#{1+}# i))))))
                                                                  (fk))))))
                                                 (if (null? v) (make-ribcage symnamevec marksvec labelvec) (fk)))))
                                           (wrap-subst w))))
                                  (fk))))))
                 (if (null? v) w (fk)))))
            (smart-append (lambda (m1 m2) (if (null? m2) m1 (append m1 m2))))
            (join-wraps
             (lambda (w1 w2)
               (let ((m1 (wrap-marks w1)) (s1 (wrap-subst w1)))
                 (if (null? m1)
                     (if (null? s1) w2 (make-wrap (wrap-marks w2) (smart-append s1 (wrap-subst w2))))
                     (make-wrap (smart-append m1 (wrap-marks w2)) (smart-append s1 (wrap-subst w2)))))))
            (join-marks (lambda (m1 m2) (smart-append m1 m2)))
            (same-marks?
             (lambda (x y)
               (or (eq? x y) (and (not (null? x)) (not (null? y)) (eq? (car x) (car y)) (same-marks? (cdr x) (cdr y))))))
            (id-var-name
             (lambda (id w mod)
               (letrec* ((search
                          (lambda (sym subst marks)
                            (let* ((v subst)
                                   (fk (lambda ()
                                         (let ((fk (lambda ()
                                                     (let ((fk (lambda () (error "value failed to match" v))))
                                                       (if (pair? v)
                                                           (let ((vx (car v)) (vy (cdr v)))
                                                             (if (and (vector? vx)
                                                                      (eq? (vector-length vx)
                                                                           (length '('ribcage rsymnames rmarks rlabels))))
                                                                 (if (eq? (vector-ref vx 0) 'ribcage)
                                                                     (let* ((rsymnames (vector-ref vx (#{1+}# 0)))
                                                                            (rmarks (vector-ref vx (#{1+}# (#{1+}# 0))))
                                                                            (rlabels
                                                                             (vector-ref
                                                                              vx
                                                                              (#{1+}# (#{1+}# (#{1+}# 0)))))
                                                                            (subst vy))
                                                                       (letrec* ((search-list-rib
                                                                                  (lambda ()
                                                                                    (let lp ((rsymnames rsymnames)
                                                                                             (rmarks rmarks)
                                                                                             (rlabels rlabels))
                                                                                      (let* ((v rsymnames)
                                                                                             (fk (lambda ()
                                                                                                   (let ((fk (lambda ()
                                                                                                               (error "value failed to match"
                                                                                                                      v))))
                                                                                                     (if (pair? v)
                                                                                                         (let ((vx (car v))
                                                                                                               (vy (cdr v)))
                                                                                                           (let* ((rsym vx)
                                                                                                                  (rsymnames
                                                                                                                   vy)
                                                                                                                  (v rmarks)
                                                                                                                  (fk (lambda ()
                                                                                                                        (error "value failed to match"
                                                                                                                               v))))
                                                                                                             (if (pair? v)
                                                                                                                 (let ((vx (car v))
                                                                                                                       (vy (cdr v)))
                                                                                                                   (let* ((rmarks1
                                                                                                                           vx)
                                                                                                                          (rmarks
                                                                                                                           vy)
                                                                                                                          (v rlabels)
                                                                                                                          (fk (lambda ()
                                                                                                                                (error "value failed to match"
                                                                                                                                       v))))
                                                                                                                     (if (pair? v)
                                                                                                                         (let ((vx (car v))
                                                                                                                               (vy (cdr v)))
                                                                                                                           (let* ((label vx)
                                                                                                                                  (rlabels
                                                                                                                                   vy))
                                                                                                                             (if (and (eq? sym
                                                                                                                                           rsym)
                                                                                                                                      (same-marks?
                                                                                                                                       marks
                                                                                                                                       rmarks1))
                                                                                                                                 (let* ((v label)
                                                                                                                                        (fk (lambda ()
                                                                                                                                              (let ((fk (lambda ()
                                                                                                                                                          (error "value failed to match"
                                                                                                                                                                 v))))
                                                                                                                                                label))))
                                                                                                                                   (if (pair? v)
                                                                                                                                       (let ((vx (car v))
                                                                                                                                             (vy (cdr v)))
                                                                                                                                         (let* ((mod* vx)
                                                                                                                                                (label vy))
                                                                                                                                           (if (equal?
                                                                                                                                                mod*
                                                                                                                                                mod)
                                                                                                                                               label
                                                                                                                                               (lp rsymnames
                                                                                                                                                   rmarks
                                                                                                                                                   rlabels))))
                                                                                                                                       (fk)))
                                                                                                                                 (lp rsymnames
                                                                                                                                     rmarks
                                                                                                                                     rlabels))))
                                                                                                                         (fk))))
                                                                                                                 (fk))))
                                                                                                         (fk))))))
                                                                                        (if (null? v)
                                                                                            (search sym subst marks)
                                                                                            (fk))))))
                                                                                 (search-vector-rib
                                                                                  (lambda ()
                                                                                    (let ((n (vector-length rsymnames)))
                                                                                      (let lp ((i 0))
                                                                                        (cond
                                                                                          ((= i n)
                                                                                           (search sym subst marks))
                                                                                          ((and (eq? (vector-ref
                                                                                                      rsymnames
                                                                                                      i)
                                                                                                     sym)
                                                                                                (same-marks?
                                                                                                 marks
                                                                                                 (vector-ref rmarks i)))
                                                                                           (let* ((v (vector-ref
                                                                                                      rlabels
                                                                                                      i))
                                                                                                  (fk (lambda ()
                                                                                                        (let* ((fk (lambda ()
                                                                                                                     (error "value failed to match"
                                                                                                                            v)))
                                                                                                               (label v))
                                                                                                          label))))
                                                                                             (if (pair? v)
                                                                                                 (let ((vx (car v))
                                                                                                       (vy (cdr v)))
                                                                                                   (let* ((mod* vx)
                                                                                                          (label vy))
                                                                                                     (if (equal?
                                                                                                          mod*
                                                                                                          mod)
                                                                                                         label
                                                                                                         (lp (#{1+}# i)))))
                                                                                                 (fk))))
                                                                                          (else (lp (#{1+}# i)))))))))
                                                                         (if (vector? rsymnames)
                                                                             (search-vector-rib)
                                                                             (search-list-rib))))
                                                                     (fk))
                                                                 (fk)))
                                                           (fk))))))
                                           (if (pair? v)
                                               (let ((vx (car v)) (vy (cdr v)))
                                                 (if (eq? vx 'shift)
                                                     (let* ((subst vy)
                                                            (v marks)
                                                            (fk (lambda () (error "value failed to match" v))))
                                                       (if (pair? v)
                                                           (let ((vx (car v)) (vy (cdr v)))
                                                             (let ((marks vy)) (search sym subst marks)))
                                                           (fk)))
                                                     (fk)))
                                               (fk))))))
                              (if (null? v) #f (fk))))))
                 (cond
                   ((symbol? id) (or (search id (wrap-subst w) (wrap-marks w)) id))
                   ((syntax? id)
                    (let ((id (syntax-expression id)) (w1 (syntax-wrap id)) (mod (or (syntax-module id) mod)))
                      (let ((marks (join-marks (wrap-marks w) (wrap-marks w1))))
                        (or (search id (wrap-subst w) marks) (search id (wrap-subst w1) marks) id))))
                   (else (syntax-violation 'id-var-name "invalid id" id))))))
            (locally-bound-identifiers
             (lambda (w mod)
               (let scan ((subst (wrap-subst w)) (results '()))
                 (let* ((v subst)
                        (fk (lambda ()
                              (let ((fk (lambda ()
                                          (let ((fk (lambda () (error "value failed to match" v))))
                                            (if (pair? v)
                                                (let ((vx (car v)) (vy (cdr v)))
                                                  (if (and (vector? vx)
                                                           (eq? (vector-length vx)
                                                                (length '('ribcage symnames marks labels))))
                                                      (if (eq? (vector-ref vx 0) 'ribcage)
                                                          (let* ((symnames (vector-ref vx (#{1+}# 0)))
                                                                 (marks (vector-ref vx (#{1+}# (#{1+}# 0))))
                                                                 (labels (vector-ref vx (#{1+}# (#{1+}# (#{1+}# 0)))))
                                                                 (subst* vy))
                                                            (letrec* ((scan-list-rib
                                                                       (lambda ()
                                                                         (let lp ((symnames symnames)
                                                                                  (marks marks)
                                                                                  (results results))
                                                                           (let* ((v symnames)
                                                                                  (fk (lambda ()
                                                                                        (let ((fk (lambda ()
                                                                                                    (error "value failed to match"
                                                                                                           v))))
                                                                                          (if (pair? v)
                                                                                              (let ((vx (car v))
                                                                                                    (vy (cdr v)))
                                                                                                (let* ((sym vx)
                                                                                                       (symnames vy)
                                                                                                       (v marks)
                                                                                                       (fk (lambda ()
                                                                                                             (error "value failed to match"
                                                                                                                    v))))
                                                                                                  (if (pair? v)
                                                                                                      (let ((vx (car v))
                                                                                                            (vy (cdr v)))
                                                                                                        (let* ((m vx)
                                                                                                               (marks vy))
                                                                                                          (lp symnames
                                                                                                              marks
                                                                                                              (cons (wrap sym
                                                                                                                          (anti-mark
                                                                                                                           (make-wrap
                                                                                                                            m
                                                                                                                            subst))
                                                                                                                          mod)
                                                                                                                    results))))
                                                                                                      (fk))))
                                                                                              (fk))))))
                                                                             (if (null? v) (scan subst* results) (fk))))))
                                                                      (scan-vector-rib
                                                                       (lambda ()
                                                                         (let ((n (vector-length symnames)))
                                                                           (let lp ((i 0) (results results))
                                                                             (if (= i n)
                                                                                 (scan subst* results)
                                                                                 (lp (#{1+}# i)
                                                                                     (let ((sym (vector-ref symnames i))
                                                                                           (m (vector-ref marks i)))
                                                                                       (cons (wrap sym
                                                                                                   (anti-mark
                                                                                                    (make-wrap m subst))
                                                                                                   mod)
                                                                                             results)))))))))
                                                              (if (vector? symnames) (scan-vector-rib) (scan-list-rib))))
                                                          (fk))
                                                      (fk)))
                                                (fk))))))
                                (if (pair? v)
                                    (let ((vx (car v)) (vy (cdr v)))
                                      (if (eq? vx 'shift) (let ((subst vy)) (scan subst results)) (fk)))
                                    (fk))))))
                   (if (null? v) results (fk))))))
            (resolve-identifier
             (lambda (id w r mod resolve-syntax-parameters?)
               (letrec* ((resolve-global
                          (lambda (var mod)
                            (if (and (not mod) (current-module))
                                (warn "module system is booted, we should have a module" var))
                            (let ((v (and (not (equal? mod '(primitive)))
                                          (module-variable (if mod (resolve-module (cdr mod)) (current-module)) var))))
                              (if (and v (variable-bound? v) (macro? (variable-ref v)))
                                  (let* ((m (variable-ref v)) (type (macro-type m)) (trans (macro-binding m)))
                                    (if (eq? type 'syntax-parameter)
                                        (if resolve-syntax-parameters?
                                            (let ((lexical (assq-ref r v)))
                                              (values 'macro (if lexical (binding-value lexical) trans) mod))
                                            (values type v mod))
                                        (values type trans mod)))
                                  (values 'global var mod)))))
                         (resolve-lexical
                          (lambda (label mod)
                            (let ((b (assq-ref r label)))
                              (if b
                                  (let ((type (binding-type b)) (value (binding-value b)))
                                    (if (eq? type 'syntax-parameter)
                                        (if resolve-syntax-parameters?
                                            (values 'macro value mod)
                                            (values type label mod))
                                        (values type value mod)))
                                  (values 'displaced-lexical #f #f))))))
                 (let ((n (id-var-name id w mod)))
                   (cond
                     ((syntax? n)
                      (if (not (eq? n id))
                          (resolve-identifier n w r mod resolve-syntax-parameters?)
                          (resolve-identifier
                           (syntax-expression n)
                           (syntax-wrap n)
                           r
                           (or (syntax-module n) mod)
                           resolve-syntax-parameters?)))
                     ((symbol? n) (resolve-global n (or (and (syntax? id) (syntax-module id)) mod)))
                     (else (resolve-lexical n (or (and (syntax? id) (syntax-module id)) mod))))))))
            (transformer-environment
             (make-fluid (lambda (k) (error "called outside the dynamic extent of a syntax transformer"))))
            (with-transformer-environment (lambda (k) ((fluid-ref transformer-environment) k)))
            (free-id=?
             (lambda (i j)
               (let* ((mi (and (syntax? i) (syntax-module i)))
                      (mj (and (syntax? j) (syntax-module j)))
                      (ni (id-var-name i empty-wrap mi))
                      (nj (id-var-name j empty-wrap mj)))
                 (letrec* ((id-module-binding
                            (lambda (id mod)
                              (module-variable (if mod (resolve-module (cdr mod)) (current-module)) (id-sym-name id)))))
                   (cond
                     ((syntax? ni) (free-id=? ni j))
                     ((syntax? nj) (free-id=? i nj))
                     ((symbol? ni)
                      (and (eq? nj (id-sym-name j))
                           (let ((bi (id-module-binding i mi)) (bj (id-module-binding j mj)))
                             (and (eq? bi bj) (or bi (eq? ni nj))))))
                     (else (equal? ni nj)))))))
            (bound-id=?
             (lambda (i j)
               (if (and (syntax? i) (syntax? j))
                   (and (eq? (syntax-expression i) (syntax-expression j))
                        (same-marks? (wrap-marks (syntax-wrap i)) (wrap-marks (syntax-wrap j))))
                   (eq? i j))))
            (valid-bound-ids?
             (lambda (ids)
               (and (let all-ids? ((ids ids))
                      (let* ((v ids)
                             (fk (lambda ()
                                   (let ((fk (lambda () (error "value failed to match" v))))
                                     (if (pair? v)
                                         (let ((vx (car v)) (vy (cdr v)))
                                           (let* ((id vx) (ids vy)) (and (id? id) (all-ids? ids))))
                                         (fk))))))
                        (if (null? v) #t (fk))))
                    (distinct-bound-ids? ids))))
            (distinct-bound-ids?
             (lambda (ids)
               (let distinct? ((ids ids))
                 (let* ((v ids)
                        (fk (lambda ()
                              (let ((fk (lambda () (error "value failed to match" v))))
                                (if (pair? v)
                                    (let ((vx (car v)) (vy (cdr v)))
                                      (let* ((id vx) (ids vy)) (and (not (bound-id-member? id ids)) (distinct? ids))))
                                    (fk))))))
                   (if (null? v) #t (fk))))))
            (bound-id-member?
             (lambda (x ids)
               (let* ((v ids)
                      (fk (lambda ()
                            (let ((fk (lambda () (error "value failed to match" v))))
                              (if (pair? v)
                                  (let ((vx (car v)) (vy (cdr v)))
                                    (let* ((id vx) (ids vy)) (or (bound-id=? x id) (bound-id-member? x ids))))
                                  (fk))))))
                 (if (null? v) #f (fk)))))
            (wrap (lambda (x w defmod) (source-wrap x w #f defmod)))
            (wrap-syntax
             (lambda (x w defmod)
               (make-syntax (syntax-expression x) w (or (syntax-module x) defmod) (syntax-sourcev x))))
            (source-wrap
             (lambda (x w s defmod)
               (cond
                 ((and (null? (wrap-marks w)) (null? (wrap-subst w)) (not defmod) (not s)) x)
                 ((syntax? x) (wrap-syntax x (join-wraps w (syntax-wrap x)) defmod))
                 ((null? x) x)
                 (else (make-syntax x w defmod s)))))
            (expand-sequence
             (lambda (body r w s mod)
               (build-sequence
                s
                (let lp ((body body))
                  (let* ((v body)
                         (fk (lambda ()
                               (let ((fk (lambda () (error "value failed to match" v))))
                                 (if (pair? v)
                                     (let ((vx (car v)) (vy (cdr v)))
                                       (let* ((head vx) (tail vy) (expr (expand head r w mod))) (cons expr (lp tail))))
                                     (fk))))))
                    (if (null? v) '() (fk)))))))
            (expand-top-sequence
             (lambda (body r w s m esew mod)
               (let* ((r (cons '("placeholder" placeholder) r))
                      (ribcage (make-empty-ribcage))
                      (w (make-wrap (wrap-marks w) (cons ribcage (wrap-subst w)))))
                 (letrec* ((record-definition!
                            (lambda (id var)
                              (let ((mod (cons 'hygiene (module-name (current-module)))))
                                (extend-ribcage! ribcage id (cons (or (syntax-module id) mod) (wrap var top-wrap mod))))))
                           (macro-introduced-identifier?
                            (lambda (id) (not (equal? (wrap-marks (syntax-wrap id)) '(top)))))
                           (ensure-fresh-name
                            (lambda (var)
                              (letrec* ((ribcage-has-var?
                                         (lambda (var)
                                           (let lp ((labels (ribcage-labels ribcage)))
                                             (let* ((v labels)
                                                    (fk (lambda ()
                                                          (let ((fk (lambda () (error "value failed to match" v))))
                                                            (if (pair? v)
                                                                (let ((vx (car v)) (vy-1 (cdr v)))
                                                                  (if (pair? vx)
                                                                      (let ((vx (car vx)) (vy (cdr vx)))
                                                                        (let* ((wrapped vy) (labels vy-1))
                                                                          (or (eq? (syntax-expression wrapped) var)
                                                                              (lp labels))))
                                                                      (fk)))
                                                                (fk))))))
                                               (if (null? v) #f (fk)))))))
                                (let lp ((unique var) (n 1))
                                  (if (ribcage-has-var? unique)
                                      (let ((tail (string->symbol (number->string n))))
                                        (lp (symbol-append var '- tail) (#{1+}# n)))
                                      unique)))))
                           (fresh-derived-name
                            (lambda (id orig-form)
                              (ensure-fresh-name
                               (symbol-append
                                (syntax-expression id)
                                '-
                                (string->symbol
                                 (number->string (hash (syntax->datum orig-form) most-positive-fixnum) 16))))))
                           (parse (lambda (body r w s m esew mod)
                                    (let lp ((body body))
                                      (let* ((v body)
                                             (fk (lambda ()
                                                   (let ((fk (lambda () (error "value failed to match" v))))
                                                     (if (pair? v)
                                                         (let ((vx (car v)) (vy (cdr v)))
                                                           (let* ((head vx)
                                                                  (tail vy)
                                                                  (thunks (parse1 head r w s m esew mod)))
                                                             (append thunks (lp tail))))
                                                         (fk))))))
                                        (if (null? v) '() (fk))))))
                           (parse1
                            (lambda (x r w s m esew mod)
                              (letrec* ((current-module-for-expansion
                                         (lambda (mod)
                                           (let* ((v mod)
                                                  (fk (lambda ()
                                                        (let ((fk (lambda () (error "value failed to match" v)))) mod))))
                                             (if (pair? v)
                                                 (let ((vx (car v)) (vy (cdr v)))
                                                   (if (eq? vx 'hygiene)
                                                       (cons 'hygiene (module-name (current-module)))
                                                       (fk)))
                                                 (fk))))))
                                (call-with-values
                                 (lambda ()
                                   (let ((mod (current-module-for-expansion mod)))
                                     (syntax-type x r w (source-annotation x) ribcage mod #f)))
                                 (lambda (type value form e w s mod)
                                   (let ((key type))
                                     (cond
                                       ((memv key '(define-form))
                                        (let* ((id (wrap value w mod))
                                               (var (if (macro-introduced-identifier? id)
                                                        (fresh-derived-name id x)
                                                        (syntax-expression id))))
                                          (record-definition! id var)
                                          (list (if (eq? m 'c&e)
                                                    (let ((x (build-global-definition s mod var (expand e r w mod))))
                                                      (top-level-eval x mod)
                                                      (lambda () x))
                                                    (call-with-values
                                                     (lambda () (resolve-identifier id empty-wrap r mod #t))
                                                     (lambda (type* value* mod*)
                                                       (if (eq? type* 'macro)
                                                           (top-level-eval
                                                            (build-global-definition s mod var (build-void s))
                                                            mod))
                                                       (lambda ()
                                                         (build-global-definition s mod var (expand e r w mod)))))))))
                                       ((memv key '(define-syntax-form define-syntax-parameter-form))
                                        (let* ((id (wrap value w mod))
                                               (var (if (macro-introduced-identifier? id)
                                                        (fresh-derived-name id x)
                                                        (syntax-expression id))))
                                          (record-definition! id var)
                                          (let ((key m))
                                            (cond
                                              ((memv key '(c))
                                               (cond
                                                 ((memq 'compile esew)
                                                  (let ((e (expand-install-global mod var type (expand e r w mod))))
                                                    (top-level-eval e mod)
                                                    (if (memq 'load esew) (list (lambda () e)) '())))
                                                 ((memq 'load esew)
                                                  (list (lambda ()
                                                          (expand-install-global mod var type (expand e r w mod)))))
                                                 (else '())))
                                              ((memv key '(c&e))
                                               (let ((e (expand-install-global mod var type (expand e r w mod))))
                                                 (top-level-eval e mod)
                                                 (list (lambda () e))))
                                              (else (if (memq 'eval esew)
                                                        (top-level-eval
                                                         (expand-install-global mod var type (expand e r w mod))
                                                         mod))
                                                    '())))))
                                       ((memv key '(begin-form))
                                        (let* ((tmp-1 e) (tmp ($sc-dispatch tmp-1 '(_ . each-any))))
                                          (if tmp
                                              (apply (lambda (e1) (parse e1 r w s m esew mod)) tmp)
                                              (syntax-violation
                                               #f
                                               "source expression failed to match any pattern"
                                               tmp-1))))
                                       ((memv key '(local-syntax-form))
                                        (expand-local-syntax
                                         value
                                         e
                                         r
                                         w
                                         s
                                         mod
                                         (lambda (forms r w s mod) (parse forms r w s m esew mod))))
                                       ((memv key '(eval-when-form))
                                        (let* ((tmp-1 e) (tmp ($sc-dispatch tmp-1 '(_ each-any any . each-any))))
                                          (if tmp
                                              (apply (lambda (x e1 e2)
                                                       (let ((when-list (parse-when-list e x)) (body (cons e1 e2)))
                                                         (letrec* ((recurse
                                                                    (lambda (m esew) (parse body r w s m esew mod))))
                                                           (cond
                                                             ((eq? m 'e)
                                                              (if (memq 'eval when-list)
                                                                  (recurse
                                                                   (if (memq 'expand when-list) 'c&e 'e)
                                                                   '(eval))
                                                                  (begin
                                                                    (if (memq 'expand when-list)
                                                                        (top-level-eval
                                                                         (expand-top-sequence body r w s 'e '(eval) mod)
                                                                         mod))
                                                                    '())))
                                                             ((memq 'load when-list)
                                                              (cond
                                                                ((or (memq 'compile when-list)
                                                                     (memq 'expand when-list)
                                                                     (and (eq? m 'c&e) (memq 'eval when-list)))
                                                                 (recurse 'c&e '(compile load)))
                                                                ((memq m '(c c&e)) (recurse 'c '(load)))
                                                                (else '())))
                                                             ((or (memq 'compile when-list)
                                                                  (memq 'expand when-list)
                                                                  (and (eq? m 'c&e) (memq 'eval when-list)))
                                                              (top-level-eval
                                                               (expand-top-sequence body r w s 'e '(eval) mod)
                                                               mod)
                                                              '())
                                                             (else '())))))
                                                     tmp)
                                              (syntax-violation
                                               #f
                                               "source expression failed to match any pattern"
                                               tmp-1))))
                                       (else (list (if (eq? m 'c&e)
                                                       (let ((x (expand-expr type value form e r w s mod)))
                                                         (top-level-eval x mod)
                                                         (lambda () x))
                                                       (lambda () (expand-expr type value form e r w s mod)))))))))))))
                   (let* ((v (let lp ((thunks (parse body r w s m esew mod)))
                               (let* ((v thunks)
                                      (fk (lambda ()
                                            (let ((fk (lambda () (error "value failed to match" v))))
                                              (if (pair? v)
                                                  (let ((vx (car v)) (vy (cdr v)))
                                                    (let* ((thunk vx) (thunks vy)) (cons (thunk) (lp thunks))))
                                                  (fk))))))
                                 (if (null? v) '() (fk)))))
                          (fk (lambda ()
                                (let* ((fk (lambda () (error "value failed to match" v))) (exps v))
                                  (build-sequence s exps)))))
                     (if (null? v) (build-void s) (fk)))))))
            (expand-install-global
             (lambda (mod name type e)
               (build-global-definition
                no-source
                mod
                name
                (build-primcall
                 no-source
                 'make-syntax-transformer
                 (list (build-data no-source name)
                       (build-data no-source (if (eq? type 'define-syntax-parameter-form) 'syntax-parameter 'macro))
                       e)))))
            (parse-when-list
             (lambda (e when-list)
               (let ((result (strip when-list)))
                 (let lp ((l result))
                   (let* ((v l)
                          (fk (lambda ()
                                (let ((fk (lambda () (error "value failed to match" v))))
                                  (if (pair? v)
                                      (let ((vx (car v)) (vy (cdr v)))
                                        (let* ((x vx)
                                               (l vy)
                                               (v x)
                                               (fk (lambda ()
                                                     (let ((fk (lambda () (error "value failed to match" v))))
                                                       (syntax-violation 'eval-when "invalid situation" e x))))
                                               (tk (lambda () (lp l))))
                                          (if (eq? v 'compile)
                                              (tk)
                                              (let ((tk (lambda () (tk))))
                                                (if (eq? v 'load)
                                                    (tk)
                                                    (let ((tk (lambda () (tk))))
                                                      (if (eq? v 'eval)
                                                          (tk)
                                                          (let ((tk (lambda () (tk)))) (if (eq? v 'expand) (tk) (fk))))))))))
                                      (fk))))))
                     (if (null? v) result (fk)))))))
            (syntax-type
             (lambda (e r w s rib mod for-car?)
               (cond
                 ((symbol? e)
                  (call-with-values
                   (lambda () (resolve-identifier e w r mod #t))
                   (lambda (type value mod*)
                     (let ((key type))
                       (cond
                         ((memv key '(macro))
                          (if for-car?
                              (values type value e e w s mod)
                              (syntax-type (expand-macro value e r w s rib mod) r empty-wrap s rib mod #f)))
                         ((memv key '(global)) (values type value e value w s mod*))
                         (else (values type value e e w s mod)))))))
                 ((pair? e)
                  (let ((first (car e)))
                    (call-with-values
                     (lambda () (syntax-type first r w s rib mod #t))
                     (lambda (ftype fval fform fe fw fs fmod)
                       (let ((key ftype))
                         (cond
                           ((memv key '(lexical)) (values 'lexical-call fval e e w s mod))
                           ((memv key '(global))
                            (if (equal? fmod '(primitive))
                                (values 'primitive-call fval e e w s mod)
                                (values 'global-call (make-syntax fval w fmod fs) e e w s mod)))
                           ((memv key '(macro))
                            (syntax-type (expand-macro fval e r w s rib mod) r empty-wrap s rib mod for-car?))
                           ((memv key '(module-ref))
                            (call-with-values
                             (lambda () (fval e r w mod))
                             (lambda (e r w s mod) (syntax-type e r w s rib mod for-car?))))
                           ((memv key '(core)) (values 'core-form fval e e w s mod))
                           ((memv key '(local-syntax)) (values 'local-syntax-form fval e e w s mod))
                           ((memv key '(begin)) (values 'begin-form #f e e w s mod))
                           ((memv key '(eval-when)) (values 'eval-when-form #f e e w s mod))
                           ((memv key '(define))
                            (let* ((tmp e) (tmp-1 ($sc-dispatch tmp '(_ any any))))
                              (if (and tmp-1 (apply (lambda (name val) (id? name)) tmp-1))
                                  (apply (lambda (name val) (values 'define-form name e val w s mod)) tmp-1)
                                  (let ((tmp-1 ($sc-dispatch tmp '(_ (any . any) any . each-any))))
                                    (if (and tmp-1
                                             (apply (lambda (name args e1 e2)
                                                      (and (id? name) (valid-bound-ids? (lambda-var-list args))))
                                                    tmp-1))
                                        (apply (lambda (name args e1 e2)
                                                 (values
                                                  'define-form
                                                  (wrap name w mod)
                                                  (wrap e w mod)
                                                  (source-wrap
                                                   (cons (make-syntax 'lambda '((top)) '(hygiene guile))
                                                         (wrap (cons args (cons e1 e2)) w mod))
                                                   empty-wrap
                                                   s
                                                   #f)
                                                  empty-wrap
                                                  s
                                                  mod))
                                               tmp-1)
                                        (let ((tmp-1 ($sc-dispatch tmp '(_ any))))
                                          (if (and tmp-1 (apply (lambda (name) (id? name)) tmp-1))
                                              (apply (lambda (name)
                                                       (values
                                                        'define-form
                                                        (wrap name w mod)
                                                        (wrap e w mod)
                                                        (list (make-syntax 'if '((top)) '(hygiene guile)) #f #f)
                                                        empty-wrap
                                                        s
                                                        mod))
                                                     tmp-1)
                                              (syntax-violation #f "source expression failed to match any pattern" tmp))))))))
                           ((memv key '(define-syntax))
                            (let* ((tmp-1 e) (tmp ($sc-dispatch tmp-1 '(_ any any))))
                              (if (and tmp (apply (lambda (name val) (id? name)) tmp))
                                  (apply (lambda (name val) (values 'define-syntax-form name e val w s mod)) tmp)
                                  (syntax-violation #f "source expression failed to match any pattern" tmp-1))))
                           ((memv key '(define-syntax-parameter))
                            (let* ((tmp-1 e) (tmp ($sc-dispatch tmp-1 '(_ any any))))
                              (if (and tmp (apply (lambda (name val) (id? name)) tmp))
                                  (apply (lambda (name val) (values 'define-syntax-parameter-form name e val w s mod))
                                         tmp)
                                  (syntax-violation #f "source expression failed to match any pattern" tmp-1))))
                           (else (values 'call #f e e w s mod))))))))
                 ((syntax? e)
                  (syntax-type
                   (syntax-expression e)
                   r
                   (join-wraps w (syntax-wrap e))
                   (or (source-annotation e) s)
                   rib
                   (or (syntax-module e) mod)
                   for-car?))
                 ((self-evaluating? e) (values 'constant #f e e w s mod))
                 (else (values 'other #f e e w s mod)))))
            (expand
             (lambda (e r w mod)
               (call-with-values
                (lambda () (syntax-type e r w (source-annotation e) #f mod #f))
                (lambda (type value form e w s mod) (expand-expr type value form e r w s mod)))))
            (expand-expr
             (lambda (type value form e r w s mod)
               (let ((key type))
                 (cond
                   ((memv key '(lexical)) (build-lexical-reference s e value))
                   ((memv key '(core core-form)) (value e r w s mod))
                   ((memv key '(module-ref))
                    (call-with-values (lambda () (value e r w mod)) (lambda (e r w s mod) (expand e r w mod))))
                   ((memv key '(lexical-call))
                    (expand-call
                     (let ((id (car e)))
                       (build-lexical-reference (source-annotation id) (if (syntax? id) (syntax->datum id) id) value))
                     e
                     r
                     w
                     s
                     mod))
                   ((memv key '(global-call))
                    (expand-call
                     (build-global-reference
                      (or (source-annotation (car e)) s)
                      (if (syntax? value) (syntax-expression value) value)
                      (or (and (syntax? value) (syntax-module value)) mod))
                     e
                     r
                     w
                     s
                     mod))
                   ((memv key '(primitive-call))
                    (let* ((tmp-1 e) (tmp ($sc-dispatch tmp-1 '(_ . each-any))))
                      (if tmp
                          (apply (lambda (e) (build-primcall s value (map (lambda (e) (expand e r w mod)) e))) tmp)
                          (syntax-violation #f "source expression failed to match any pattern" tmp-1))))
                   ((memv key '(constant)) (build-data s (strip e)))
                   ((memv key '(global)) (build-global-reference s value mod))
                   ((memv key '(call)) (expand-call (expand (car e) r w mod) e r w s mod))
                   ((memv key '(begin-form))
                    (let* ((tmp e) (tmp-1 ($sc-dispatch tmp '(_ any . each-any))))
                      (if tmp-1
                          (apply (lambda (e1 e2) (expand-sequence (cons e1 e2) r w s mod)) tmp-1)
                          (let ((tmp-1 ($sc-dispatch tmp '(_))))
                            (if tmp-1
                                (apply (lambda ()
                                         (syntax-violation #f "sequence of zero expressions" (source-wrap e w s mod)))
                                       tmp-1)
                                (syntax-violation #f "source expression failed to match any pattern" tmp))))))
                   ((memv key '(local-syntax-form)) (expand-local-syntax value e r w s mod expand-sequence))
                   ((memv key '(eval-when-form))
                    (let* ((tmp-1 e) (tmp ($sc-dispatch tmp-1 '(_ each-any any . each-any))))
                      (if tmp
                          (apply (lambda (x e1 e2)
                                   (let ((when-list (parse-when-list e x)))
                                     (if (memq 'eval when-list) (expand-sequence (cons e1 e2) r w s mod) (expand-void))))
                                 tmp)
                          (syntax-violation #f "source expression failed to match any pattern" tmp-1))))
                   ((memv key '(define-form define-syntax-form define-syntax-parameter-form))
                    (syntax-violation
                     #f
                     "definition in expression context, where definitions are not allowed,"
                     (source-wrap form w s mod)))
                   ((memv key '(syntax))
                    (syntax-violation #f "reference to pattern variable outside syntax form" (source-wrap e w s mod)))
                   ((memv key '(displaced-lexical))
                    (syntax-violation #f "reference to identifier outside its scope" (source-wrap e w s mod)))
                   (else (syntax-violation #f "unexpected syntax" (source-wrap e w s mod)))))))
            (expand-call
             (lambda (x e r w s mod)
               (let* ((tmp-1 e) (tmp ($sc-dispatch tmp-1 '(any . each-any))))
                 (if tmp
                     (apply (lambda (e0 e1) (build-call s x (map (lambda (e) (expand e r w mod)) e1))) tmp)
                     (syntax-violation #f "source expression failed to match any pattern" tmp-1)))))
            (expand-macro
             (lambda (p e r w s rib mod)
               (letrec* ((decorate-source (lambda (x) (source-wrap x empty-wrap s #f)))
                         (map* (lambda (f x)
                                 (let* ((v x)
                                        (fk (lambda ()
                                              (let ((fk (lambda ()
                                                          (let* ((fk (lambda () (error "value failed to match" v)))
                                                                 (x v))
                                                            (f x)))))
                                                (if (pair? v)
                                                    (let ((vx (car v)) (vy (cdr v)))
                                                      (let* ((x vx) (x* vy)) (cons (f x) (map* f x*))))
                                                    (fk))))))
                                   (if (null? v) '() (fk)))))
                         (rebuild-macro-output
                          (lambda (x m)
                            (cond
                              ((pair? x) (decorate-source (map* (lambda (x) (rebuild-macro-output x m)) x)))
                              ((syntax? x)
                               (let ((w (syntax-wrap x)))
                                 (let ((ms (wrap-marks w)) (ss (wrap-subst w)))
                                   (if (and (pair? ms) (eq? (car ms) the-anti-mark))
                                       (wrap-syntax x (make-wrap (cdr ms) (if rib (cons rib (cdr ss)) (cdr ss))) mod)
                                       (wrap-syntax
                                        x
                                        (make-wrap (cons m ms) (if rib (cons rib (cons 'shift ss)) (cons 'shift ss)))
                                        mod)))))
                              ((vector? x)
                               (let* ((n (vector-length x)) (v (make-vector n)))
                                 (let loop ((i 0))
                                   (if (= i n)
                                       (begin (if #f #f) v)
                                       (begin
                                         (vector-set! v i (rebuild-macro-output (vector-ref x i) m))
                                         (loop (#{1+}# i)))))
                                 (decorate-source v)))
                              ((symbol? x)
                               (syntax-violation
                                #f
                                "encountered raw symbol in macro output"
                                (source-wrap e w (wrap-subst w) mod)
                                x))
                              (else (decorate-source x))))))
                 (let* ((t-680b775fb37a463-c45 transformer-environment)
                        (t-680b775fb37a463-c46 (lambda (k) (k e r w s rib mod))))
                   (with-fluid*
                    t-680b775fb37a463-c45
                    t-680b775fb37a463-c46
                    (lambda () (rebuild-macro-output (p (source-wrap e (anti-mark w) s mod)) (new-mark))))))))
            (expand-body
             (lambda (body outer-form r w mod)
               (let* ((r (cons '("placeholder" placeholder) r))
                      (ribcage (make-empty-ribcage))
                      (w (make-wrap (wrap-marks w) (cons ribcage (wrap-subst w)))))
                 (let parse ((body (map (lambda (x) (cons r (wrap x w mod))) body))
                             (ids '())
                             (labels '())
                             (var-ids '())
                             (vars '())
                             (vals '())
                             (bindings '())
                             (expand-tail-expr #f))
                   (cond
                     ((null? body)
                      (if (not expand-tail-expr)
                          (begin
                            (if (null? ids) (syntax-violation #f "empty body" outer-form))
                            (syntax-violation #f "body should end with an expression" outer-form)))
                      (if (not (valid-bound-ids? ids))
                          (syntax-violation #f "invalid or duplicate identifier in definition" outer-form))
                      (set-cdr! r (extend-env labels bindings (cdr r)))
                      (let ((src (source-annotation outer-form)))
                        (let lp ((var-ids var-ids) (vars vars) (vals vals) (tail (expand-tail-expr)))
                          (cond
                            ((null? var-ids) tail)
                            ((not (car var-ids))
                             (lp (cdr var-ids) (cdr vars) (cdr vals) (make-seq src ((car vals)) tail)))
                            (else (let ((var-ids (map (lambda (id) (if id (syntax->datum id) '_)) (reverse var-ids)))
                                        (vars (map (lambda (var) (or var (gen-lexical '_))) (reverse vars)))
                                        (vals (map (lambda (expand-expr id)
                                                     (if id (expand-expr) (make-seq src (expand-expr) (build-void src))))
                                                   (reverse vals)
                                                   (reverse var-ids))))
                                    (build-letrec src #t var-ids vars vals tail)))))))
                     (expand-tail-expr
                      (parse body ids labels (cons #f var-ids) (cons #f vars) (cons expand-tail-expr vals) bindings #f))
                     (else (let ((e (cdar body)) (er (caar body)) (body (cdr body)))
                             (call-with-values
                              (lambda () (syntax-type e er empty-wrap (source-annotation e) ribcage mod #f))
                              (lambda (type value form e w s mod)
                                (let ((key type))
                                  (cond
                                    ((memv key '(define-form))
                                     (let ((id (wrap value w mod)) (label (gen-label)))
                                       (let ((var (gen-var id)))
                                         (extend-ribcage! ribcage id label)
                                         (parse body
                                                (cons id ids)
                                                (cons label labels)
                                                (cons id var-ids)
                                                (cons var vars)
                                                (cons (let ((wrapped (source-wrap e w s mod)))
                                                        (lambda () (expand wrapped er empty-wrap mod)))
                                                      vals)
                                                (cons (cons 'lexical var) bindings)
                                                #f))))
                                    ((memv key '(define-syntax-form))
                                     (let ((id (wrap value w mod)) (label (gen-label)) (trans-r (macros-only-env er)))
                                       (extend-ribcage! ribcage id label)
                                       (set-cdr!
                                        r
                                        (extend-env
                                         (list label)
                                         (list (cons 'macro (eval-local-transformer (expand e trans-r w mod) mod)))
                                         (cdr r)))
                                       (parse body (cons id ids) labels var-ids vars vals bindings #f)))
                                    ((memv key '(define-syntax-parameter-form))
                                     (let ((id (wrap value w mod)) (label (gen-label)) (trans-r (macros-only-env er)))
                                       (extend-ribcage! ribcage id label)
                                       (set-cdr!
                                        r
                                        (extend-env
                                         (list label)
                                         (list (cons 'syntax-parameter
                                                     (eval-local-transformer (expand e trans-r w mod) mod)))
                                         (cdr r)))
                                       (parse body (cons id ids) labels var-ids vars vals bindings #f)))
                                    ((memv key '(begin-form))
                                     (let* ((tmp-1 e) (tmp ($sc-dispatch tmp-1 '(_ . each-any))))
                                       (if tmp
                                           (apply (lambda (e1)
                                                    (parse (let f ((forms e1))
                                                             (if (null? forms)
                                                                 body
                                                                 (cons (cons er (wrap (car forms) w mod))
                                                                       (f (cdr forms)))))
                                                           ids
                                                           labels
                                                           var-ids
                                                           vars
                                                           vals
                                                           bindings
                                                           #f))
                                                  tmp)
                                           (syntax-violation #f "source expression failed to match any pattern" tmp-1))))
                                    ((memv key '(local-syntax-form))
                                     (expand-local-syntax
                                      value
                                      e
                                      er
                                      w
                                      s
                                      mod
                                      (lambda (forms er w s mod)
                                        (parse (let f ((forms forms))
                                                 (if (null? forms)
                                                     body
                                                     (cons (cons er (wrap (car forms) w mod)) (f (cdr forms)))))
                                               ids
                                               labels
                                               var-ids
                                               vars
                                               vals
                                               bindings
                                               #f))))
                                    (else (let ((wrapped (source-wrap e w s mod)))
                                            (parse body
                                                   ids
                                                   labels
                                                   var-ids
                                                   vars
                                                   vals
                                                   bindings
                                                   (lambda () (expand wrapped er empty-wrap mod))))))))))))))))
            (expand-local-syntax
             (lambda (rec? e r w s mod k)
               (let* ((tmp e) (tmp ($sc-dispatch tmp '(_ #(each (any any)) any . each-any))))
                 (if tmp
                     (apply (lambda (id val e1 e2)
                              (let ((ids id))
                                (if (not (valid-bound-ids? ids))
                                    (syntax-violation #f "duplicate bound keyword" e)
                                    (let* ((labels (gen-labels ids)) (new-w (make-binding-wrap ids labels w)))
                                      (k (cons e1 e2)
                                         (extend-env
                                          labels
                                          (let ((w (if rec? new-w w)) (trans-r (macros-only-env r)))
                                            (map (lambda (x)
                                                   (cons 'macro (eval-local-transformer (expand x trans-r w mod) mod)))
                                                 val))
                                          r)
                                         new-w
                                         s
                                         mod)))))
                            tmp)
                     (syntax-violation #f "bad local syntax definition" (source-wrap e w s mod))))))
            (eval-local-transformer
             (lambda (expanded mod)
               (let ((p (local-eval expanded mod)))
                 (if (not (procedure? p)) (syntax-violation #f "nonprocedure transformer" p))
                 p)))
            (expand-void (lambda () (build-void no-source)))
            (ellipsis?
             (lambda (e r mod)
               (and (nonsymbol-id? e)
                    (call-with-values
                     (lambda ()
                       (resolve-identifier
                        (make-syntax '#{ $sc-ellipsis }# (syntax-wrap e) (or (syntax-module e) mod) #f)
                        empty-wrap
                        r
                        mod
                        #f))
                     (lambda (type value mod)
                       (if (eq? type 'ellipsis)
                           (bound-id=? e value)
                           (free-id=? e (make-syntax '... '((top)) '(hygiene guile)))))))))
            (lambda-formals
             (lambda (orig-args)
               (letrec* ((req (lambda (args rreq)
                                (let* ((tmp args) (tmp-1 ($sc-dispatch tmp '())))
                                  (if tmp-1
                                      (apply (lambda () (check (reverse rreq) #f)) tmp-1)
                                      (let ((tmp-1 ($sc-dispatch tmp '(any . any))))
                                        (if (and tmp-1 (apply (lambda (a b) (id? a)) tmp-1))
                                            (apply (lambda (a b) (req b (cons a rreq))) tmp-1)
                                            (let ((tmp-1 (list tmp)))
                                              (if (and tmp-1 (apply (lambda (r) (id? r)) tmp-1))
                                                  (apply (lambda (r) (check (reverse rreq) r)) tmp-1)
                                                  (let ((else tmp))
                                                    (syntax-violation 'lambda "invalid argument list" orig-args args))))))))))
                         (check (lambda (req rest)
                                  (if (distinct-bound-ids? (if rest (cons rest req) req))
                                      (values req #f rest #f)
                                      (syntax-violation 'lambda "duplicate identifier in argument list" orig-args)))))
                 (req orig-args '()))))
            (expand-simple-lambda
             (lambda (e r w s mod req rest meta body)
               (let* ((ids (if rest (append req (list rest)) req)) (vars (map gen-var ids)) (labels (gen-labels ids)))
                 (build-simple-lambda
                  s
                  (map syntax->datum req)
                  (and rest (syntax->datum rest))
                  vars
                  meta
                  (expand-body
                   body
                   (source-wrap e w s mod)
                   (extend-var-env labels vars r)
                   (make-binding-wrap ids labels w)
                   mod)))))
            (lambda*-formals
             (lambda (orig-args)
               (letrec* ((req (lambda (args rreq)
                                (let* ((tmp args) (tmp-1 ($sc-dispatch tmp '())))
                                  (if tmp-1
                                      (apply (lambda () (check (reverse rreq) '() #f '())) tmp-1)
                                      (let ((tmp-1 ($sc-dispatch tmp '(any . any))))
                                        (if (and tmp-1 (apply (lambda (a b) (id? a)) tmp-1))
                                            (apply (lambda (a b) (req b (cons a rreq))) tmp-1)
                                            (let ((tmp-1 ($sc-dispatch tmp '(any . any))))
                                              (if (and tmp-1
                                                       (apply (lambda (a b) (eq? (syntax->datum a) #:optional)) tmp-1))
                                                  (apply (lambda (a b) (opt b (reverse rreq) '())) tmp-1)
                                                  (let ((tmp-1 ($sc-dispatch tmp '(any . any))))
                                                    (if (and tmp-1
                                                             (apply (lambda (a b) (eq? (syntax->datum a) #:key)) tmp-1))
                                                        (apply (lambda (a b) (key b (reverse rreq) '() '())) tmp-1)
                                                        (let ((tmp-1 ($sc-dispatch tmp '(any any))))
                                                          (if (and tmp-1
                                                                   (apply (lambda (a b) (eq? (syntax->datum a) #:rest))
                                                                          tmp-1))
                                                              (apply (lambda (a b) (rest b (reverse rreq) '() '()))
                                                                     tmp-1)
                                                              (let ((tmp-1 (list tmp)))
                                                                (if (and tmp-1 (apply (lambda (r) (id? r)) tmp-1))
                                                                    (apply (lambda (r) (rest r (reverse rreq) '() '()))
                                                                           tmp-1)
                                                                    (let ((else tmp))
                                                                      (syntax-violation
                                                                       'lambda*
                                                                       "invalid argument list"
                                                                       orig-args
                                                                       args))))))))))))))))
                         (opt (lambda (args req ropt)
                                (let* ((tmp args) (tmp-1 ($sc-dispatch tmp '())))
                                  (if tmp-1
                                      (apply (lambda () (check req (reverse ropt) #f '())) tmp-1)
                                      (let ((tmp-1 ($sc-dispatch tmp '(any . any))))
                                        (if (and tmp-1 (apply (lambda (a b) (id? a)) tmp-1))
                                            (apply (lambda (a b) (opt b req (cons (cons a '(#f)) ropt))) tmp-1)
                                            (let ((tmp-1 ($sc-dispatch tmp '((any any) . any))))
                                              (if (and tmp-1 (apply (lambda (a init b) (id? a)) tmp-1))
                                                  (apply (lambda (a init b) (opt b req (cons (list a init) ropt)))
                                                         tmp-1)
                                                  (let ((tmp-1 ($sc-dispatch tmp '(any . any))))
                                                    (if (and tmp-1
                                                             (apply (lambda (a b) (eq? (syntax->datum a) #:key)) tmp-1))
                                                        (apply (lambda (a b) (key b req (reverse ropt) '())) tmp-1)
                                                        (let ((tmp-1 ($sc-dispatch tmp '(any any))))
                                                          (if (and tmp-1
                                                                   (apply (lambda (a b) (eq? (syntax->datum a) #:rest))
                                                                          tmp-1))
                                                              (apply (lambda (a b) (rest b req (reverse ropt) '()))
                                                                     tmp-1)
                                                              (let ((tmp-1 (list tmp)))
                                                                (if (and tmp-1 (apply (lambda (r) (id? r)) tmp-1))
                                                                    (apply (lambda (r) (rest r req (reverse ropt) '()))
                                                                           tmp-1)
                                                                    (let ((else tmp))
                                                                      (syntax-violation
                                                                       'lambda*
                                                                       "invalid optional argument list"
                                                                       orig-args
                                                                       args))))))))))))))))
                         (key (lambda (args req opt rkey)
                                (let* ((tmp args) (tmp-1 ($sc-dispatch tmp '())))
                                  (if tmp-1
                                      (apply (lambda () (check req opt #f (cons #f (reverse rkey)))) tmp-1)
                                      (let ((tmp-1 ($sc-dispatch tmp '(any . any))))
                                        (if (and tmp-1 (apply (lambda (a b) (id? a)) tmp-1))
                                            (apply (lambda (a b)
                                                     (let* ((tmp (symbol->keyword (syntax->datum a))) (k tmp))
                                                       (key b req opt (cons (cons k (cons a '(#f))) rkey))))
                                                   tmp-1)
                                            (let ((tmp-1 ($sc-dispatch tmp '((any any) . any))))
                                              (if (and tmp-1 (apply (lambda (a init b) (id? a)) tmp-1))
                                                  (apply (lambda (a init b)
                                                           (let* ((tmp (symbol->keyword (syntax->datum a))) (k tmp))
                                                             (key b req opt (cons (list k a init) rkey))))
                                                         tmp-1)
                                                  (let ((tmp-1 ($sc-dispatch tmp '((any any any) . any))))
                                                    (if (and tmp-1
                                                             (apply (lambda (a init k b)
                                                                      (and (id? a) (keyword? (syntax->datum k))))
                                                                    tmp-1))
                                                        (apply (lambda (a init k b)
                                                                 (key b req opt (cons (list k a init) rkey)))
                                                               tmp-1)
                                                        (let ((tmp-1 ($sc-dispatch tmp '(any))))
                                                          (if (and tmp-1
                                                                   (apply (lambda (aok)
                                                                            (eq? (syntax->datum aok) #:allow-other-keys))
                                                                          tmp-1))
                                                              (apply (lambda (aok)
                                                                       (check req opt #f (cons #t (reverse rkey))))
                                                                     tmp-1)
                                                              (let ((tmp-1 ($sc-dispatch tmp '(any any any))))
                                                                (if (and tmp-1
                                                                         (apply (lambda (aok a b)
                                                                                  (and (eq? (syntax->datum aok)
                                                                                            #:allow-other-keys)
                                                                                       (eq? (syntax->datum a) #:rest)))
                                                                                tmp-1))
                                                                    (apply (lambda (aok a b)
                                                                             (rest b req opt (cons #t (reverse rkey))))
                                                                           tmp-1)
                                                                    (let ((tmp-1 ($sc-dispatch tmp '(any . any))))
                                                                      (if (and tmp-1
                                                                               (apply (lambda (aok r)
                                                                                        (and (eq? (syntax->datum aok)
                                                                                                  #:allow-other-keys)
                                                                                             (id? r)))
                                                                                      tmp-1))
                                                                          (apply (lambda (aok r)
                                                                                   (rest r
                                                                                         req
                                                                                         opt
                                                                                         (cons #t (reverse rkey))))
                                                                                 tmp-1)
                                                                          (let ((tmp-1 ($sc-dispatch tmp '(any any))))
                                                                            (if (and tmp-1
                                                                                     (apply (lambda (a b)
                                                                                              (eq? (syntax->datum a)
                                                                                                   #:rest))
                                                                                            tmp-1))
                                                                                (apply (lambda (a b)
                                                                                         (rest b
                                                                                               req
                                                                                               opt
                                                                                               (cons #f (reverse rkey))))
                                                                                       tmp-1)
                                                                                (let ((tmp-1 (list tmp)))
                                                                                  (if (and tmp-1
                                                                                           (apply (lambda (r) (id? r))
                                                                                                  tmp-1))
                                                                                      (apply (lambda (r)
                                                                                               (rest r
                                                                                                     req
                                                                                                     opt
                                                                                                     (cons #f
                                                                                                           (reverse
                                                                                                            rkey))))
                                                                                             tmp-1)
                                                                                      (let ((else tmp))
                                                                                        (syntax-violation
                                                                                         'lambda*
                                                                                         "invalid keyword argument list"
                                                                                         orig-args
                                                                                         args))))))))))))))))))))))
                         (rest (lambda (args req opt kw)
                                 (let* ((tmp-1 args) (tmp (list tmp-1)))
                                   (if (and tmp (apply (lambda (r) (id? r)) tmp))
                                       (apply (lambda (r) (check req opt r kw)) tmp)
                                       (let ((else tmp-1))
                                         (syntax-violation 'lambda* "invalid rest argument" orig-args args))))))
                         (check (lambda (req opt rest kw)
                                  (if (distinct-bound-ids?
                                       (append
                                        req
                                        (map car opt)
                                        (if rest (list rest) '())
                                        (if (pair? kw) (map cadr (cdr kw)) '())))
                                      (values req opt rest kw)
                                      (syntax-violation 'lambda* "duplicate identifier in argument list" orig-args)))))
                 (req orig-args '()))))
            (expand-lambda-case
             (lambda (e r w s mod get-formals clauses)
               (letrec* ((parse-req
                          (lambda (req opt rest kw body)
                            (let ((vars (map gen-var req)) (labels (gen-labels req)))
                              (let ((r* (extend-var-env labels vars r)) (w* (make-binding-wrap req labels w)))
                                (parse-opt (map syntax->datum req) opt rest kw body (reverse vars) r* w* '() '())))))
                         (parse-opt
                          (lambda (req opt rest kw body vars r* w* out inits)
                            (cond
                              ((pair? opt)
                               (let* ((tmp-1 (car opt)) (tmp ($sc-dispatch tmp-1 '(any any))))
                                 (if tmp
                                     (apply (lambda (id i)
                                              (let* ((v (gen-var id))
                                                     (l (gen-labels (list v)))
                                                     (r** (extend-var-env l (list v) r*))
                                                     (w** (make-binding-wrap (list id) l w*)))
                                                (parse-opt
                                                 req
                                                 (cdr opt)
                                                 rest
                                                 kw
                                                 body
                                                 (cons v vars)
                                                 r**
                                                 w**
                                                 (cons (syntax->datum id) out)
                                                 (cons (expand i r* w* mod) inits))))
                                            tmp)
                                     (syntax-violation #f "source expression failed to match any pattern" tmp-1))))
                              (rest (let* ((v (gen-var rest))
                                           (l (gen-labels (list v)))
                                           (r* (extend-var-env l (list v) r*))
                                           (w* (make-binding-wrap (list rest) l w*)))
                                      (parse-kw
                                       req
                                       (and (pair? out) (reverse out))
                                       (syntax->datum rest)
                                       (if (pair? kw) (cdr kw) kw)
                                       body
                                       (cons v vars)
                                       r*
                                       w*
                                       (and (pair? kw) (car kw))
                                       '()
                                       inits)))
                              (else (parse-kw
                                     req
                                     (and (pair? out) (reverse out))
                                     #f
                                     (if (pair? kw) (cdr kw) kw)
                                     body
                                     vars
                                     r*
                                     w*
                                     (and (pair? kw) (car kw))
                                     '()
                                     inits)))))
                         (parse-kw
                          (lambda (req opt rest kw body vars r* w* aok out inits)
                            (if (pair? kw)
                                (let* ((tmp-1 (car kw)) (tmp ($sc-dispatch tmp-1 '(any any any))))
                                  (if tmp
                                      (apply (lambda (k id i)
                                               (let* ((v (gen-var id))
                                                      (l (gen-labels (list v)))
                                                      (r** (extend-var-env l (list v) r*))
                                                      (w** (make-binding-wrap (list id) l w*)))
                                                 (parse-kw
                                                  req
                                                  opt
                                                  rest
                                                  (cdr kw)
                                                  body
                                                  (cons v vars)
                                                  r**
                                                  w**
                                                  aok
                                                  (cons (list (syntax->datum k) (syntax->datum id) v) out)
                                                  (cons (expand i r* w* mod) inits))))
                                             tmp)
                                      (syntax-violation #f "source expression failed to match any pattern" tmp-1)))
                                (parse-body
                                 req
                                 opt
                                 rest
                                 (and (or aok (pair? out)) (cons aok (reverse out)))
                                 body
                                 (reverse vars)
                                 r*
                                 w*
                                 (reverse inits)
                                 '()))))
                         (parse-body
                          (lambda (req opt rest kw body vars r* w* inits meta)
                            (let* ((tmp body) (tmp-1 ($sc-dispatch tmp '(any any . each-any))))
                              (if (and tmp-1
                                       (apply (lambda (docstring e1 e2) (string? (syntax->datum docstring))) tmp-1))
                                  (apply (lambda (docstring e1 e2)
                                           (parse-body
                                            req
                                            opt
                                            rest
                                            kw
                                            (cons e1 e2)
                                            vars
                                            r*
                                            w*
                                            inits
                                            (append meta (list (cons 'documentation (syntax->datum docstring))))))
                                         tmp-1)
                                  (let ((tmp-1 ($sc-dispatch tmp '(#(vector #(each (any . any))) any . each-any))))
                                    (if tmp-1
                                        (apply (lambda (k v e1 e2)
                                                 (parse-body
                                                  req
                                                  opt
                                                  rest
                                                  kw
                                                  (cons e1 e2)
                                                  vars
                                                  r*
                                                  w*
                                                  inits
                                                  (append meta (syntax->datum (map cons k v)))))
                                               tmp-1)
                                        (let ((tmp-1 ($sc-dispatch tmp '(any . each-any))))
                                          (if tmp-1
                                              (apply (lambda (e1 e2)
                                                       (values
                                                        meta
                                                        req
                                                        opt
                                                        rest
                                                        kw
                                                        inits
                                                        vars
                                                        (expand-body (cons e1 e2) (source-wrap e w s mod) r* w* mod)))
                                                     tmp-1)
                                              (syntax-violation #f "source expression failed to match any pattern" tmp))))))))))
                 (let* ((tmp clauses) (tmp-1 ($sc-dispatch tmp '())))
                   (if tmp-1
                       (apply (lambda () (values '() #f)) tmp-1)
                       (let ((tmp-1 ($sc-dispatch tmp '((any any . each-any) . #(each (any any . each-any))))))
                         (if tmp-1
                             (apply (lambda (args e1 e2 args* e1* e2*)
                                      (call-with-values
                                       (lambda () (get-formals args))
                                       (lambda (req opt rest kw)
                                         (call-with-values
                                          (lambda () (parse-req req opt rest kw (cons e1 e2)))
                                          (lambda (meta req opt rest kw inits vars body)
                                            (call-with-values
                                             (lambda ()
                                               (expand-lambda-case
                                                e
                                                r
                                                w
                                                s
                                                mod
                                                get-formals
                                                (map (lambda (tmp-680b775fb37a463-ece
                                                              tmp-680b775fb37a463-ecd
                                                              tmp-680b775fb37a463-ecc)
                                                       (cons tmp-680b775fb37a463-ecc
                                                             (cons tmp-680b775fb37a463-ecd tmp-680b775fb37a463-ece)))
                                                     e2*
                                                     e1*
                                                     args*)))
                                             (lambda (meta* else*)
                                               (values
                                                (append meta meta*)
                                                (build-lambda-case s req opt rest kw inits vars body else*)))))))))
                                    tmp-1)
                             (syntax-violation #f "source expression failed to match any pattern" tmp))))))))
            (strip (lambda (x)
                     (letrec* ((annotate
                                (lambda (proc datum)
                                  (let ((s (proc x)))
                                    (if (and s (supports-source-properties? datum))
                                        (set-source-properties! datum (sourcev->alist s)))
                                    datum))))
                       (cond
                         ((syntax? x) (annotate syntax-sourcev (strip (syntax-expression x))))
                         ((pair? x) (cons (strip (car x)) (strip (cdr x))))
                         ((vector? x) (list->vector (strip (vector->list x))))
                         (else x)))))
            (gen-var (lambda (id) (let ((id (if (syntax? id) (syntax-expression id) id))) (gen-lexical id))))
            (lambda-var-list
             (lambda (vars)
               (let lvl ((vars vars) (ls '()) (w empty-wrap))
                 (cond
                   ((pair? vars) (lvl (cdr vars) (cons (wrap (car vars) w #f) ls) w))
                   ((id? vars) (cons (wrap vars w #f) ls))
                   ((null? vars) ls)
                   ((syntax? vars) (lvl (syntax-expression vars) ls (join-wraps w (syntax-wrap vars))))
                   (else (cons vars ls))))))
            (expand-syntax-parameterize
             (lambda (e r w s mod)
               (let* ((tmp e) (tmp ($sc-dispatch tmp '(_ #(each (any any)) any . each-any))))
                 (if (and tmp (apply (lambda (var val e1 e2) (valid-bound-ids? var)) tmp))
                     (apply (lambda (var val e1 e2)
                              (let ((names (map (lambda (x)
                                                  (call-with-values
                                                   (lambda () (resolve-identifier x w r mod #f))
                                                   (lambda (type value mod)
                                                     (let ((key type))
                                                       (cond
                                                         ((memv key '(displaced-lexical))
                                                          (syntax-violation
                                                           'syntax-parameterize
                                                           "identifier out of context"
                                                           e
                                                           (source-wrap x w s mod)))
                                                         ((memv key '(syntax-parameter)) value)
                                                         (else (syntax-violation
                                                                'syntax-parameterize
                                                                "invalid syntax parameter"
                                                                e
                                                                (source-wrap x w s mod))))))))
                                                var))
                                    (bindings
                                     (let ((trans-r (macros-only-env r)))
                                       (map (lambda (x)
                                              (cons 'syntax-parameter
                                                    (eval-local-transformer (expand x trans-r w mod) mod)))
                                            val))))
                                (expand-body (cons e1 e2) (source-wrap e w s mod) (extend-env names bindings r) w mod)))
                            tmp)
                     (syntax-violation 'syntax-parameterize "bad syntax" (source-wrap e w s mod))))))
            (expand-quote
             (lambda (e r w s mod)
               (let* ((tmp e) (tmp ($sc-dispatch tmp '(_ any))))
                 (if tmp
                     (apply (lambda (e) (build-data s (strip e))) tmp)
                     (syntax-violation 'quote "bad syntax" (source-wrap e w s mod))))))
            (expand-quote-syntax
             (lambda (e r w s mod)
               (let* ((tmp-1 (source-wrap e w s mod)) (tmp ($sc-dispatch tmp-1 '(_ any))))
                 (if tmp
                     (apply (lambda (e) (build-data s e)) tmp)
                     (let ((e tmp-1)) (syntax-violation 'quote "bad syntax" e))))))
            (expand-syntax
             (letrec* ((gen-syntax
                        (lambda (src e r maps ellipsis? mod)
                          (if (id? e)
                              (call-with-values
                               (lambda () (resolve-identifier e empty-wrap r mod #f))
                               (lambda (type value mod)
                                 (let ((key type))
                                   (cond
                                     ((memv key '(syntax))
                                      (call-with-values
                                       (lambda () (gen-ref src (car value) (cdr value) maps))
                                       (lambda (var maps) (values (list 'ref var) maps))))
                                     ((ellipsis? e r mod) (syntax-violation 'syntax "misplaced ellipsis" src))
                                     (else (values (list 'quote e) maps))))))
                              (let* ((tmp e) (tmp-1 ($sc-dispatch tmp '(any any))))
                                (if (and tmp-1 (apply (lambda (dots e) (ellipsis? dots r mod)) tmp-1))
                                    (apply (lambda (dots e) (gen-syntax src e r maps (lambda (e r mod) #f) mod)) tmp-1)
                                    (let ((tmp-1 ($sc-dispatch tmp '(any any . any))))
                                      (if (and tmp-1 (apply (lambda (x dots y) (ellipsis? dots r mod)) tmp-1))
                                          (apply (lambda (x dots y)
                                                   (let f ((y y)
                                                           (k (lambda (maps)
                                                                (call-with-values
                                                                 (lambda ()
                                                                   (gen-syntax src x r (cons '() maps) ellipsis? mod))
                                                                 (lambda (x maps)
                                                                   (if (null? (car maps))
                                                                       (syntax-violation 'syntax "extra ellipsis" src)
                                                                       (values (gen-map x (car maps)) (cdr maps))))))))
                                                     (let* ((tmp y) (tmp ($sc-dispatch tmp '(any . any))))
                                                       (if (and tmp
                                                                (apply (lambda (dots y) (ellipsis? dots r mod)) tmp))
                                                           (apply (lambda (dots y)
                                                                    (f y
                                                                       (lambda (maps)
                                                                         (call-with-values
                                                                          (lambda () (k (cons '() maps)))
                                                                          (lambda (x maps)
                                                                            (if (null? (car maps))
                                                                                (syntax-violation
                                                                                 'syntax
                                                                                 "extra ellipsis"
                                                                                 src)
                                                                                (values
                                                                                 (gen-mappend x (car maps))
                                                                                 (cdr maps))))))))
                                                                  tmp)
                                                           (call-with-values
                                                            (lambda () (gen-syntax src y r maps ellipsis? mod))
                                                            (lambda (y maps)
                                                              (call-with-values
                                                               (lambda () (k maps))
                                                               (lambda (x maps) (values (gen-append x y) maps)))))))))
                                                 tmp-1)
                                          (let ((tmp-1 ($sc-dispatch tmp '(any . any))))
                                            (if tmp-1
                                                (apply (lambda (x y)
                                                         (call-with-values
                                                          (lambda () (gen-syntax src x r maps ellipsis? mod))
                                                          (lambda (x maps)
                                                            (call-with-values
                                                             (lambda () (gen-syntax src y r maps ellipsis? mod))
                                                             (lambda (y maps) (values (gen-cons x y) maps))))))
                                                       tmp-1)
                                                (let ((tmp-1 ($sc-dispatch tmp '#(vector (any . each-any)))))
                                                  (if tmp-1
                                                      (apply (lambda (e1 e2)
                                                               (call-with-values
                                                                (lambda ()
                                                                  (gen-syntax src (cons e1 e2) r maps ellipsis? mod))
                                                                (lambda (e maps) (values (gen-vector e) maps))))
                                                             tmp-1)
                                                      (let ((tmp-1 (list tmp)))
                                                        (if (and tmp-1
                                                                 (apply (lambda (x) (eq? (syntax->datum x) #nil)) tmp-1))
                                                            (apply (lambda (x) (values ''#nil maps)) tmp-1)
                                                            (let ((tmp ($sc-dispatch tmp '())))
                                                              (if tmp
                                                                  (apply (lambda () (values ''() maps)) tmp)
                                                                  (values (list 'quote e) maps))))))))))))))))
                       (gen-ref
                        (lambda (src var level maps)
                          (cond
                            ((= level 0) (values var maps))
                            ((null? maps) (syntax-violation 'syntax "missing ellipsis" src))
                            (else (call-with-values
                                   (lambda () (gen-ref src var (#{1-}# level) (cdr maps)))
                                   (lambda (outer-var outer-maps)
                                     (let ((b (assq outer-var (car maps))))
                                       (if b
                                           (values (cdr b) maps)
                                           (let ((inner-var (gen-var 'tmp)))
                                             (values
                                              inner-var
                                              (cons (cons (cons outer-var inner-var) (car maps)) outer-maps)))))))))))
                       (gen-mappend (lambda (e map-env) (list 'apply '(primitive append) (gen-map e map-env))))
                       (gen-map
                        (lambda (e map-env)
                          (let ((formals (map cdr map-env)) (actuals (map (lambda (x) (list 'ref (car x))) map-env)))
                            (cond
                              ((eq? (car e) 'ref) (car actuals))
                              ((and-map (lambda (x) (and (eq? (car x) 'ref) (memq (cadr x) formals))) (cdr e))
                               (cons 'map
                                     (cons (list 'primitive (car e))
                                           (map (let ((r (map cons formals actuals)))
                                                  (lambda (x) (cdr (assq (cadr x) r))))
                                                (cdr e)))))
                              (else (cons 'map (cons (list 'lambda formals e) actuals)))))))
                       (gen-cons
                        (lambda (x y)
                          (let ((key (car y)))
                            (cond
                              ((memv key '(quote))
                               (cond
                                 ((eq? (car x) 'quote) (list 'quote (cons (cadr x) (cadr y))))
                                 ((eq? (cadr y) '()) (list 'list x))
                                 (else (list 'cons x y))))
                              ((memv key '(list)) (cons 'list (cons x (cdr y))))
                              (else (list 'cons x y))))))
                       (gen-append (lambda (x y) (if (equal? y ''()) x (list 'append x y))))
                       (gen-vector
                        (lambda (x)
                          (cond
                            ((eq? (car x) 'list) (cons 'vector (cdr x)))
                            ((eq? (car x) 'quote) (list 'quote (list->vector (cadr x))))
                            (else (list 'list->vector x)))))
                       (regen (lambda (x)
                                (let ((key (car x)))
                                  (cond
                                    ((memv key '(ref)) (build-lexical-reference no-source (cadr x) (cadr x)))
                                    ((memv key '(primitive)) (build-primref no-source (cadr x)))
                                    ((memv key '(quote)) (build-data no-source (cadr x)))
                                    ((memv key '(lambda))
                                     (if (list? (cadr x))
                                         (build-simple-lambda no-source (cadr x) #f (cadr x) '() (regen (caddr x)))
                                         (error "how did we get here" x)))
                                    (else (build-primcall no-source (car x) (map regen (cdr x)))))))))
               (lambda (e r w s mod)
                 (let* ((e (source-wrap e w s mod)) (tmp e) (tmp ($sc-dispatch tmp '(_ any))))
                   (if tmp
                       (apply (lambda (x)
                                (call-with-values
                                 (lambda () (gen-syntax e x r '() ellipsis? mod))
                                 (lambda (e maps) (regen e))))
                              tmp)
                       (syntax-violation 'syntax "bad `syntax' form" e))))))
            (expand-lambda
             (lambda (e r w s mod)
               (let* ((tmp e) (tmp ($sc-dispatch tmp '(_ any any . each-any))))
                 (if tmp
                     (apply (lambda (args e1 e2)
                              (call-with-values
                               (lambda () (lambda-formals args))
                               (lambda (req opt rest kw)
                                 (let lp ((body (cons e1 e2)) (meta '()))
                                   (let* ((tmp-1 body) (tmp ($sc-dispatch tmp-1 '(any any . each-any))))
                                     (if (and tmp
                                              (apply (lambda (docstring e1 e2) (string? (syntax->datum docstring))) tmp))
                                         (apply (lambda (docstring e1 e2)
                                                  (lp (cons e1 e2)
                                                      (append
                                                       meta
                                                       (list (cons 'documentation (syntax->datum docstring))))))
                                                tmp)
                                         (let ((tmp ($sc-dispatch tmp-1 '(#(vector #(each (any . any))) any . each-any))))
                                           (if tmp
                                               (apply (lambda (k v e1 e2)
                                                        (lp (cons e1 e2) (append meta (syntax->datum (map cons k v)))))
                                                      tmp)
                                               (expand-simple-lambda e r w s mod req rest meta body)))))))))
                            tmp)
                     (syntax-violation 'lambda "bad lambda" e)))))
            (expand-lambda*
             (lambda (e r w s mod)
               (let* ((tmp e) (tmp ($sc-dispatch tmp '(_ any any . each-any))))
                 (if tmp
                     (apply (lambda (args e1 e2)
                              (call-with-values
                               (lambda ()
                                 (expand-lambda-case e r w s mod lambda*-formals (list (cons args (cons e1 e2)))))
                               (lambda (meta lcase) (build-case-lambda s meta lcase))))
                            tmp)
                     (syntax-violation 'lambda "bad lambda*" e)))))
            (expand-case-lambda
             (lambda (e r w s mod)
               (letrec* ((build-it
                          (lambda (meta clauses)
                            (call-with-values
                             (lambda () (expand-lambda-case e r w s mod lambda-formals clauses))
                             (lambda (meta* lcase) (build-case-lambda s (append meta meta*) lcase))))))
                 (let* ((tmp-1 e) (tmp ($sc-dispatch tmp-1 '(_ . #(each (any any . each-any))))))
                   (if tmp
                       (apply (lambda (args e1 e2)
                                (build-it
                                 '()
                                 (map (lambda (tmp-680b775fb37a463-2 tmp-680b775fb37a463-1 tmp-680b775fb37a463)
                                        (cons tmp-680b775fb37a463 (cons tmp-680b775fb37a463-1 tmp-680b775fb37a463-2)))
                                      e2
                                      e1
                                      args)))
                              tmp)
                       (let ((tmp ($sc-dispatch tmp-1 '(_ any . #(each (any any . each-any))))))
                         (if (and tmp (apply (lambda (docstring args e1 e2) (string? (syntax->datum docstring))) tmp))
                             (apply (lambda (docstring args e1 e2)
                                      (build-it
                                       (list (cons 'documentation (syntax->datum docstring)))
                                       (map (lambda (tmp-680b775fb37a463-2 tmp-680b775fb37a463-1 tmp-680b775fb37a463)
                                              (cons tmp-680b775fb37a463
                                                    (cons tmp-680b775fb37a463-1 tmp-680b775fb37a463-2)))
                                            e2
                                            e1
                                            args)))
                                    tmp)
                             (syntax-violation 'case-lambda "bad case-lambda" e))))))))
            (expand-case-lambda*
             (lambda (e r w s mod)
               (letrec* ((build-it
                          (lambda (meta clauses)
                            (call-with-values
                             (lambda () (expand-lambda-case e r w s mod lambda*-formals clauses))
                             (lambda (meta* lcase) (build-case-lambda s (append meta meta*) lcase))))))
                 (let* ((tmp-1 e) (tmp ($sc-dispatch tmp-1 '(_ . #(each (any any . each-any))))))
                   (if tmp
                       (apply (lambda (args e1 e2)
                                (build-it
                                 '()
                                 (map (lambda (tmp-680b775fb37a463-2 tmp-680b775fb37a463-1 tmp-680b775fb37a463)
                                        (cons tmp-680b775fb37a463 (cons tmp-680b775fb37a463-1 tmp-680b775fb37a463-2)))
                                      e2
                                      e1
                                      args)))
                              tmp)
                       (let ((tmp ($sc-dispatch tmp-1 '(_ any . #(each (any any . each-any))))))
                         (if (and tmp (apply (lambda (docstring args e1 e2) (string? (syntax->datum docstring))) tmp))
                             (apply (lambda (docstring args e1 e2)
                                      (build-it
                                       (list (cons 'documentation (syntax->datum docstring)))
                                       (map (lambda (tmp-680b775fb37a463-117f
                                                     tmp-680b775fb37a463-117e
                                                     tmp-680b775fb37a463-117d)
                                              (cons tmp-680b775fb37a463-117d
                                                    (cons tmp-680b775fb37a463-117e tmp-680b775fb37a463-117f)))
                                            e2
                                            e1
                                            args)))
                                    tmp)
                             (syntax-violation 'case-lambda "bad case-lambda*" e))))))))
            (expand-with-ellipsis
             (lambda (e r w s mod)
               (let* ((tmp e) (tmp ($sc-dispatch tmp '(_ any any . each-any))))
                 (if (and tmp (apply (lambda (dots e1 e2) (id? dots)) tmp))
                     (apply (lambda (dots e1 e2)
                              (let ((id (if (symbol? dots)
                                            '#{ $sc-ellipsis }#
                                            (make-syntax
                                             '#{ $sc-ellipsis }#
                                             (syntax-wrap dots)
                                             (syntax-module dots)
                                             (syntax-sourcev dots)))))
                                (let ((ids (list id))
                                      (labels (list (gen-label)))
                                      (bindings (list (cons 'ellipsis (source-wrap dots w s mod)))))
                                  (let ((nw (make-binding-wrap ids labels w)) (nr (extend-env labels bindings r)))
                                    (expand-body (cons e1 e2) (source-wrap e nw s mod) nr nw mod)))))
                            tmp)
                     (syntax-violation 'with-ellipsis "bad syntax" (source-wrap e w s mod))))))
            (expand-let
             (letrec* ((expand-let
                        (lambda (e r w s mod constructor ids vals exps)
                          (if (not (valid-bound-ids? ids))
                              (syntax-violation 'let "duplicate bound variable" e)
                              (let ((labels (gen-labels ids)) (new-vars (map gen-var ids)))
                                (let ((nw (make-binding-wrap ids labels w)) (nr (extend-var-env labels new-vars r)))
                                  (constructor
                                   s
                                   (map syntax->datum ids)
                                   new-vars
                                   (map (lambda (x) (expand x r w mod)) vals)
                                   (expand-body exps (source-wrap e nw s mod) nr nw mod))))))))
               (lambda (e r w s mod)
                 (let* ((tmp-1 e) (tmp ($sc-dispatch tmp-1 '(_ #(each (any any)) any . each-any))))
                   (if (and tmp (apply (lambda (id val e1 e2) (and-map id? id)) tmp))
                       (apply (lambda (id val e1 e2) (expand-let e r w s mod build-let id val (cons e1 e2))) tmp)
                       (let ((tmp ($sc-dispatch tmp-1 '(_ any #(each (any any)) any . each-any))))
                         (if (and tmp (apply (lambda (f id val e1 e2) (and (id? f) (and-map id? id))) tmp))
                             (apply (lambda (f id val e1 e2)
                                      (expand-let e r w s mod build-named-let (cons f id) val (cons e1 e2)))
                                    tmp)
                             (syntax-violation 'let "bad let" (source-wrap e w s mod)))))))))
            (expand-letrec
             (lambda (e r w s mod)
               (let* ((tmp e) (tmp ($sc-dispatch tmp '(_ #(each (any any)) any . each-any))))
                 (if (and tmp (apply (lambda (id val e1 e2) (and-map id? id)) tmp))
                     (apply (lambda (id val e1 e2)
                              (let ((ids id))
                                (if (not (valid-bound-ids? ids))
                                    (syntax-violation 'letrec "duplicate bound variable" e)
                                    (let ((labels (gen-labels ids)) (new-vars (map gen-var ids)))
                                      (let ((w (make-binding-wrap ids labels w)) (r (extend-var-env labels new-vars r)))
                                        (build-letrec
                                         s
                                         #f
                                         (map syntax->datum ids)
                                         new-vars
                                         (map (lambda (x) (expand x r w mod)) val)
                                         (expand-body (cons e1 e2) (source-wrap e w s mod) r w mod)))))))
                            tmp)
                     (syntax-violation 'letrec "bad letrec" (source-wrap e w s mod))))))
            (expand-letrec*
             (lambda (e r w s mod)
               (let* ((tmp e) (tmp ($sc-dispatch tmp '(_ #(each (any any)) any . each-any))))
                 (if (and tmp (apply (lambda (id val e1 e2) (and-map id? id)) tmp))
                     (apply (lambda (id val e1 e2)
                              (let ((ids id))
                                (if (not (valid-bound-ids? ids))
                                    (syntax-violation 'letrec* "duplicate bound variable" e)
                                    (let ((labels (gen-labels ids)) (new-vars (map gen-var ids)))
                                      (let ((w (make-binding-wrap ids labels w)) (r (extend-var-env labels new-vars r)))
                                        (build-letrec
                                         s
                                         #t
                                         (map syntax->datum ids)
                                         new-vars
                                         (map (lambda (x) (expand x r w mod)) val)
                                         (expand-body (cons e1 e2) (source-wrap e w s mod) r w mod)))))))
                            tmp)
                     (syntax-violation 'letrec* "bad letrec*" (source-wrap e w s mod))))))
            (expand-set!
             (lambda (e r w s mod)
               (let* ((tmp-1 e) (tmp ($sc-dispatch tmp-1 '(_ any any))))
                 (if (and tmp (apply (lambda (id val) (id? id)) tmp))
                     (apply (lambda (id val)
                              (call-with-values
                               (lambda () (resolve-identifier id w r mod #t))
                               (lambda (type value id-mod)
                                 (let ((key type))
                                   (cond
                                     ((memv key '(lexical))
                                      (build-lexical-assignment s (syntax->datum id) value (expand val r w mod)))
                                     ((memv key '(global))
                                      (build-global-assignment s value (expand val r w mod) id-mod))
                                     ((memv key '(macro))
                                      (if (procedure-property value 'variable-transformer)
                                          (expand (expand-macro value e r w s #f mod) r empty-wrap mod)
                                          (syntax-violation
                                           'set!
                                           "not a variable transformer"
                                           (wrap e w mod)
                                           (wrap id w id-mod))))
                                     ((memv key '(displaced-lexical))
                                      (syntax-violation 'set! "identifier out of context" (wrap id w mod)))
                                     (else (syntax-violation 'set! "bad set!" (source-wrap e w s mod))))))))
                            tmp)
                     (let ((tmp ($sc-dispatch tmp-1 '(_ (any . each-any) any))))
                       (if tmp
                           (apply (lambda (head tail val)
                                    (call-with-values
                                     (lambda () (syntax-type head r empty-wrap no-source #f mod #t))
                                     (lambda (type value ee* ee ww ss modmod)
                                       (let ((key type))
                                         (if (memv key '(module-ref))
                                             (let ((val (expand val r w mod)))
                                               (call-with-values
                                                (lambda () (value (cons head tail) r w mod))
                                                (lambda (e r w s* mod)
                                                  (let* ((tmp-1 e) (tmp (list tmp-1)))
                                                    (if (and tmp (apply (lambda (e) (id? e)) tmp))
                                                        (apply (lambda (e)
                                                                 (build-global-assignment s (syntax->datum e) val mod))
                                                               tmp)
                                                        (syntax-violation
                                                         #f
                                                         "source expression failed to match any pattern"
                                                         tmp-1))))))
                                             (build-call
                                              s
                                              (expand
                                               (list (make-syntax 'setter '((top)) '(hygiene guile)) head)
                                               r
                                               w
                                               mod)
                                              (map (lambda (e) (expand e r w mod)) (append tail (list val)))))))))
                                  tmp)
                           (syntax-violation 'set! "bad set!" (source-wrap e w s mod))))))))
            (expand-public-ref
             (lambda (e r w mod)
               (let* ((tmp-1 e) (tmp ($sc-dispatch tmp-1 '(_ each-any any))))
                 (if (and tmp (apply (lambda (mod id) (and (and-map id? mod) (id? id))) tmp))
                     (apply (lambda (mod id)
                              (values
                               (syntax->datum id)
                               r
                               top-wrap
                               #f
                               (syntax->datum (cons (make-syntax 'public '((top)) '(hygiene guile)) mod))))
                            tmp)
                     (syntax-violation #f "source expression failed to match any pattern" tmp-1)))))
            (expand-private-ref
             (lambda (e r w mod)
               (letrec* ((remodulate
                          (lambda (x mod)
                            (cond
                              ((pair? x) (cons (remodulate (car x) mod) (remodulate (cdr x) mod)))
                              ((syntax? x)
                               (make-syntax
                                (remodulate (syntax-expression x) mod)
                                (syntax-wrap x)
                                mod
                                (syntax-sourcev x)))
                              ((vector? x)
                               (let* ((n (vector-length x)) (v (make-vector n)))
                                 (let loop ((i 0))
                                   (if (= i n)
                                       (begin (if #f #f) v)
                                       (begin (vector-set! v i (remodulate (vector-ref x i) mod)) (loop (#{1+}# i)))))))
                              (else x)))))
                 (let* ((tmp e)
                        (tmp-1 ($sc-dispatch
                                tmp
                                (list '_ (vector 'free-id (make-syntax 'primitive '((top)) '(hygiene guile))) 'any))))
                   (if (and tmp-1
                            (apply (lambda (id)
                                     (and (id? id)
                                          (equal? (cdr (or (and (syntax? id) (syntax-module id)) mod)) '(guile))))
                                   tmp-1))
                       (apply (lambda (id) (values (syntax->datum id) r top-wrap #f '(primitive))) tmp-1)
                       (let ((tmp-1 ($sc-dispatch tmp '(_ each-any any))))
                         (if (and tmp-1 (apply (lambda (mod id) (and (and-map id? mod) (id? id))) tmp-1))
                             (apply (lambda (mod id)
                                      (values
                                       (syntax->datum id)
                                       r
                                       top-wrap
                                       #f
                                       (syntax->datum (cons (make-syntax 'private '((top)) '(hygiene guile)) mod))))
                                    tmp-1)
                             (let ((tmp-1 ($sc-dispatch
                                           tmp
                                           (list '_
                                                 (vector 'free-id (make-syntax '@@ '((top)) '(hygiene guile)))
                                                 'each-any
                                                 'any))))
                               (if (and tmp-1 (apply (lambda (mod exp) (and-map id? mod)) tmp-1))
                                   (apply (lambda (mod exp)
                                            (let ((mod (syntax->datum
                                                        (cons (make-syntax 'private '((top)) '(hygiene guile)) mod))))
                                              (values (remodulate exp mod) r w (source-annotation exp) mod)))
                                          tmp-1)
                                   (syntax-violation #f "source expression failed to match any pattern" tmp))))))))))
            (expand-if
             (lambda (e r w s mod)
               (let* ((tmp e) (tmp-1 ($sc-dispatch tmp '(_ any any))))
                 (if tmp-1
                     (apply (lambda (test then)
                              (build-conditional s (expand test r w mod) (expand then r w mod) (build-void no-source)))
                            tmp-1)
                     (let ((tmp-1 ($sc-dispatch tmp '(_ any any any))))
                       (if tmp-1
                           (apply (lambda (test then else)
                                    (build-conditional
                                     s
                                     (expand test r w mod)
                                     (expand then r w mod)
                                     (expand else r w mod)))
                                  tmp-1)
                           (syntax-violation #f "source expression failed to match any pattern" tmp)))))))
            (expand-syntax-case
             (letrec* ((convert-pattern
                        (lambda (pattern keys ellipsis?)
                          (letrec* ((cvt* (lambda (p* n ids)
                                            (let* ((tmp p*) (tmp ($sc-dispatch tmp '(any . any))))
                                              (if tmp
                                                  (apply (lambda (x y)
                                                           (call-with-values
                                                            (lambda () (cvt* y n ids))
                                                            (lambda (y ids)
                                                              (call-with-values
                                                               (lambda () (cvt x n ids))
                                                               (lambda (x ids) (values (cons x y) ids))))))
                                                         tmp)
                                                  (cvt p* n ids)))))
                                    (v-reverse
                                     (lambda (x)
                                       (let loop ((r '()) (x x))
                                         (if (not (pair? x)) (values r x) (loop (cons (car x) r) (cdr x))))))
                                    (cvt (lambda (p n ids)
                                           (if (id? p)
                                               (cond
                                                 ((bound-id-member? p keys) (values (vector 'free-id p) ids))
                                                 ((free-id=? p (make-syntax '_ '((top)) '(hygiene guile)))
                                                  (values '_ ids))
                                                 (else (values 'any (cons (cons p n) ids))))
                                               (let* ((tmp p) (tmp-1 ($sc-dispatch tmp '(any any))))
                                                 (if (and tmp-1 (apply (lambda (x dots) (ellipsis? dots)) tmp-1))
                                                     (apply (lambda (x dots)
                                                              (call-with-values
                                                               (lambda () (cvt x (#{1+}# n) ids))
                                                               (lambda (p ids)
                                                                 (values
                                                                  (if (eq? p 'any) 'each-any (vector 'each p))
                                                                  ids))))
                                                            tmp-1)
                                                     (let ((tmp-1 ($sc-dispatch tmp '(any any . any))))
                                                       (if (and tmp-1
                                                                (apply (lambda (x dots ys) (ellipsis? dots)) tmp-1))
                                                           (apply (lambda (x dots ys)
                                                                    (call-with-values
                                                                     (lambda () (cvt* ys n ids))
                                                                     (lambda (ys ids)
                                                                       (call-with-values
                                                                        (lambda () (cvt x (+ n 1) ids))
                                                                        (lambda (x ids)
                                                                          (call-with-values
                                                                           (lambda () (v-reverse ys))
                                                                           (lambda (ys e)
                                                                             (values (vector 'each+ x ys e) ids))))))))
                                                                  tmp-1)
                                                           (let ((tmp-1 ($sc-dispatch tmp '(any . any))))
                                                             (if tmp-1
                                                                 (apply (lambda (x y)
                                                                          (call-with-values
                                                                           (lambda () (cvt y n ids))
                                                                           (lambda (y ids)
                                                                             (call-with-values
                                                                              (lambda () (cvt x n ids))
                                                                              (lambda (x ids) (values (cons x y) ids))))))
                                                                        tmp-1)
                                                                 (let ((tmp-1 ($sc-dispatch tmp '())))
                                                                   (if tmp-1
                                                                       (apply (lambda () (values '() ids)) tmp-1)
                                                                       (let ((tmp-1 ($sc-dispatch
                                                                                     tmp
                                                                                     '#(vector each-any))))
                                                                         (if tmp-1
                                                                             (apply (lambda (x)
                                                                                      (call-with-values
                                                                                       (lambda () (cvt x n ids))
                                                                                       (lambda (p ids)
                                                                                         (values (vector 'vector p) ids))))
                                                                                    tmp-1)
                                                                             (let ((x tmp))
                                                                               (values (vector 'atom (strip p)) ids))))))))))))))))
                            (cvt pattern 0 '()))))
                       (build-dispatch-call
                        (lambda (pvars exp y r mod)
                          (let ((ids (map car pvars)) (levels (map cdr pvars)))
                            (let ((labels (gen-labels ids)) (new-vars (map gen-var ids)))
                              (build-primcall
                               no-source
                               'apply
                               (list (build-simple-lambda
                                      no-source
                                      (map syntax->datum ids)
                                      #f
                                      new-vars
                                      '()
                                      (expand
                                       exp
                                       (extend-env
                                        labels
                                        (map (lambda (var level) (cons 'syntax (cons var level)))
                                             new-vars
                                             (map cdr pvars))
                                        r)
                                       (make-binding-wrap ids labels empty-wrap)
                                       mod))
                                     y))))))
                       (gen-clause
                        (lambda (x keys clauses r pat fender exp mod)
                          (call-with-values
                           (lambda () (convert-pattern pat keys (lambda (e) (ellipsis? e r mod))))
                           (lambda (p pvars)
                             (cond
                               ((not (and-map (lambda (x) (not (ellipsis? (car x) r mod))) pvars))
                                (syntax-violation 'syntax-case "misplaced ellipsis" pat))
                               ((not (distinct-bound-ids? (map car pvars)))
                                (syntax-violation 'syntax-case "duplicate pattern variable" pat))
                               (else (let ((y (gen-var 'tmp)))
                                       (build-call
                                        no-source
                                        (build-simple-lambda
                                         no-source
                                         (list 'tmp)
                                         #f
                                         (list y)
                                         '()
                                         (let ((y (build-lexical-reference no-source 'tmp y)))
                                           (build-conditional
                                            no-source
                                            (let* ((tmp fender) (tmp ($sc-dispatch tmp '#(atom #t))))
                                              (if tmp
                                                  (apply (lambda () y) tmp)
                                                  (build-conditional
                                                   no-source
                                                   y
                                                   (build-dispatch-call pvars fender y r mod)
                                                   (build-data no-source #f))))
                                            (build-dispatch-call pvars exp y r mod)
                                            (gen-syntax-case x keys clauses r mod))))
                                        (list (if (eq? p 'any)
                                                  (build-primcall no-source 'list (list x))
                                                  (build-primcall
                                                   no-source
                                                   '$sc-dispatch
                                                   (list x (build-data no-source p)))))))))))))
                       (gen-syntax-case
                        (lambda (x keys clauses r mod)
                          (if (null? clauses)
                              (build-primcall
                               no-source
                               'syntax-violation
                               (list (build-data no-source #f)
                                     (build-data no-source "source expression failed to match any pattern")
                                     x))
                              (let* ((tmp-1 (car clauses)) (tmp ($sc-dispatch tmp-1 '(any any))))
                                (if tmp
                                    (apply (lambda (pat exp)
                                             (if (and (id? pat)
                                                      (and-map
                                                       (lambda (x) (not (free-id=? pat x)))
                                                       (cons (make-syntax '... '((top)) '(hygiene guile)) keys)))
                                                 (if (free-id=? pat (make-syntax '_ '((top)) '(hygiene guile)))
                                                     (expand exp r empty-wrap mod)
                                                     (let ((labels (list (gen-label))) (var (gen-var pat)))
                                                       (build-call
                                                        no-source
                                                        (build-simple-lambda
                                                         no-source
                                                         (list (syntax->datum pat))
                                                         #f
                                                         (list var)
                                                         '()
                                                         (expand
                                                          exp
                                                          (extend-env labels (list (cons 'syntax (cons var 0))) r)
                                                          (make-binding-wrap (list pat) labels empty-wrap)
                                                          mod))
                                                        (list x))))
                                                 (gen-clause x keys (cdr clauses) r pat #t exp mod)))
                                           tmp)
                                    (let ((tmp ($sc-dispatch tmp-1 '(any any any))))
                                      (if tmp
                                          (apply (lambda (pat fender exp)
                                                   (gen-clause x keys (cdr clauses) r pat fender exp mod))
                                                 tmp)
                                          (syntax-violation 'syntax-case "invalid clause" (car clauses))))))))))
               (lambda (e r w s mod)
                 (let* ((e (source-wrap e w s mod)) (tmp-1 e) (tmp ($sc-dispatch tmp-1 '(_ any each-any . each-any))))
                   (if tmp
                       (apply (lambda (val key m)
                                (if (and-map (lambda (x) (and (id? x) (not (ellipsis? x r mod)))) key)
                                    (let ((x (gen-var 'tmp)))
                                      (build-call
                                       s
                                       (build-simple-lambda
                                        no-source
                                        (list 'tmp)
                                        #f
                                        (list x)
                                        '()
                                        (gen-syntax-case (build-lexical-reference no-source 'tmp x) key m r mod))
                                       (list (expand val r empty-wrap mod))))
                                    (syntax-violation 'syntax-case "invalid literals list" e)))
                              tmp)
                       (syntax-violation #f "source expression failed to match any pattern" tmp-1)))))))
    (global-extend 'local-syntax 'letrec-syntax #t)
    (global-extend 'local-syntax 'let-syntax #f)
    (global-extend 'core 'syntax-parameterize expand-syntax-parameterize)
    (global-extend 'core 'quote expand-quote)
    (global-extend 'core 'quote-syntax expand-quote-syntax)
    (global-extend 'core 'syntax expand-syntax)
    (global-extend 'core 'lambda expand-lambda)
    (global-extend 'core 'lambda* expand-lambda*)
    (global-extend 'core 'case-lambda expand-case-lambda)
    (global-extend 'core 'case-lambda* expand-case-lambda*)
    (global-extend 'core 'with-ellipsis expand-with-ellipsis)
    (global-extend 'core 'let expand-let)
    (global-extend 'core 'letrec expand-letrec)
    (global-extend 'core 'letrec* expand-letrec*)
    (global-extend 'core 'set! expand-set!)
    (global-extend 'module-ref '@ expand-public-ref)
    (global-extend 'module-ref '@@ expand-private-ref)
    (global-extend 'core 'if expand-if)
    (global-extend 'begin 'begin '())
    (global-extend 'define 'define '())
    (global-extend 'define-syntax 'define-syntax '())
    (global-extend 'define-syntax-parameter 'define-syntax-parameter '())
    (global-extend 'eval-when 'eval-when '())
    (global-extend 'core 'syntax-case expand-syntax-case)
    (set! macroexpand
          (lambda* (x #:optional (m 'e) (esew '(eval)))
            (letrec* ((unstrip
                       (lambda (x)
                         (letrec* ((annotate
                                    (lambda (result)
                                      (let ((props (source-properties x)))
                                        (if (pair? props) (datum->syntax #f result #:source props) result)))))
                           (cond
                             ((pair? x) (annotate (cons (unstrip (car x)) (unstrip (cdr x)))))
                             ((vector? x)
                              (let ((v (make-vector (vector-length x))))
                                (annotate (list->vector (map unstrip (vector->list x))))))
                             ((syntax? x) x)
                             (else (annotate x)))))))
              (expand-top-sequence
               (list (unstrip x))
               null-env
               top-wrap
               #f
               m
               esew
               (cons 'hygiene (module-name (current-module)))))))
    (set! identifier? (lambda (x) (nonsymbol-id? x)))
    (set! datum->syntax
          (lambda* (id datum #:key (source #f #:source))
            (letrec* ((props->sourcev
                       (lambda (alist)
                         (and (pair? alist)
                              (vector (assq-ref alist 'filename) (assq-ref alist 'line) (assq-ref alist 'column))))))
              (make-syntax
               datum
               (if id (syntax-wrap id) empty-wrap)
               (and id (syntax-module id))
               (cond
                 ((not source) (props->sourcev (source-properties datum)))
                 ((and (list? source) (and-map pair? source)) (props->sourcev source))
                 ((and (vector? source) (= 3 (vector-length source))) source)
                 (else (syntax-sourcev source)))))))
    (set! syntax->datum (lambda (x) (strip x)))
    (set! generate-temporaries
          (lambda (ls)
            (let ((x ls)) (if (not (list? x)) (syntax-violation 'generate-temporaries "invalid argument" x)))
            (let ((mod (cons 'hygiene (module-name (current-module)))))
              (map (lambda (x) (wrap (gen-var 't) top-wrap mod)) ls))))
    (set! free-identifier=?
          (lambda (x y)
            (let ((x x)) (if (not (nonsymbol-id? x)) (syntax-violation 'free-identifier=? "invalid argument" x)))
            (let ((x y)) (if (not (nonsymbol-id? x)) (syntax-violation 'free-identifier=? "invalid argument" x)))
            (free-id=? x y)))
    (set! bound-identifier=?
          (lambda (x y)
            (let ((x x)) (if (not (nonsymbol-id? x)) (syntax-violation 'bound-identifier=? "invalid argument" x)))
            (let ((x y)) (if (not (nonsymbol-id? x)) (syntax-violation 'bound-identifier=? "invalid argument" x)))
            (bound-id=? x y)))
    (set! syntax-violation
          (lambda* (who message form #:optional (subform #f))
            (let ((x who))
              (if (not (let ((x x)) (or (not x) (string? x) (symbol? x))))
                  (syntax-violation 'syntax-violation "invalid argument" x)))
            (let ((x message)) (if (not (string? x)) (syntax-violation 'syntax-violation "invalid argument" x)))
            (throw 'syntax-error
                   who
                   message
                   (sourcev->alist (or (source-annotation subform) (source-annotation form)))
                   (strip form)
                   (strip subform))))
    (letrec* ((%syntax-module
               (lambda (id)
                 (let ((x id)) (if (not (nonsymbol-id? x)) (syntax-violation 'syntax-module "invalid argument" x)))
                 (let ((mod (syntax-module id))) (and mod (not (equal? mod '(primitive))) (cdr mod)))))
              (syntax-local-binding
               (lambda* (id #:key (resolve-syntax-parameters? #t #:resolve-syntax-parameters?))
                 (let ((x id))
                   (if (not (nonsymbol-id? x)) (syntax-violation 'syntax-local-binding "invalid argument" x)))
                 (with-transformer-environment
                  (lambda (e r w s rib mod)
                    (letrec* ((strip-anti-mark
                               (lambda (w)
                                 (let ((ms (wrap-marks w)) (s (wrap-subst w)))
                                   (if (and (pair? ms) (eq? (car ms) the-anti-mark))
                                       (make-wrap (cdr ms) (if rib (cons rib (cdr s)) (cdr s)))
                                       (make-wrap ms (if rib (cons rib s) s)))))))
                      (call-with-values
                       (lambda ()
                         (resolve-identifier
                          (syntax-expression id)
                          (strip-anti-mark (syntax-wrap id))
                          r
                          (or (syntax-module id) mod)
                          resolve-syntax-parameters?))
                       (lambda (type value mod)
                         (let ((key type))
                           (cond
                             ((memv key '(lexical)) (values 'lexical value))
                             ((memv key '(macro)) (values 'macro value))
                             ((memv key '(syntax-parameter)) (values 'syntax-parameter value))
                             ((memv key '(syntax)) (values 'pattern-variable value))
                             ((memv key '(displaced-lexical)) (values 'displaced-lexical #f))
                             ((memv key '(global))
                              (if (equal? mod '(primitive))
                                  (values 'primitive value)
                                  (values 'global (cons value (cdr mod)))))
                             ((memv key '(ellipsis))
                              (values 'ellipsis (wrap-syntax value (anti-mark (syntax-wrap value)) mod)))
                             (else (values 'other #f)))))))))))
              (syntax-locally-bound-identifiers
               (lambda (id)
                 (let ((x id))
                   (if (not (nonsymbol-id? x))
                       (syntax-violation 'syntax-locally-bound-identifiers "invalid argument" x)))
                 (locally-bound-identifiers (syntax-wrap id) (syntax-module id)))))
      (define! '%syntax-module %syntax-module)
      (define! 'syntax-local-binding syntax-local-binding)
      (define! 'syntax-locally-bound-identifiers syntax-locally-bound-identifiers))
    (set! $sc-dispatch
          (lambda (e p)
            (letrec* ((match-each
                       (lambda (e p w mod)
                         (cond
                           ((pair? e)
                            (let ((first (match (car e) p w '() mod)))
                              (and first (let ((rest (match-each (cdr e) p w mod))) (and rest (cons first rest))))))
                           ((null? e) '())
                           ((syntax? e)
                            (match-each
                             (syntax-expression e)
                             p
                             (join-wraps w (syntax-wrap e))
                             (or (syntax-module e) mod)))
                           (else #f))))
                      (match-each+
                       (lambda (e x-pat y-pat z-pat w r mod)
                         (let f ((e e) (w w))
                           (cond
                             ((pair? e)
                              (call-with-values
                               (lambda () (f (cdr e) w))
                               (lambda (xr* y-pat r)
                                 (if r
                                     (if (null? y-pat)
                                         (let ((xr (match (car e) x-pat w '() mod)))
                                           (if xr (values (cons xr xr*) y-pat r) (values #f #f #f)))
                                         (values '() (cdr y-pat) (match (car e) (car y-pat) w r mod)))
                                     (values #f #f #f)))))
                             ((syntax? e) (f (syntax-expression e) (join-wraps w (syntax-wrap e))))
                             (else (values '() y-pat (match e z-pat w r mod)))))))
                      (match-each-any
                       (lambda (e w mod)
                         (cond
                           ((pair? e) (let ((l (match-each-any (cdr e) w mod))) (and l (cons (wrap (car e) w mod) l))))
                           ((null? e) '())
                           ((syntax? e) (match-each-any (syntax-expression e) (join-wraps w (syntax-wrap e)) mod))
                           (else #f))))
                      (match-empty
                       (lambda (p r)
                         (cond
                           ((null? p) r)
                           ((eq? p '_) r)
                           ((eq? p 'any) (cons '() r))
                           ((pair? p) (match-empty (car p) (match-empty (cdr p) r)))
                           ((eq? p 'each-any) (cons '() r))
                           (else (let ((key (vector-ref p 0)))
                                   (cond
                                     ((memv key '(each)) (match-empty (vector-ref p 1) r))
                                     ((memv key '(each+))
                                      (match-empty
                                       (vector-ref p 1)
                                       (match-empty (reverse (vector-ref p 2)) (match-empty (vector-ref p 3) r))))
                                     ((memv key '(free-id atom)) r)
                                     ((memv key '(vector)) (match-empty (vector-ref p 1) r))))))))
                      (combine (lambda (r* r) (if (null? (car r*)) r (cons (map car r*) (combine (map cdr r*) r)))))
                      (match*
                       (lambda (e p w r mod)
                         (cond
                           ((null? p) (and (null? e) r))
                           ((pair? p) (and (pair? e) (match (car e) (car p) w (match (cdr e) (cdr p) w r mod) mod)))
                           ((eq? p 'each-any) (let ((l (match-each-any e w mod))) (and l (cons l r))))
                           (else (let ((key (vector-ref p 0)))
                                   (cond
                                     ((memv key '(each))
                                      (if (null? e)
                                          (match-empty (vector-ref p 1) r)
                                          (let ((l (match-each e (vector-ref p 1) w mod)))
                                            (and l
                                                 (let collect ((l l))
                                                   (if (null? (car l)) r (cons (map car l) (collect (map cdr l)))))))))
                                     ((memv key '(each+))
                                      (call-with-values
                                       (lambda ()
                                         (match-each+ e (vector-ref p 1) (vector-ref p 2) (vector-ref p 3) w r mod))
                                       (lambda (xr* y-pat r)
                                         (and r
                                              (null? y-pat)
                                              (if (null? xr*) (match-empty (vector-ref p 1) r) (combine xr* r))))))
                                     ((memv key '(free-id)) (and (id? e) (free-id=? (wrap e w mod) (vector-ref p 1)) r))
                                     ((memv key '(atom)) (and (equal? (vector-ref p 1) (strip e)) r))
                                     ((memv key '(vector))
                                      (and (vector? e) (match (vector->list e) (vector-ref p 1) w r mod)))))))))
                      (match (lambda (e p w r mod)
                               (cond
                                 ((not r) #f)
                                 ((eq? p '_) r)
                                 ((eq? p 'any) (cons (wrap e w mod) r))
                                 ((syntax? e)
                                  (match*
                                   (syntax-expression e)
                                   p
                                   (join-wraps w (syntax-wrap e))
                                   r
                                   (or (syntax-module e) mod)))
                                 (else (match* e p w r mod))))))
              (cond
                ((eq? p 'any) (list e))
                ((eq? p '_) '())
                ((syntax? e) (match* (syntax-expression e) p (syntax-wrap e) '() (syntax-module e)))
                (else (match* e p empty-wrap '() #f))))))))

(define with-syntax
  (let ((make-syntax make-syntax))
    (make-syntax-transformer
     'with-syntax
     'macro
     (lambda (x)
       (let ((tmp x))
         (let ((tmp-1 ($sc-dispatch tmp '(_ () any . each-any))))
           (if tmp-1
               (apply (lambda (e1 e2) (cons (make-syntax 'let '((top)) '(hygiene guile)) (cons '() (cons e1 e2))))
                      tmp-1)
               (let ((tmp-1 ($sc-dispatch tmp '(_ ((any any)) any . each-any))))
                 (if tmp-1
                     (apply (lambda (out in e1 e2)
                              (list (make-syntax 'syntax-case '((top)) '(hygiene guile))
                                    in
                                    '()
                                    (list out
                                          (cons (make-syntax 'let '((top)) '(hygiene guile)) (cons '() (cons e1 e2))))))
                            tmp-1)
                     (let ((tmp-1 ($sc-dispatch tmp '(_ #(each (any any)) any . each-any))))
                       (if tmp-1
                           (apply (lambda (out in e1 e2)
                                    (list (make-syntax 'syntax-case '((top)) '(hygiene guile))
                                          (cons (make-syntax 'list '((top)) '(hygiene guile)) in)
                                          '()
                                          (list out
                                                (cons (make-syntax 'let '((top)) '(hygiene guile))
                                                      (cons '() (cons e1 e2))))))
                                  tmp-1)
                           (syntax-violation #f "source expression failed to match any pattern" tmp))))))))))))

(define syntax-error
  (let ((make-syntax make-syntax))
    (make-syntax-transformer
     'syntax-error
     'macro
     (lambda (x)
       (let ((tmp-1 x))
         (let ((tmp ($sc-dispatch tmp-1 '(_ (any . any) any . each-any))))
           (if (if tmp (apply (lambda (keyword operands message arg) (string? (syntax->datum message))) tmp) #f)
               (apply (lambda (keyword operands message arg)
                        (syntax-violation
                         (syntax->datum keyword)
                         (string-join
                          (cons (syntax->datum message) (map (lambda (x) (object->string (syntax->datum x))) arg)))
                         (if (syntax->datum keyword) (cons keyword operands) #f)))
                      tmp)
               (let ((tmp ($sc-dispatch tmp-1 '(_ any . each-any))))
                 (if (if tmp (apply (lambda (message arg) (string? (syntax->datum message))) tmp) #f)
                     (apply (lambda (message arg)
                              (cons (make-syntax
                                     'syntax-error
                                     (list '(top)
                                           (vector
                                            'ribcage
                                            '#(syntax-error)
                                            '#((top))
                                            (vector
                                             (cons '(hygiene guile)
                                                   (make-syntax 'syntax-error '((top)) '(hygiene guile))))))
                                     '(hygiene guile))
                                    (cons '(#f) (cons message arg))))
                            tmp)
                     (syntax-violation #f "source expression failed to match any pattern" tmp-1))))))))))

(define syntax-rules
  (let ((make-syntax make-syntax))
    (make-syntax-transformer
     'syntax-rules
     'macro
     (lambda (xx)
       (letrec* ((expand-clause
                  (lambda (clause)
                    (let ((tmp-1 clause))
                      (let ((tmp ($sc-dispatch
                                  tmp-1
                                  (list '(any . any)
                                        (cons (vector 'free-id (make-syntax 'syntax-error '((top)) '(hygiene guile)))
                                              '(any . each-any))))))
                        (if (if tmp
                                (apply (lambda (keyword pattern message arg) (string? (syntax->datum message))) tmp)
                                #f)
                            (apply (lambda (keyword pattern message arg)
                                     (list (cons (make-syntax 'dummy '((top)) '(hygiene guile)) pattern)
                                           (list (make-syntax 'syntax '((top)) '(hygiene guile))
                                                 (cons (make-syntax 'syntax-error '((top)) '(hygiene guile))
                                                       (cons (cons (make-syntax 'dummy '((top)) '(hygiene guile))
                                                                   pattern)
                                                             (cons message arg))))))
                                   tmp)
                            (let ((tmp ($sc-dispatch tmp-1 '((any . any) any))))
                              (if tmp
                                  (apply (lambda (keyword pattern template)
                                           (list (cons (make-syntax 'dummy '((top)) '(hygiene guile)) pattern)
                                                 (list (make-syntax 'syntax '((top)) '(hygiene guile)) template)))
                                         tmp)
                                  (syntax-violation #f "source expression failed to match any pattern" tmp-1))))))))
                 (expand-syntax-rules
                  (lambda (dots keys docstrings clauses)
                    (let ((tmp-1 (list keys docstrings clauses (map expand-clause clauses))))
                      (let ((tmp ($sc-dispatch tmp-1 '(each-any each-any #(each ((any . any) any)) each-any))))
                        (if tmp
                            (apply (lambda (k docstring keyword pattern template clause)
                                     (let ((tmp (cons (make-syntax 'lambda '((top)) '(hygiene guile))
                                                      (cons (list (make-syntax 'x '((top)) '(hygiene guile)))
                                                            (append
                                                             docstring
                                                             (list (vector
                                                                    (cons (make-syntax
                                                                           'macro-type
                                                                           '((top))
                                                                           '(hygiene guile))
                                                                          (make-syntax
                                                                           'syntax-rules
                                                                           (list '(top)
                                                                                 (vector
                                                                                  'ribcage
                                                                                  '#(syntax-rules)
                                                                                  '#((top))
                                                                                  (vector
                                                                                   (cons '(hygiene guile)
                                                                                         (make-syntax
                                                                                          'syntax-rules
                                                                                          '((top))
                                                                                          '(hygiene guile))))))
                                                                           '(hygiene guile)))
                                                                    (cons (make-syntax
                                                                           'patterns
                                                                           '((top))
                                                                           '(hygiene guile))
                                                                          pattern))
                                                                   (cons (make-syntax
                                                                          'syntax-case
                                                                          '((top))
                                                                          '(hygiene guile))
                                                                         (cons (make-syntax
                                                                                'x
                                                                                '((top))
                                                                                '(hygiene guile))
                                                                               (cons k clause)))))))))
                                       (let ((form tmp))
                                         (if dots
                                             (let ((tmp dots))
                                               (let ((dots tmp))
                                                 (list (make-syntax 'with-ellipsis '((top)) '(hygiene guile)) dots form)))
                                             form))))
                                   tmp)
                            (syntax-violation #f "source expression failed to match any pattern" tmp-1)))))))
         (let ((tmp xx))
           (let ((tmp-1 ($sc-dispatch tmp '(_ each-any . #(each ((any . any) any))))))
             (if tmp-1
                 (apply (lambda (k keyword pattern template)
                          (expand-syntax-rules
                           #f
                           k
                           '()
                           (map (lambda (tmp-680b775fb37a463-145d tmp-680b775fb37a463-145c tmp-680b775fb37a463-145b)
                                  (list (cons tmp-680b775fb37a463-145b tmp-680b775fb37a463-145c)
                                        tmp-680b775fb37a463-145d))
                                template
                                pattern
                                keyword)))
                        tmp-1)
                 (let ((tmp-1 ($sc-dispatch tmp '(_ each-any any . #(each ((any . any) any))))))
                   (if (if tmp-1
                           (apply (lambda (k docstring keyword pattern template) (string? (syntax->datum docstring)))
                                  tmp-1)
                           #f)
                       (apply (lambda (k docstring keyword pattern template)
                                (expand-syntax-rules
                                 #f
                                 k
                                 (list docstring)
                                 (map (lambda (tmp-680b775fb37a463-2 tmp-680b775fb37a463-1 tmp-680b775fb37a463)
                                        (list (cons tmp-680b775fb37a463 tmp-680b775fb37a463-1) tmp-680b775fb37a463-2))
                                      template
                                      pattern
                                      keyword)))
                              tmp-1)
                       (let ((tmp-1 ($sc-dispatch tmp '(_ any each-any . #(each ((any . any) any))))))
                         (if (if tmp-1 (apply (lambda (dots k keyword pattern template) (identifier? dots)) tmp-1) #f)
                             (apply (lambda (dots k keyword pattern template)
                                      (expand-syntax-rules
                                       dots
                                       k
                                       '()
                                       (map (lambda (tmp-680b775fb37a463-148f
                                                     tmp-680b775fb37a463-148e
                                                     tmp-680b775fb37a463-148d)
                                              (list (cons tmp-680b775fb37a463-148d tmp-680b775fb37a463-148e)
                                                    tmp-680b775fb37a463-148f))
                                            template
                                            pattern
                                            keyword)))
                                    tmp-1)
                             (let ((tmp-1 ($sc-dispatch tmp '(_ any each-any any . #(each ((any . any) any))))))
                               (if (if tmp-1
                                       (apply (lambda (dots k docstring keyword pattern template)
                                                (if (identifier? dots) (string? (syntax->datum docstring)) #f))
                                              tmp-1)
                                       #f)
                                   (apply (lambda (dots k docstring keyword pattern template)
                                            (expand-syntax-rules
                                             dots
                                             k
                                             (list docstring)
                                             (map (lambda (tmp-680b775fb37a463-14ae
                                                           tmp-680b775fb37a463-14ad
                                                           tmp-680b775fb37a463-14ac)
                                                    (list (cons tmp-680b775fb37a463-14ac tmp-680b775fb37a463-14ad)
                                                          tmp-680b775fb37a463-14ae))
                                                  template
                                                  pattern
                                                  keyword)))
                                          tmp-1)
                                   (syntax-violation #f "source expression failed to match any pattern" tmp)))))))))))))))

(define define-syntax-rule
  (let ((make-syntax make-syntax))
    (make-syntax-transformer
     'define-syntax-rule
     'macro
     (lambda (x)
       (let ((tmp-1 x))
         (let ((tmp ($sc-dispatch tmp-1 '(_ (any . any) any))))
           (if tmp
               (apply (lambda (name pattern template)
                        (list (make-syntax 'define-syntax '((top)) '(hygiene guile))
                              name
                              (list (make-syntax 'syntax-rules '((top)) '(hygiene guile))
                                    '()
                                    (list (cons (make-syntax '_ '((top)) '(hygiene guile)) pattern) template))))
                      tmp)
               (let ((tmp ($sc-dispatch tmp-1 '(_ (any . any) any any))))
                 (if (if tmp
                         (apply (lambda (name pattern docstring template) (string? (syntax->datum docstring))) tmp)
                         #f)
                     (apply (lambda (name pattern docstring template)
                              (list (make-syntax 'define-syntax '((top)) '(hygiene guile))
                                    name
                                    (list (make-syntax 'syntax-rules '((top)) '(hygiene guile))
                                          '()
                                          docstring
                                          (list (cons (make-syntax '_ '((top)) '(hygiene guile)) pattern) template))))
                            tmp)
                     (syntax-violation #f "source expression failed to match any pattern" tmp-1))))))))))

(define let*
  (let ((make-syntax make-syntax))
    (make-syntax-transformer
     'let*
     'macro
     (lambda (x)
       (let ((tmp-1 x))
         (let ((tmp ($sc-dispatch tmp-1 '(any #(each (any any)) any . each-any))))
           (if (if tmp (apply (lambda (let* x v e1 e2) (and-map identifier? x)) tmp) #f)
               (apply (lambda (let* x v e1 e2)
                        (let f ((bindings (map list x v)))
                          (if (null? bindings)
                              (cons (make-syntax 'let '((top)) '(hygiene guile)) (cons '() (cons e1 e2)))
                              (let ((tmp-1 (list (f (cdr bindings)) (car bindings))))
                                (let ((tmp ($sc-dispatch tmp-1 '(any any))))
                                  (if tmp
                                      (apply (lambda (body binding)
                                               (list (make-syntax 'let '((top)) '(hygiene guile)) (list binding) body))
                                             tmp)
                                      (syntax-violation #f "source expression failed to match any pattern" tmp-1)))))))
                      tmp)
               (syntax-violation #f "source expression failed to match any pattern" tmp-1))))))))

(define quasiquote
  (let ((make-syntax make-syntax))
    (make-syntax-transformer
     'quasiquote
     'macro
     (letrec* ((quasi (lambda (p lev)
                        (let ((tmp p))
                          (let ((tmp-1 ($sc-dispatch
                                        tmp
                                        (list (vector 'free-id (make-syntax 'unquote '((top)) '(hygiene guile))) 'any))))
                            (if tmp-1
                                (apply (lambda (p)
                                         (if (= lev 0)
                                             (list "value" p)
                                             (quasicons
                                              (list "quote" (make-syntax 'unquote '((top)) '(hygiene guile)))
                                              (quasi (list p) (- lev 1)))))
                                       tmp-1)
                                (let ((tmp-1 ($sc-dispatch
                                              tmp
                                              (list (vector
                                                     'free-id
                                                     (make-syntax
                                                      'quasiquote
                                                      (list '(top)
                                                            (vector
                                                             'ribcage
                                                             '#(quasiquote)
                                                             '#((top))
                                                             (vector
                                                              (cons '(hygiene guile)
                                                                    (make-syntax 'quasiquote '((top)) '(hygiene guile))))))
                                                      '(hygiene guile)))
                                                    'any))))
                                  (if tmp-1
                                      (apply (lambda (p)
                                               (quasicons
                                                (list "quote"
                                                      (make-syntax
                                                       'quasiquote
                                                       (list '(top)
                                                             (vector
                                                              'ribcage
                                                              '#(quasiquote)
                                                              '#((top))
                                                              (vector
                                                               (cons '(hygiene guile)
                                                                     (make-syntax 'quasiquote '((top)) '(hygiene guile))))))
                                                       '(hygiene guile)))
                                                (quasi (list p) (+ lev 1))))
                                             tmp-1)
                                      (let ((tmp-1 ($sc-dispatch tmp '(any . any))))
                                        (if tmp-1
                                            (apply (lambda (p q)
                                                     (let ((tmp-1 p))
                                                       (let ((tmp ($sc-dispatch
                                                                   tmp-1
                                                                   (cons (vector
                                                                          'free-id
                                                                          (make-syntax
                                                                           'unquote
                                                                           '((top))
                                                                           '(hygiene guile)))
                                                                         'each-any))))
                                                         (if tmp
                                                             (apply (lambda (p)
                                                                      (if (= lev 0)
                                                                          (quasilist*
                                                                           (map (lambda (tmp-680b775fb37a463-155b)
                                                                                  (list "value"
                                                                                        tmp-680b775fb37a463-155b))
                                                                                p)
                                                                           (quasi q lev))
                                                                          (quasicons
                                                                           (quasicons
                                                                            (list "quote"
                                                                                  (make-syntax
                                                                                   'unquote
                                                                                   '((top))
                                                                                   '(hygiene guile)))
                                                                            (quasi p (- lev 1)))
                                                                           (quasi q lev))))
                                                                    tmp)
                                                             (let ((tmp ($sc-dispatch
                                                                         tmp-1
                                                                         (cons (vector
                                                                                'free-id
                                                                                (make-syntax
                                                                                 'unquote-splicing
                                                                                 '((top))
                                                                                 '(hygiene guile)))
                                                                               'each-any))))
                                                               (if tmp
                                                                   (apply (lambda (p)
                                                                            (if (= lev 0)
                                                                                (quasiappend
                                                                                 (map (lambda (tmp-680b775fb37a463)
                                                                                        (list "value"
                                                                                              tmp-680b775fb37a463))
                                                                                      p)
                                                                                 (quasi q lev))
                                                                                (quasicons
                                                                                 (quasicons
                                                                                  (list "quote"
                                                                                        (make-syntax
                                                                                         'unquote-splicing
                                                                                         '((top))
                                                                                         '(hygiene guile)))
                                                                                  (quasi p (- lev 1)))
                                                                                 (quasi q lev))))
                                                                          tmp)
                                                                   (quasicons (quasi p lev) (quasi q lev))))))))
                                                   tmp-1)
                                            (let ((tmp-1 ($sc-dispatch tmp '#(vector each-any))))
                                              (if tmp-1
                                                  (apply (lambda (x) (quasivector (vquasi x lev))) tmp-1)
                                                  (let ((p tmp)) (list "quote" p)))))))))))))
               (vquasi
                (lambda (p lev)
                  (let ((tmp p))
                    (let ((tmp-1 ($sc-dispatch tmp '(any . any))))
                      (if tmp-1
                          (apply (lambda (p q)
                                   (let ((tmp-1 p))
                                     (let ((tmp ($sc-dispatch
                                                 tmp-1
                                                 (cons (vector
                                                        'free-id
                                                        (make-syntax 'unquote '((top)) '(hygiene guile)))
                                                       'each-any))))
                                       (if tmp
                                           (apply (lambda (p)
                                                    (if (= lev 0)
                                                        (quasilist*
                                                         (map (lambda (tmp-680b775fb37a463)
                                                                (list "value" tmp-680b775fb37a463))
                                                              p)
                                                         (vquasi q lev))
                                                        (quasicons
                                                         (quasicons
                                                          (list "quote"
                                                                (make-syntax 'unquote '((top)) '(hygiene guile)))
                                                          (quasi p (- lev 1)))
                                                         (vquasi q lev))))
                                                  tmp)
                                           (let ((tmp ($sc-dispatch
                                                       tmp-1
                                                       (cons (vector
                                                              'free-id
                                                              (make-syntax 'unquote-splicing '((top)) '(hygiene guile)))
                                                             'each-any))))
                                             (if tmp
                                                 (apply (lambda (p)
                                                          (if (= lev 0)
                                                              (quasiappend
                                                               (map (lambda (tmp-680b775fb37a463-157b)
                                                                      (list "value" tmp-680b775fb37a463-157b))
                                                                    p)
                                                               (vquasi q lev))
                                                              (quasicons
                                                               (quasicons
                                                                (list "quote"
                                                                      (make-syntax
                                                                       'unquote-splicing
                                                                       '((top))
                                                                       '(hygiene guile)))
                                                                (quasi p (- lev 1)))
                                                               (vquasi q lev))))
                                                        tmp)
                                                 (quasicons (quasi p lev) (vquasi q lev))))))))
                                 tmp-1)
                          (let ((tmp-1 ($sc-dispatch tmp '())))
                            (if tmp-1
                                (apply (lambda () '("quote" ())) tmp-1)
                                (syntax-violation #f "source expression failed to match any pattern" tmp))))))))
               (quasicons
                (lambda (x y)
                  (let ((tmp-1 (list x y)))
                    (let ((tmp ($sc-dispatch tmp-1 '(any any))))
                      (if tmp
                          (apply (lambda (x y)
                                   (let ((tmp y))
                                     (let ((tmp-1 ($sc-dispatch tmp '(#(atom "quote") any))))
                                       (if tmp-1
                                           (apply (lambda (dy)
                                                    (let ((tmp x))
                                                      (let ((tmp ($sc-dispatch tmp '(#(atom "quote") any))))
                                                        (if tmp
                                                            (apply (lambda (dx) (list "quote" (cons dx dy))) tmp)
                                                            (if (null? dy) (list "list" x) (list "list*" x y))))))
                                                  tmp-1)
                                           (let ((tmp-1 ($sc-dispatch tmp '(#(atom "list") . any))))
                                             (if tmp-1
                                                 (apply (lambda (stuff) (cons "list" (cons x stuff))) tmp-1)
                                                 (let ((tmp ($sc-dispatch tmp '(#(atom "list*") . any))))
                                                   (if tmp
                                                       (apply (lambda (stuff) (cons "list*" (cons x stuff))) tmp)
                                                       (list "list*" x y)))))))))
                                 tmp)
                          (syntax-violation #f "source expression failed to match any pattern" tmp-1))))))
               (quasiappend
                (lambda (x y)
                  (let ((tmp y))
                    (let ((tmp ($sc-dispatch tmp '(#(atom "quote") ()))))
                      (if tmp
                          (apply (lambda ()
                                   (if (null? x)
                                       '("quote" ())
                                       (if (null? (cdr x))
                                           (car x)
                                           (let ((tmp-1 x))
                                             (let ((tmp ($sc-dispatch tmp-1 'each-any)))
                                               (if tmp
                                                   (apply (lambda (p) (cons "append" p)) tmp)
                                                   (syntax-violation
                                                    #f
                                                    "source expression failed to match any pattern"
                                                    tmp-1)))))))
                                 tmp)
                          (if (null? x)
                              y
                              (let ((tmp-1 (list x y)))
                                (let ((tmp ($sc-dispatch tmp-1 '(each-any any))))
                                  (if tmp
                                      (apply (lambda (p y) (cons "append" (append p (list y)))) tmp)
                                      (syntax-violation #f "source expression failed to match any pattern" tmp-1))))))))))
               (quasilist* (lambda (x y) (let f ((x x)) (if (null? x) y (quasicons (car x) (f (cdr x)))))))
               (quasivector
                (lambda (x)
                  (let ((tmp x))
                    (let ((tmp ($sc-dispatch tmp '(#(atom "quote") each-any))))
                      (if tmp
                          (apply (lambda (x) (list "quote" (list->vector x))) tmp)
                          (let f ((y x)
                                  (k (lambda (ls)
                                       (let ((tmp-1 ls))
                                         (let ((tmp ($sc-dispatch tmp-1 'each-any)))
                                           (if tmp
                                               (apply (lambda (t-680b775fb37a463-15c4)
                                                        (cons "vector" t-680b775fb37a463-15c4))
                                                      tmp)
                                               (syntax-violation
                                                #f
                                                "source expression failed to match any pattern"
                                                tmp-1)))))))
                            (let ((tmp y))
                              (let ((tmp-1 ($sc-dispatch tmp '(#(atom "quote") each-any))))
                                (if tmp-1
                                    (apply (lambda (y)
                                             (k (map (lambda (tmp-680b775fb37a463-15d0)
                                                       (list "quote" tmp-680b775fb37a463-15d0))
                                                     y)))
                                           tmp-1)
                                    (let ((tmp-1 ($sc-dispatch tmp '(#(atom "list") . each-any))))
                                      (if tmp-1
                                          (apply (lambda (y) (k y)) tmp-1)
                                          (let ((tmp-1 ($sc-dispatch tmp '(#(atom "list*") . #(each+ any (any) ())))))
                                            (if tmp-1
                                                (apply (lambda (y z) (f z (lambda (ls) (k (append y ls))))) tmp-1)
                                                (let ((else tmp))
                                                  (let ((tmp x))
                                                    (let ((t-680b775fb37a463-15df tmp))
                                                      (list "list->vector" t-680b775fb37a463-15df)))))))))))))))))
               (emit (lambda (x)
                       (let ((tmp x))
                         (let ((tmp-1 ($sc-dispatch tmp '(#(atom "quote") any))))
                           (if tmp-1
                               (apply (lambda (x) (list (make-syntax 'quote '((top)) '(hygiene guile)) x)) tmp-1)
                               (let ((tmp-1 ($sc-dispatch tmp '(#(atom "list") . each-any))))
                                 (if tmp-1
                                     (apply (lambda (x)
                                              (let ((tmp-1 (map emit x)))
                                                (let ((tmp ($sc-dispatch tmp-1 'each-any)))
                                                  (if tmp
                                                      (apply (lambda (t-680b775fb37a463-15ee)
                                                               (cons (make-syntax 'list '((top)) '(hygiene guile))
                                                                     t-680b775fb37a463-15ee))
                                                             tmp)
                                                      (syntax-violation
                                                       #f
                                                       "source expression failed to match any pattern"
                                                       tmp-1)))))
                                            tmp-1)
                                     (let ((tmp-1 ($sc-dispatch tmp '(#(atom "list*") . #(each+ any (any) ())))))
                                       (if tmp-1
                                           (apply (lambda (x y)
                                                    (let f ((x* x))
                                                      (if (null? x*)
                                                          (emit y)
                                                          (let ((tmp-1 (list (emit (car x*)) (f (cdr x*)))))
                                                            (let ((tmp ($sc-dispatch tmp-1 '(any any))))
                                                              (if tmp
                                                                  (apply (lambda (t-680b775fb37a463-1 t-680b775fb37a463)
                                                                           (list (make-syntax
                                                                                  'cons
                                                                                  '((top))
                                                                                  '(hygiene guile))
                                                                                 t-680b775fb37a463-1
                                                                                 t-680b775fb37a463))
                                                                         tmp)
                                                                  (syntax-violation
                                                                   #f
                                                                   "source expression failed to match any pattern"
                                                                   tmp-1)))))))
                                                  tmp-1)
                                           (let ((tmp-1 ($sc-dispatch tmp '(#(atom "append") . each-any))))
                                             (if tmp-1
                                                 (apply (lambda (x)
                                                          (let ((tmp-1 (map emit x)))
                                                            (let ((tmp ($sc-dispatch tmp-1 'each-any)))
                                                              (if tmp
                                                                  (apply (lambda (t-680b775fb37a463-160e)
                                                                           (cons (make-syntax
                                                                                  'append
                                                                                  '((top))
                                                                                  '(hygiene guile))
                                                                                 t-680b775fb37a463-160e))
                                                                         tmp)
                                                                  (syntax-violation
                                                                   #f
                                                                   "source expression failed to match any pattern"
                                                                   tmp-1)))))
                                                        tmp-1)
                                                 (let ((tmp-1 ($sc-dispatch tmp '(#(atom "vector") . each-any))))
                                                   (if tmp-1
                                                       (apply (lambda (x)
                                                                (let ((tmp-1 (map emit x)))
                                                                  (let ((tmp ($sc-dispatch tmp-1 'each-any)))
                                                                    (if tmp
                                                                        (apply (lambda (t-680b775fb37a463-161a)
                                                                                 (cons (make-syntax
                                                                                        'vector
                                                                                        '((top))
                                                                                        '(hygiene guile))
                                                                                       t-680b775fb37a463-161a))
                                                                               tmp)
                                                                        (syntax-violation
                                                                         #f
                                                                         "source expression failed to match any pattern"
                                                                         tmp-1)))))
                                                              tmp-1)
                                                       (let ((tmp-1 ($sc-dispatch tmp '(#(atom "list->vector") any))))
                                                         (if tmp-1
                                                             (apply (lambda (x)
                                                                      (let ((tmp (emit x)))
                                                                        (let ((t-680b775fb37a463 tmp))
                                                                          (list (make-syntax
                                                                                 'list->vector
                                                                                 '((top))
                                                                                 '(hygiene guile))
                                                                                t-680b775fb37a463))))
                                                                    tmp-1)
                                                             (let ((tmp-1 ($sc-dispatch tmp '(#(atom "value") any))))
                                                               (if tmp-1
                                                                   (apply (lambda (x) x) tmp-1)
                                                                   (syntax-violation
                                                                    #f
                                                                    "source expression failed to match any pattern"
                                                                    tmp)))))))))))))))))))
       (lambda (x)
         (let ((tmp-1 x))
           (let ((tmp ($sc-dispatch tmp-1 '(_ any))))
             (if tmp
                 (apply (lambda (e) (emit (quasi e 0))) tmp)
                 (syntax-violation #f "source expression failed to match any pattern" tmp-1)))))))))

(define call-with-include-port
  (let ((syntax-dirname
         (lambda (stx)
           (letrec* ((src (syntax-source stx)) (filename (if src (assq-ref src 'filename) #f)))
             (if (string? filename) (dirname filename) #f)))))
    (lambda* (filename proc #:key (dirname (syntax-dirname filename) #:dirname))
      "Like @code{call-with-input-file}, except relative paths are\nsearched relative to the @var{dirname} instead of the current working\ndirectory.  Also, @var{filename} can be a syntax object; in that case,\nand if @var{dirname} is not specified, the @code{syntax-source} of\n@var{filename} is used to obtain a base directory for relative file\nnames."
      (let ((filename (syntax->datum filename)))
        (let ((p (open-input-file
                  (if (absolute-file-name? filename)
                      filename
                      (if dirname
                          (in-vicinity dirname filename)
                          (error "attempt to include relative file name but could not determine base dir"))))))
          (let ((enc (file-encoding p)))
            (set-port-encoding! p (let ((t enc)) (if t t "UTF-8")))
            (call-with-values (lambda () (proc p)) (lambda results (close-port p) (apply values results)))))))))

(define include
  (let ((make-syntax make-syntax))
    (make-syntax-transformer
     'include
     'macro
     (lambda (stx)
       (let ((tmp-1 stx))
         (let ((tmp ($sc-dispatch tmp-1 '(_ any))))
           (if tmp
               (apply (lambda (filename)
                        (call-with-include-port
                         filename
                         (lambda (p)
                           (cons (make-syntax 'begin '((top)) '(hygiene guile))
                                 (let lp ()
                                   (let ((x (read-syntax p)))
                                     (if (eof-object? x) '() (cons (datum->syntax filename x) (lp)))))))))
                      tmp)
               (syntax-violation #f "source expression failed to match any pattern" tmp-1))))))))

(define include-from-path
  (let ((make-syntax make-syntax))
    (make-syntax-transformer
     'include-from-path
     'macro
     (lambda (x)
       (let ((tmp-1 x))
         (let ((tmp ($sc-dispatch tmp-1 '(any any))))
           (if tmp
               (apply (lambda (k filename)
                        (let ((fn (syntax->datum filename)))
                          (let ((tmp (datum->syntax
                                      filename
                                      (canonicalize-path
                                       (let ((t (%search-load-path fn)))
                                         (if t
                                             t
                                             (syntax-violation 'include-from-path "file not found in path" x filename)))))))
                            (let ((fn tmp)) (list (make-syntax 'include '((top)) '(hygiene guile)) fn)))))
                      tmp)
               (syntax-violation #f "source expression failed to match any pattern" tmp-1))))))))

(define unquote
  (make-syntax-transformer
   'unquote
   'macro
   (lambda (x) (syntax-violation 'unquote "expression not valid outside of quasiquote" x))))

(define unquote-splicing
  (make-syntax-transformer
   'unquote-splicing
   'macro
   (lambda (x) (syntax-violation 'unquote-splicing "expression not valid outside of quasiquote" x))))

(define make-variable-transformer
  (lambda (proc)
    (if (procedure? proc)
        (let ((trans (lambda (x) (proc x)))) (set-procedure-property! trans 'variable-transformer #t) trans)
        (error "variable transformer not a procedure" proc))))

(define identifier-syntax
  (let ((make-syntax make-syntax))
    (make-syntax-transformer
     'identifier-syntax
     'macro
     (lambda (xx)
       (let ((tmp-1 xx))
         (let ((tmp ($sc-dispatch tmp-1 '(_ any))))
           (if tmp
               (apply (lambda (e)
                        (list (make-syntax 'lambda '((top)) '(hygiene guile))
                              (list (make-syntax 'x '((top)) '(hygiene guile)))
                              (vector
                               (cons (make-syntax 'macro-type '((top)) '(hygiene guile))
                                     (make-syntax
                                      'identifier-syntax
                                      (list '(top)
                                            (vector
                                             'ribcage
                                             '#(identifier-syntax)
                                             '#((top))
                                             (vector
                                              (cons '(hygiene guile)
                                                    (make-syntax 'identifier-syntax '((top)) '(hygiene guile))))))
                                      '(hygiene guile))))
                              (list (make-syntax 'syntax-case '((top)) '(hygiene guile))
                                    (make-syntax 'x '((top)) '(hygiene guile))
                                    '()
                                    (list (make-syntax 'id '((top)) '(hygiene guile))
                                          (list (make-syntax 'identifier? '((top)) '(hygiene guile))
                                                (list (make-syntax 'syntax '((top)) '(hygiene guile))
                                                      (make-syntax 'id '((top)) '(hygiene guile))))
                                          (list (make-syntax 'syntax '((top)) '(hygiene guile)) e))
                                    (list (list (make-syntax '_ '((top)) '(hygiene guile))
                                                (make-syntax 'x '((top)) '(hygiene guile))
                                                (make-syntax '... '((top)) '(hygiene guile)))
                                          (list (make-syntax 'syntax '((top)) '(hygiene guile))
                                                (cons e
                                                      (list (make-syntax 'x '((top)) '(hygiene guile))
                                                            (make-syntax '... '((top)) '(hygiene guile)))))))))
                      tmp)
               (let ((tmp ($sc-dispatch
                           tmp-1
                           (list '_
                                 '(any any)
                                 (list (list (vector 'free-id (make-syntax 'set! '((top)) '(hygiene guile))) 'any 'any)
                                       'any)))))
                 (if (if tmp (apply (lambda (id exp1 var val exp2) (if (identifier? id) (identifier? var) #f)) tmp) #f)
                     (apply (lambda (id exp1 var val exp2)
                              (list (make-syntax 'make-variable-transformer '((top)) '(hygiene guile))
                                    (list (make-syntax 'lambda '((top)) '(hygiene guile))
                                          (list (make-syntax 'x '((top)) '(hygiene guile)))
                                          (vector
                                           (cons (make-syntax 'macro-type '((top)) '(hygiene guile))
                                                 (make-syntax 'variable-transformer '((top)) '(hygiene guile))))
                                          (list (make-syntax 'syntax-case '((top)) '(hygiene guile))
                                                (make-syntax 'x '((top)) '(hygiene guile))
                                                (list (make-syntax 'set! '((top)) '(hygiene guile)))
                                                (list (list (make-syntax 'set! '((top)) '(hygiene guile)) var val)
                                                      (list (make-syntax 'syntax '((top)) '(hygiene guile)) exp2))
                                                (list (cons id
                                                            (list (make-syntax 'x '((top)) '(hygiene guile))
                                                                  (make-syntax '... '((top)) '(hygiene guile))))
                                                      (list (make-syntax 'syntax '((top)) '(hygiene guile))
                                                            (cons exp1
                                                                  (list (make-syntax 'x '((top)) '(hygiene guile))
                                                                        (make-syntax '... '((top)) '(hygiene guile))))))
                                                (list id
                                                      (list (make-syntax 'identifier? '((top)) '(hygiene guile))
                                                            (list (make-syntax 'syntax '((top)) '(hygiene guile)) id))
                                                      (list (make-syntax 'syntax '((top)) '(hygiene guile)) exp1))))))
                            tmp)
                     (syntax-violation #f "source expression failed to match any pattern" tmp-1))))))))))

(define define*
  (let ((make-syntax make-syntax))
    (make-syntax-transformer
     'define*
     'macro
     (lambda (x)
       (let ((tmp-1 x))
         (let ((tmp ($sc-dispatch tmp-1 '(_ (any . any) any . each-any))))
           (if tmp
               (apply (lambda (id args b0 b1)
                        (list (make-syntax 'define '((top)) '(hygiene guile))
                              id
                              (cons (make-syntax 'lambda* '((top)) '(hygiene guile)) (cons args (cons b0 b1)))))
                      tmp)
               (let ((tmp ($sc-dispatch tmp-1 '(_ any any))))
                 (if (if tmp (apply (lambda (id val) (identifier? id)) tmp) #f)
                     (apply (lambda (id val) (list (make-syntax 'define '((top)) '(hygiene guile)) id val)) tmp)
                     (syntax-violation #f "source expression failed to match any pattern" tmp-1))))))))))

