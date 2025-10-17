;; DAO Treasury Contract - Community Investment Fund Management

(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-INSUFFICIENT-FUNDS (err u201))
(define-constant ERR-INVALID-AMOUNT (err u202))
(define-constant ERR-INVESTMENT-NOT-FOUND (err u203))
(define-constant ERR-TREASURY-LOCKED (err u206))

(define-constant CONTRACT-OWNER tx-sender)

(define-data-var total-treasury uint u0)
(define-data-var investment-counter uint u0)
(define-data-var emergency-lock bool false)

(define-map investments uint {
    investment-name: (string-ascii 50),
    allocated-amount: uint,
    current-value: uint,
    start-block: uint,
    last-updated: uint,
    roi-percentage: int,
    status: (string-ascii 10),
    manager: principal
})

(define-map treasury-deposits principal {
    total-deposited: uint,
    last-deposit: uint
})

(define-map authorized-managers principal bool)

(define-private (is-authorized-manager (user principal))
    (or (is-eq user CONTRACT-OWNER)
        (default-to false (map-get? authorized-managers user))))

(define-read-only (get-treasury-balance)
    (var-get total-treasury))

(define-read-only (get-investment (investment-id uint))
    (map-get? investments investment-id))

(define-read-only (get-depositor-info (depositor principal))
    (map-get? treasury-deposits depositor))

(define-read-only (get-investment-count)
    (var-get investment-counter))

(define-public (deposit-to-treasury (amount uint))
    (begin
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (not (var-get emergency-lock)) ERR-TREASURY-LOCKED)
        
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        (var-set total-treasury (+ (var-get total-treasury) amount))
        
        (let ((current-info (default-to 
                {total-deposited: u0, last-deposit: u0}
                (get-depositor-info tx-sender))))
            (map-set treasury-deposits tx-sender {
                total-deposited: (+ (get total-deposited current-info) amount),
                last-deposit: block-height
            }))
        
        (ok amount)))

(define-public (create-investment (name (string-ascii 50))
                                (allocated-amount uint)
                                (manager principal))
    (begin
        (asserts! (is-authorized-manager tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (<= allocated-amount (var-get total-treasury)) ERR-INSUFFICIENT-FUNDS)
        (asserts! (> allocated-amount u0) ERR-INVALID-AMOUNT)
        (asserts! (not (var-get emergency-lock)) ERR-TREASURY-LOCKED)
        
        (let ((investment-id (+ (var-get investment-counter) u1)))
            (var-set total-treasury (- (var-get total-treasury) allocated-amount))
            
            (map-set investments investment-id {
                investment-name: name,
                allocated-amount: allocated-amount,
                current-value: allocated-amount,
                start-block: block-height,
                last-updated: block-height,
                roi-percentage: 0,
                status: "active",
                manager: manager
            })
            
            (var-set investment-counter investment-id)
            (ok investment-id))))

(define-public (update-investment-value (investment-id uint) (new-value uint))
    (let ((investment (unwrap! (get-investment investment-id) ERR-INVESTMENT-NOT-FOUND)))
        (asserts! (or (is-eq tx-sender (get manager investment))
                     (is-authorized-manager tx-sender)) ERR-NOT-AUTHORIZED)
        
        (let ((allocated (get allocated-amount investment))
              (roi (if (> new-value allocated)
                      (to-int (/ (* (- new-value allocated) u100) allocated))
                      (* -1 (to-int (/ (* (- allocated new-value) u100) allocated))))))
            
            (map-set investments investment-id 
                (merge investment {
                    current-value: new-value,
                    last-updated: block-height,
                    roi-percentage: roi
                }))
            
            (ok roi))))

(define-public (close-investment (investment-id uint))
    (let ((investment (unwrap! (get-investment investment-id) ERR-INVESTMENT-NOT-FOUND)))
        (asserts! (or (is-eq tx-sender (get manager investment))
                     (is-authorized-manager tx-sender)) ERR-NOT-AUTHORIZED)
        
        (let ((current-value (get current-value investment))
              (fee (/ (* current-value u25) u1000))
              (return-amount (- current-value fee)))
            
            (var-set total-treasury (+ (var-get total-treasury) return-amount))
            
            (map-set investments investment-id 
                (merge investment {status: "closed"}))
            
            (ok return-amount))))

(define-public (authorize-manager (manager principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (map-set authorized-managers manager true)
        (ok true)))

(define-public (emergency-lock-treasury)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (var-set emergency-lock true)
        (ok true)))