;; ------------------------------------------------------------
;; StackLend
;; DAO-governed lending + borrowing protocol with collateral,
;; interest, liquidation, and treasury revenue.
;; Clarity v2 reference implementation (simplified).
;; ------------------------------------------------------------
;; WARNING: Reference code - audit, test with Clarinet, adapt for production.
;; ------------------------------------------------------------
;; ------------------------------------------------------------

(define-constant ERR-NOT-AUTH       (err u100))
(define-constant ERR-NOT-FOUND      (err u101))
(define-constant ERR-INSUFFICIENT   (err u102))
(define-constant ERR-UNDERCOLLATERAL (err u103))
(define-constant ERR-BAD-INPUT      (err u104))
(define-constant ERR-ALREADY        (err u105))

(define-data-var owner principal tx-sender)
(define-data-var treasury principal tx-sender)

;; DAO params (modifiable by admin/DAO)
(define-data-var collateral-ratio-bps uint u15000) ;; 150% collateral ratio
(define-data-var liquidation-ratio-bps uint u12000) ;; below 120% -> liquidation
(define-data-var interest-rate-bps uint u500) ;; 5% interest (annualized, simplified)
(define-data-var liquidation-bonus-bps uint u500) ;; 5% bonus to liquidator
(define-data-var treasury-fee-bps uint u100) ;; 1% fee to treasury

;; User positions -------------------------------------------------------------
(define-map positions { who: principal }
  {
    collateral: uint, ;; amount of STX locked
    debt: uint,       ;; outstanding borrowed STX
    last-update: uint ;; block height for interest accrual
  }
)

;; Helpers -------------------------------------------------------------------
(define-read-only (is-owner (p principal))
  (is-eq p (var-get owner))
)

(define-private (u-percent (amount uint) (bps uint))
  (/ (* amount bps) u10000)
)

(define-private (accrue-interest (pos { collateral: uint, debt: uint, last-update: uint }))
  (let ((elapsed (- stacks-block-height (get last-update pos)))
        (rate (var-get interest-rate-bps)))
    (if (<= (get debt pos) u0)
        pos
        (let ((interest (u-percent (get debt pos) (* rate elapsed))))
          (merge pos { debt: (+ (get debt pos) interest), last-update: stacks-block-height })
        )
    )
  )
)

(define-private (update-position (who principal))
  (let ((p (map-get? positions { who: who })))
    (if (is-none p) 
        none
        (let ((pos (unwrap-panic p)))
          (let ((np (accrue-interest pos)))
            (map-set positions { who: who } np)
            (some np)
          )
        )
    )
  )
)

;; Collateral deposit/withdraw ------------------------------------------------
(define-public (deposit-collateral (amount uint))
  (begin
    (asserts! (> amount u0) ERR-BAD-INPUT)
    (let ((p (map-get? positions { who: tx-sender })))
      (if (is-none p)
          (map-set positions { who: tx-sender } { collateral: amount, debt: u0, last-update: stacks-block-height })
          (let ((pos (unwrap-panic p)))
            (map-set positions { who: tx-sender } { collateral: (+ (get collateral pos) amount), debt: (get debt pos), last-update: stacks-block-height })
          )
      )
    )
    (ok true)
  )
)

(define-public (withdraw-collateral (amount uint))
  (let ((np (update-position tx-sender)))
    (asserts! (is-some np) ERR-NOT-FOUND)
    (let ((pos (unwrap-panic np)))
      (asserts! (>= (get collateral pos) amount) ERR-INSUFFICIENT)
      (let ((new-collateral (- (get collateral pos) amount))
            (debt (get debt pos)))
        (asserts! (or (<= debt u0) (>= (* new-collateral u10000) (* debt (var-get collateral-ratio-bps)))) ERR-UNDERCOLLATERAL)
        (begin
          (map-set positions { who: tx-sender } { collateral: new-collateral, debt: debt, last-update: stacks-block-height })
          (try! (stx-transfer? amount tx-sender tx-sender))
          (ok true)
        )
      )
    )
  )
)

;; Borrow & Repay -------------------------------------------------------------
(define-public (borrow (amount uint))
  (let ((np (update-position tx-sender)))
    (asserts! (is-some np) ERR-NOT-FOUND)
    (let ((pos (unwrap-panic np)))
      (let ((new-debt (+ (get debt pos) amount)))
        (asserts! (<= (* new-debt (var-get collateral-ratio-bps)) (* (get collateral pos) u10000)) ERR-UNDERCOLLATERAL)
        (begin
          (map-set positions { who: tx-sender } { collateral: (get collateral pos), debt: new-debt, last-update: stacks-block-height })
          (try! (stx-transfer? amount tx-sender tx-sender))
          (ok true)
        )
      )
    )
  )
)

(define-public (repay (amount uint))
  (let ((p (map-get? positions { who: tx-sender })))
    (asserts! (is-some p) ERR-NOT-FOUND)
    (let ((pos (unwrap-panic p)))
      (let ((new-debt (if (> (get debt pos) amount) (- (get debt pos) amount) u0)))
        (map-set positions { who: tx-sender } { collateral: (get collateral pos), debt: new-debt, last-update: stacks-block-height })
        (ok true)
      )
    )
  )
)

;; Liquidation ---------------------------------------------------------------
(define-public (liquidate (borrower principal))
  (let ((np (update-position borrower)))
    (asserts! (is-some np) ERR-NOT-FOUND)
    (let ((pos (unwrap-panic np)))
      (let ((coll (get collateral pos)) (debt (get debt pos)))
        (asserts! (> debt u0) ERR-BAD-INPUT)
        (asserts! (< (* coll u10000) (* debt (var-get liquidation-ratio-bps))) ERR-UNDERCOLLATERAL)
        (let ((bonus (u-percent coll (var-get liquidation-bonus-bps))))
          (map-set positions { who: borrower } { collateral: u0, debt: u0, last-update: stacks-block-height })
          (try! (stx-transfer? (+ coll bonus) tx-sender tx-sender))
          (ok true)
        )
      )
    )
  )
)

;; DAO Controls --------------------------------------------------------------
(define-public (set-param (k (string-ascii 20)) (v uint))
  (begin
    (asserts! (is-owner tx-sender) ERR-NOT-AUTH)
    (asserts! (and (>= v u0) (< v u10000)) ERR-BAD-INPUT)
    (asserts!
      (or
        (and (is-eq k "collateral-ratio-bps") (var-set collateral-ratio-bps v) true)
        (and (is-eq k "liquidation-ratio-bps") (var-set liquidation-ratio-bps v) true)
        (and (is-eq k "interest-rate-bps") (var-set interest-rate-bps v) true)
        (and (is-eq k "liquidation-bonus-bps") (var-set liquidation-bonus-bps v) true)
        (and (is-eq k "treasury-fee-bps") (var-set treasury-fee-bps v) true))
      ERR-BAD-INPUT)
    (ok true)
  )
)

;; Read-only views ------------------------------------------------------------
(define-read-only (get-position (who principal))
  (map-get? positions { who: who })
)
(define-read-only (get-params)
  {
    collateral-ratio-bps: (var-get collateral-ratio-bps),
    liquidation-ratio-bps: (var-get liquidation-ratio-bps),
    interest-rate-bps: (var-get interest-rate-bps),
    liquidation-bonus-bps: (var-get liquidation-bonus-bps),
    treasury-fee-bps: (var-get treasury-fee-bps)
  }
)

;; ------------------------------------------------------------
;; END StackLend
;; ------------------------------------------------------------
