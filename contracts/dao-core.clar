;; DAO Core Contract - Community Investment Governance

(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-VOTED (err u102))
(define-constant ERR-VOTING-PERIOD-ENDED (err u103))
(define-constant ERR-INSUFFICIENT-TOKENS (err u104))

(define-data-var proposal-counter uint u0)
(define-data-var minimum-quorum uint u10)
(define-data-var voting-period uint u1008)

(define-map proposals uint {
    proposer: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    investment-amount: uint,
    target-address: principal,
    votes-for: uint,
    votes-against: uint,
    start-block: uint,
    end-block: uint,
    executed: bool
})

(define-map member-votes {proposal-id: uint, voter: principal} bool)
(define-map dao-members principal {
    tokens: uint,
    joined-block: uint,
    is-active: bool
})

(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals proposal-id))

(define-read-only (get-member-info (member principal))
    (map-get? dao-members member))

(define-read-only (has-voted (proposal-id uint) (voter principal))
    (is-some (map-get? member-votes {proposal-id: proposal-id, voter: voter})))

(define-read-only (get-proposal-count)
    (var-get proposal-counter))

(define-public (join-dao (token-amount uint))
    (begin
        (asserts! (>= token-amount u5) ERR-INSUFFICIENT-TOKENS)
        (map-set dao-members tx-sender {
            tokens: token-amount,
            joined-block: block-height,
            is-active: true
        })
        (ok true)))

(define-public (create-proposal (title (string-ascii 100)) 
                              (description (string-ascii 500))
                              (investment-amount uint)
                              (target-address principal))
    (let ((proposal-id (+ (var-get proposal-counter) u1))
          (member-info (unwrap! (get-member-info tx-sender) ERR-NOT-AUTHORIZED)))
        (asserts! (get is-active member-info) ERR-NOT-AUTHORIZED)
        (asserts! (>= (get tokens member-info) u10) ERR-INSUFFICIENT-TOKENS)
        
        (map-set proposals proposal-id {
            proposer: tx-sender,
            title: title,
            description: description,
            investment-amount: investment-amount,
            target-address: target-address,
            votes-for: u0,
            votes-against: u0,
            start-block: block-height,
            end-block: (+ block-height (var-get voting-period)),
            executed: false
        })
        
        (var-set proposal-counter proposal-id)
        (ok proposal-id)))

(define-public (vote-on-proposal (proposal-id uint) (vote-for bool))
    (let ((proposal (unwrap! (get-proposal proposal-id) ERR-PROPOSAL-NOT-FOUND))
          (member-info (unwrap! (get-member-info tx-sender) ERR-NOT-AUTHORIZED)))
        
        (asserts! (get is-active member-info) ERR-NOT-AUTHORIZED)
        (asserts! (not (has-voted proposal-id tx-sender)) ERR-ALREADY-VOTED)
        (asserts! (<= block-height (get end-block proposal)) ERR-VOTING-PERIOD-ENDED)
        
        (map-set member-votes {proposal-id: proposal-id, voter: tx-sender} true)
        
        (if vote-for
            (map-set proposals proposal-id 
                (merge proposal {votes-for: (+ (get votes-for proposal) (get tokens member-info))}))
            (map-set proposals proposal-id 
                (merge proposal {votes-against: (+ (get votes-against proposal) (get tokens member-info))})))
        
        (ok true)))
