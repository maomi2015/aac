#lang racket

; CESK*Ξ machine for ANF Scheme (lambda if set! let letrec)
; local Ξ

;; helpers
(define ns (make-base-namespace))
;;

;; machine
(struct ev (e ρ σ κ Ξ) #:transparent)
(struct ko (κ v σ Ξ) #:transparent)
(struct ctx (f ρ σ) #:transparent)
(struct letk (x e ρ) #:transparent)
(struct letreck (a e ρ) #:transparent)
(struct haltk () #:transparent)
(struct clo (λ ρ) #:transparent)

(define (make-step α γ ⊥ ⊔ alloc true? false?)
  (let* ((env-bind
          (lambda (ρ x a)
            (hash-set ρ x a)))
         (env-lookup
          (lambda (ρ x)
            (hash-ref ρ x)))
         (store-alloc
          (lambda (σ a v)
            (hash-set σ a (⊔ (hash-ref σ a ⊥) v))))
         (store-update
          (lambda (σ a v)
            (hash-set σ a (⊔ (hash-ref σ a) v))))
         (store-lookup
          (lambda (σ a)
            (hash-ref σ a)))
         (stack-alloc
          (lambda (Ξ τ κ)
            (hash-set Ξ τ (set-union (hash-ref Ξ τ (set)) (set κ)))))
         (stack-lookup
          (lambda (Ξ τ)
            (hash-ref Ξ τ)))
         (ae?
          (lambda (e)
            (match e
              ((? symbol? e) #t)
              (`(lambda ,_ ,_) #t)
              ((? boolean? e) #t)
              ((? number? e) #t)
              ((? string? e) #t)
              (_ #f))))
         (eval-atom
          (lambda (ae ρ σ)
            (match ae
              ((? symbol? ae) (store-lookup σ (env-lookup ρ ae)))
              (`(lambda ,x ,e0) (α (clo ae ρ)))
              (_ (α ae))))))
    (lambda (s)
      (match s
        ((ev (? ae? ae) ρ σ κ Ξ)
         (set (ko κ (eval-atom ae ρ σ) σ Ξ)))
        ((ev `(if ,ae ,e1 ,e2) ρ σ κ Ξ)
         (let ((v (eval-atom ae ρ σ)))
           (set-union (if (true? v)
                          (set (ev e1 ρ σ κ Ξ))
                          (set))
                      (if (false? v)
                          (set (ev e2 ρ σ κ Ξ))
                          (set)))))
        ((ev (and `(let ((,x ,e0)) ,e1) e) ρ σ κ Ξ)
         (let ((τ (ctx e ρ σ)))
           (set (ev e0 ρ σ (cons (letk x e1 ρ) τ) (stack-alloc Ξ τ κ)))))
        ((ev (and `(letrec ((,x ,e0)) ,e1) e) ρ σ κ Ξ)
         (let* ((a (alloc x))
                (ρ* (env-bind ρ x a))
                (τ (ctx e ρ σ)))
           (set (ev e0 ρ* σ (cons (letreck a e1 ρ*) τ) (stack-alloc Ξ τ κ)))))
        ((ev `(set! ,x ,ae) ρ σ κ Ξ)
         (let* ((v (eval-atom ae))
                (a (env-lookup ρ x))
                (σ* (store-update σ a v)))
           (set (ko κ v σ* Ξ))))
        ((ev `(,rator . ,rands) ρ σ κ Ξ)
         (let ((v (eval-atom rator ρ σ)))
           (let loop ((rands rands) (rvs '()))
             (if (null? rands)
                 (for/fold ((states (set))) ((w (γ v)))
                   (match w
                     ((clo `(lambda ,x ,e0) ρ**)
                      (let loop ((x x) (vs (reverse rvs)) (ρ* ρ**) (σ* σ))
                        (match x
                          ('() (set-union states (set (ev e0 ρ* σ* κ Ξ))))
                          ((cons x xs)
                           (if (null? vs)
                               (set)
                               (let ((a (alloc x)))
                                 (loop xs (cdr vs) (env-bind ρ* x a) (store-alloc σ* a (car vs)))))))))
                     ((? procedure? w)
                      (set-union states (set (ko κ (apply w (reverse rvs)) σ Ξ))))
                     (_ (set))))
                 (let ((v (eval-atom (car rands) ρ σ)))
                   (loop (cdr rands) (cons v rvs)))))))
         ((ko (cons (letk x e ρ) τ) v σ Ξ)
          (let* ((a (alloc x))
                 (ρ* (env-bind ρ x a))
                 (σ* (store-alloc σ a v))
                 (κs (stack-lookup Ξ τ)))
            (list->set (set-map κs (lambda (κ) (ev e ρ* σ* κ Ξ))))))
        ((ko (cons (letreck a e ρ) τ) v σ Ξ)
         (let ((σ* (store-alloc σ a v))
               (κs (stack-lookup Ξ τ)))
           (list->set (set-map κs (lambda (κ) (ev e ρ σ* κ Ξ))))))
        ((ko (cons (haltk) _) v _ _)
         (set))))))

(define (inject e global)
  (let loop ((global global) (ρ (hash)) (σ (hash)))
    (match global
      ('()
       (ev e ρ σ `(,(haltk) . #f) (hash)))
      ((cons (cons x v) r)
       (let ((a (gensym x)))
         (loop r (hash-set ρ x a) (hash-set σ a v)))))))
                                      
(define (run s step)
  (let loop ((visited (set))
             (todo (set s)))
    (if (set-empty? todo)
        (begin
          (display "states ") (display (set-count visited)) (display " result ")
          (for/set ((s visited) #:when (match s ((ko (cons (haltk) _) _ _ _) #t) (_ #f)))
            (match-let (((ko _ v _ _) s))
              v)))
        (let ((s (set-first todo)))
          (if (set-member? visited s)
              (loop visited (set-rest todo))
              (loop (set-add visited s) (set-union (step s) (set-rest todo))))))))
;;

;; allocators
(define (conc-alloc x)
  (gensym x))

(define (mono-alloc x)
  x)
;;

;; conc lattice
(define (conc-α v)
  v)

(define (conc-γ v)
  (set v))

(define conc-⊥ (gensym '⊥))

(define (conc-⊔ v1 v2)
  (match* (v1 v2)
    (((== conc-⊥) v) v)
    ((v (== conc-⊥)) v)
    ((_ _) (error "concrete join" v1 v2))))

(define (conc-true? v)
  v)

(define (conc-false? v)
  (not v))

(define conc-step (make-step conc-α conc-γ conc-⊥ conc-⊔ conc-alloc conc-true? conc-false?))

(define conc-global
  `((= . ,(conc-α =))
    (< . ,(conc-α <))
    (<= . ,(conc-α <=))
    (+ . ,(conc-α +))
    (- . ,(conc-α -))
    (* . ,(conc-α *))
    (not . ,(conc-α not))))

(define (conc-eval e)
  (run (inject e conc-global) conc-step))
;;

;; type lattice
(define (type-α v)
  (cond
    ((number? v) (set 'NUM))
    ((boolean? v) (set 'BOOL))
    ((string? v) (set 'STR))
    ((clo? v) (set v))
    ((procedure? v) (set v))
    (else (error "bwek" v))))

(define (type-γ v)
  v)

(define type-⊥ (set))

(define type-⊔ set-union)

(define (type-true? v)
  #t)

(define (type-false? v)
  #t)

(define type-step (make-step type-α type-γ type-⊥ type-⊔ mono-alloc type-true? type-false?))

(define type-global
  `((= . ,(type-α (lambda (v1 v2)
                    (set 'BOOL))))
    (< . ,(type-α (lambda (v1 v2)
                    (set 'BOOL))))
    (<= . ,(type-α (lambda (v1 v2)
                    (set 'BOOL))))
    (+ . ,(type-α (lambda (v1 v2)
                    (set 'NUM))))
    (- . ,(type-α (lambda (v1 v2)
                    (set 'NUM))))
    (* . ,(type-α (lambda (v1 v2)
                    (set 'NUM))))
    (not . ,(type-α (lambda (v)
                      (set 'BOOL))))))

(define (type-eval e)
  (run (inject e type-global) type-step))
;;

(define sq '((lambda (x) (* x x)) 8))
(define loopy1 '(letrec ((f (lambda () (f)))) (f)))
(define loopy2 '((lambda (x) (x x)) (lambda (y) (y y))))
(define safeloopy1 '(letrec ((count (lambda (n) (let ((t (= n 0))) (if t 123 (let ((u (- n 1))) (let ((v (count u))) v))))))) (count 8)))
(define fac '(letrec ((fac (lambda (n) (let ((t (= n 0))) (if t 1 (let ((u (- n 1))) (let ((v (fac u))) (* n v)))))))) (fac 8)))
(define fib '(letrec ((_fib0 (lambda (_n1) (let ((_p2 (< _n1 2))) (if _p2 _n1 (let ((_p3 (- _n1 1))) (let ((_p4 (_fib0 _p3))) (let ((_p5 (- _n1 2))) (let ((_p6 (_fib0 _p5))) (+ _p4 _p6)))))))))) (_fib0 8)))
(define blur '(let ((_id0 (lambda (_x1) _x1))) (let ((_blur2 (lambda (_y3) _y3))) (letrec ((_lp4 (lambda (_a5 _n6) (let ((_p9 (<= _n6 1))) (if _p9 (_id0 _a5) (let ((_p10 (_blur2 _id0))) (let ((_r7 (_p10 #t))) (let ((_p11 (_blur2 _id0))) (let ((_s8 (_p11 #f))) (let ((_p12 (_blur2 _lp4))) (let ((_p13 (- _n6 1))) (let ((_p14 (_p12 _s8 _p13))) (not _p14))))))))))))) (_lp4 #f 2)))))
(define churchNums '(let ((_plus0 (lambda (_n11 _n22) (lambda (_f3) (lambda (_x4) (let ((_p38 (_n11 _f3))) (let ((_p39 (_n22 _f3))) (let ((_p40 (_p39 _x4))) (_p38 _p40))))))))) (let ((_mult5 (lambda (_n16 _n27) (lambda (_f8) (let ((_p41 (_n16 _f8))) (_n27 _p41)))))) (let ((_pred9 (lambda (_n10) (lambda (_f11) (lambda (_x12) (let ((_p43 (_n10 (lambda (_g13) (lambda (_h14) (let ((_p42 (_g13 _f11))) (_h14 _p42))))))) (let ((_p44 (_p43 (lambda (_ignored15) _x12)))) (_p44 (lambda (_id16) _id16))))))))) (let ((_sub17 (lambda (_n118 _n219) (let ((_p45 (_n219 _pred9))) (_p45 _n118))))) (let ((_church020 (lambda (_f21) (lambda (_x22) _x22)))) (let ((_church123 (lambda (_f24) (lambda (_x25) (_f24 _x25))))) (let ((_church226 (lambda (_f27) (lambda (_x28) (let ((_p46 (_f27 _x28))) (_f27 _p46)))))) (let ((_church329 (lambda (_f30) (lambda (_x31) (let ((_p47 (_f30 _x31))) (let ((_p48 (_f30 _p47))) (_f30 _p48))))))) (let ((_church0?32 (lambda (_n33) (let ((_p49 (_n33 (lambda (_x34) #f)))) (_p49 #t))))) (letrec ((_church=?35 (lambda (_n136 _n237) (let ((_p50 (_church0?32 _n136))) (if _p50 (_church0?32 _n237) (let ((_p51 (_church0?32 _n237))) (if _p51 #f (let ((_p52 (_sub17 _n136 _church123))) (let ((_p53 (_sub17 _n237 _church123))) (_church=?35 _p52 _p53)))))))))) (let ((_p54 (_plus0 _church123 _church329))) (let ((_p55 (_mult5 _church226 _p54))) (let ((_p56 (_mult5 _church226 _church123))) (let ((_p57 (_mult5 _church226 _church329))) (let ((_p58 (_plus0 _p56 _p57))) (_church=?35 _p55 _p58)))))))))))))))))
(define eta '(let ((_do-something0 (lambda () 10))) (let ((_id1 (lambda (_y2) (let ((_tmp13 (_do-something0))) _y2)))) (let ((_p7 (_id1 (lambda (_a5) _a5)))) (let ((_tmp24 (_p7 #t))) (let ((_p8 (_id1 (lambda (_b6) _b6)))) (_p8 #f)))))))
(define gcipd '(let ((_id0 (lambda (_x1) _x1))) (letrec ((_f2 (lambda (_n3) (let ((_p6 (<= _n3 1))) (if _p6 1 (let ((_p7 (- _n3 1))) (let ((_p8 (_f2 _p7))) (* _n3 _p8)))))))) (letrec ((_g4 (lambda (_n5) (let ((_p9 (<= _n5 1))) (if _p9 1 (let ((_p10 (* _n5 _n5))) (let ((_p11 (- _n5 1))) (let ((_p12 (_g4 _p11))) (+ _p10 _p12))))))))) (let ((_p13 (_id0 _f2))) (let ((_p14 (_p13 3))) (let ((_p15 (_id0 _g4))) (let ((_p16 (_p15 4))) (+ _p14 _p16)))))))))
(define kcfa2 '(let ((_f10 (lambda (_x12) (let ((_f23 (lambda (_x26) (let ((_z7 (lambda (_y18 _y29) _y18))) (_z7 _x12 _x26))))) (let ((_b4 (_f23 #t))) (let ((_c5 (_f23 #f))) (_f23 #t))))))) (let ((_a1 (_f10 #t))) (_f10 #f))))
(define kcfa3 '(let ((_f10 (lambda (_x12) (let ((_f23 (lambda (_x25) (let ((_f36 (lambda (_x38) (let ((_z9 (lambda (_y110 _y211 _y312) _y110))) (_z9 _x12 _x25 _x38))))) (let ((_c7 (_f36 #t))) (_f36 #f)))))) (let ((_b4 (_f23 #t))) (_f23 #f)))))) (let ((_a1 (_f10 #t))) (_f10 #f))))
(define loop2 '(letrec ((_lp10 (lambda (_i1 _x2) (let ((_a3 (= 0 _i1))) (if _a3 _x2 (letrec ((_lp24 (lambda (_j5 _f6 _y7) (let ((_b8 (= 0 _j5))) (if _b8 (let ((_p10 (- _i1 1))) (_lp10 _p10 _y7)) (let ((_p11 (- _j5 1))) (let ((_p12 (_f6 _y7))) (_lp24 _p11 _f6 _p12)))))))) (_lp24 10 (lambda (_n9) (+ _n9 _i1)) _x2))))))) (_lp10 10 0)))
(define mj09 '(let ((_h0 (lambda (_b1) (let ((_g2 (lambda (_z3) _z3))) (let ((_f4 (lambda (_k5) (if _b1 (_k5 1) (_k5 2))))) (let ((_y6 (_f4 (lambda (_x7) _x7)))) (_g2 _y6))))))) (let ((_x8 (_h0 #t))) (let ((_y9 (_h0 #f))) _y9))))
(define rotate '(letrec ((_rotate0 (lambda (_n1 _x2 _y3 _z4) (let ((_p5 (= _n1 0))) (if _p5 _x2 (let ((_p6 (- _n1 1))) (_rotate0 _p6 _y3 _z4 _x2))))))) (_rotate0 41 5 #t "hallo")))
(define sat '(let ((_phi5 (lambda (_x16 _x27 _x38 _x49) (let ((__t010 _x16)) (let ((_p23 (if __t010 __t010 (let ((__t111 (not _x27))) (if __t111 __t111 (not _x38)))))) (if _p23 (let ((__t212 (not _x27))) (let ((_p24 (if __t212 __t212 (not _x38)))) (if _p24 (let ((__t313 _x49)) (if __t313 __t313 _x27)) #f))) #f)))))) (let ((_try14 (lambda (_f15) (let ((__t416 (_f15 #t))) (if __t416 __t416 (_f15 #f)))))) (let ((_sat-solve-417 (lambda (_p18) (_try14 (lambda (_n119) (_try14 (lambda (_n220) (_try14 (lambda (_n321) (_try14 (lambda (_n422) (_p18 _n119 _n220 _n321 _n422)))))))))))) (_sat-solve-417 _phi5)))))

(conc-eval sq)
(type-eval sq)

(type-eval loopy1)

(type-eval loopy2)

(time
 (conc-eval safeloopy1)
 (type-eval safeloopy1)
 (conc-eval blur)
 (type-eval blur)
 (conc-eval fac)
 (type-eval fac)
 (conc-eval fib)
 (type-eval fib)
 (conc-eval eta)
 (type-eval eta)
 (conc-eval gcipd)
 (type-eval gcipd)
 (conc-eval kcfa2)
 (type-eval kcfa2)
 (conc-eval kcfa3)
 (type-eval kcfa3)
 (conc-eval loop2)
 (type-eval loop2)
 (conc-eval mj09)
 (type-eval mj09)
 (conc-eval rotate)
 (type-eval rotate)
 )

;(conc-eval sat)
;(type-eval sat)

;(conc-eval churchNums)
;(type-eval churchNums)