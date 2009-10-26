;;; Guile VM program functions

;;; Copyright (C) 2001, 2009 Free Software Foundation, Inc.
;;;
;;; This library is free software; you can redistribute it and/or
;;; modify it under the terms of the GNU Lesser General Public
;;; License as published by the Free Software Foundation; either
;;; version 3 of the License, or (at your option) any later version.
;;;
;;; This library is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;; Lesser General Public License for more details.
;;;
;;; You should have received a copy of the GNU Lesser General Public
;;; License along with this library; if not, write to the Free Software
;;; Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA

;;; Code:

(define-module (system vm program)
  #:use-module (system base pmatch)
  #:use-module (ice-9 optargs)
  #:export (make-program

            make-binding binding:name binding:boxed? binding:index
            binding:start binding:end

            source:addr source:line source:column source:file
            program-sources program-source
            program-properties program-property program-documentation
            program-name

            program-bindings program-bindings-by-index program-bindings-for-ip
            program-arities program-arity arity:start arity:end

            arity:nreq arity:nopt arity:rest? arity:kw arity:allow-other-keys?

            program-arguments program-lambda-list
            
            program-meta
            program-objcode program? program-objects
            program-module program-base program-free-variables))

(load-extension "libguile" "scm_init_programs")

(define (make-binding name boxed? index start end)
  (list name boxed? index start end))
(define (binding:name b) (list-ref b 0))
(define (binding:boxed? b) (list-ref b 1))
(define (binding:index b) (list-ref b 2))
(define (binding:start b) (list-ref b 3))
(define (binding:end b) (list-ref b 4))

(define (source:addr source)
  (car source))
(define (source:file source)
  (cadr source))
(define (source:line source)
  (caddr source))
(define (source:column source)
  (cdddr source))

(define (program-property prog prop)
  (assq-ref (program-properties prog) prop))

(define (program-documentation prog)
  (assq-ref (program-properties prog) 'documentation))

(define (collapse-locals locs)
  (let lp ((ret '()) (locs locs))
    (if (null? locs)
        (map cdr (sort! ret 
                        (lambda (x y) (< (car x) (car y)))))
        (let ((b (car locs)))
          (cond
           ((assv-ref ret (binding:index b))
            => (lambda (bindings)
                 (append! bindings (list b))
                 (lp ret (cdr locs))))
           (else
            (lp (acons (binding:index b) (list b) ret)
                (cdr locs))))))))

;; returns list of list of bindings
;; (list-ref ret N) == bindings bound to the Nth local slot
(define (program-bindings-by-index prog)
  (cond ((program-bindings prog) => collapse-locals)
        (else '())))

(define (program-bindings-for-ip prog ip)
  (let lp ((in (program-bindings-by-index prog)) (out '()))
    (if (null? in)
        (reverse out)
        (lp (cdr in)
            (let inner ((binds (car in)))
              (cond ((null? binds) out)
                    ((<= (binding:start (car binds))
                         ip
                         (binding:end (car binds)))
                     (cons (car binds) out))
                    (else (inner (cdr binds)))))))))

(define (arity:start a)
  (pmatch a ((,start ,end . _) start) (else (error "bad arity" a))))
(define (arity:end a)
  (pmatch a ((,start ,end . _) end) (else (error "bad arity" a))))
(define (arity:nreq a)
  (pmatch a ((_ _ ,nreq . _) nreq) (else 0)))
(define (arity:nopt a)
  (pmatch a ((_ _ ,nreq ,nopt . _) nopt) (else 0)))
(define (arity:rest? a)
  (pmatch a ((_ _ ,nreq ,nopt ,rest? . _) rest?) (else #f)))
(define (arity:kw a)
  (pmatch a ((_ _ ,nreq ,nopt ,rest? (_ . ,kw)) kw) (else '())))
(define (arity:allow-other-keys? a)
  (pmatch a ((_ _ ,nreq ,nopt ,rest? (,aok . ,kw)) aok) (else #f)))

(define (program-arity prog ip)
  (let ((arities (program-arities prog)))
    (and arities
         (let lp ((arities arities))
           (cond ((null? arities) #f)
                 ((and (< (arity:start (car arities)) ip)
                       (<= ip (arity:end (car arities))))
                  (car arities))
                 (else (lp (cdr arities))))))))

(define (arglist->arguments arglist)
  (pmatch arglist
    ((,req ,opt ,keyword ,allow-other-keys? ,rest . ,extents)
     `((required . ,req)
       (optional . ,opt)
       (keyword . ,keyword)
       (allow-other-keys? . ,allow-other-keys?)
       (rest . ,rest)
       (extents . ,extents)))
    (else #f)))

(define (arity->arguments prog arity)
  (define var-by-index
    (let ((rbinds (map (lambda (x)
                         (cons (binding:index x) (binding:name x)))
                       (program-bindings-for-ip prog
                                                (arity:start arity)))))
      (lambda (i)
        (assv-ref rbinds i))))

  (let lp ((nreq (arity:nreq arity)) (req '())
           (nopt (arity:nopt arity)) (opt '())
           (rest? (arity:rest? arity)) (rest #f)
           (n 0))
    (cond
     ((< 0 nreq)
      (lp (1- nreq) (cons (var-by-index n) req)
          nopt opt rest? rest (1+ n)))
     ((< 0 nopt)
      (lp nreq req
          (1- nopt) (cons (var-by-index n) opt)
          rest? rest (1+ n)))
     (rest?
      (lp nreq req nopt opt
          #f (var-by-index n)
          (1+ n)))
     (else
      `((required . ,(reverse req))
        (optional . ,(reverse opt))
        (keyword . ,(arity:kw arity))
        (allow-other-keys? . ,(arity:allow-other-keys? arity))
        (rest . ,rest))))))

(define* (program-arguments prog #:optional ip)
  (let ((arity (program-arity prog ip)))
    (and arity
        (arity->arguments prog arity))))

(define* (program-lambda-list prog #:optional ip)
  (and=> (program-arguments prog ip) arguments->lambda-list))

(define (arguments->lambda-list arguments)
  (let ((req (or (assq-ref arguments 'required) '()))
        (opt (or (assq-ref arguments 'optional) '()))
        (key (or (assq-ref arguments 'keyword) '()))
        (rest (or (assq-ref arguments 'rest) '())))
    `(,@req
      ,@(if (pair? opt) (cons #:optional opt) '())
      ,@(if (pair? key) (cons #:key key) '())
      . ,rest)))

(define (write-program prog port)
  (format port "#<program ~a~a>"
          (or (program-name prog)
              (and=> (program-source prog 0)
                     (lambda (s)
                       (format #f "~a at ~a:~a:~a"
                               (number->string (object-address prog) 16)
                               (or (source:file s) "<unknown port>")
                               (source:line s) (source:column s))))
              (number->string (object-address prog) 16))
          (let ((arities (program-arities prog)))
            (if (null? arities)
                ""
                (string-append
                 " " (string-join (map (lambda (a)
                                         (object->string
                                          (arguments->lambda-list
                                           (arity->arguments prog a))))
                                       arities)
                                  " | "))))))

