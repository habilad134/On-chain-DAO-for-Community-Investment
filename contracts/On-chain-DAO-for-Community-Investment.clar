(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-FUNDS (err u101))
(define-constant ERR-PROPOSAL-EXISTS (err u102))
(define-constant ERR-NO-PROPOSAL (err u103))
(define-constant ERR-ALREADY-VOTED (err u104))
(define-constant ERR-PROPOSAL-ACTIVE (err u105))
(define-constant ERR-PROPOSAL-INACTIVE (err u106))
(define-constant ERR-WITHDRAWAL-LOCKED (err u107))
(define-constant ERR-CANNOT-DELEGATE-TO-SELF (err u108))
(define-constant ERR-INVALID-DELEGATE (err u109))
(define-constant PROPOSAL-DURATION u144)
(define-constant MIN-PROPOSAL-AMOUNT u1000000)
(define-constant VOTING_POWER_MULTIPLIER u100)
(define-constant WITHDRAWAL-LOCK-PERIOD u144)

(define-data-var dao-owner principal tx-sender)
(define-data-var total-funds uint u0)

(define-map proposals
    uint
    {
        creator: principal,
        title: (string-ascii 50),
        recipient: principal,
        amount: uint,
        yes-votes: uint,
        no-votes: uint,
        end-block: uint,
        executed: bool,
    }
)

(define-map user-balances
    principal
    uint
)
(define-map proposal-votes
    {
        proposal-id: uint,
        voter: principal,
    }
    bool
)
(define-map member-withdrawals
    principal
    uint
)
(define-map delegations
    principal
    principal
)
(define-data-var proposal-count uint u0)

(define-public (initialize (owner principal))
    (begin
        (asserts! (is-eq tx-sender (var-get dao-owner)) ERR-NOT-AUTHORIZED)
        (var-set dao-owner owner)
        (ok true)
    )
)

(define-public (deposit (amount uint))
    (begin
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (map-set user-balances tx-sender
            (+ (default-to u0 (map-get? user-balances tx-sender)) amount)
        )
        (var-set total-funds (+ (var-get total-funds) amount))
        (ok true)
    )
)

(define-public (create-proposal
        (title (string-ascii 50))
        (recipient principal)
        (amount uint)
    )
    (let ((proposal-id (+ (var-get proposal-count) u1)))
        (asserts!
            (>= (default-to u0 (map-get? user-balances tx-sender))
                MIN-PROPOSAL-AMOUNT
            )
            ERR-INSUFFICIENT-FUNDS
        )
        (asserts! (<= amount (var-get total-funds)) ERR-INSUFFICIENT-FUNDS)
        (map-set proposals proposal-id {
            creator: tx-sender,
            title: title,
            recipient: recipient,
            amount: amount,
            yes-votes: u0,
            no-votes: u0,
            end-block: (+ burn-block-height PROPOSAL-DURATION),
            executed: false,
        })
        (var-set proposal-count proposal-id)
        (ok proposal-id)
    )
)

(define-private (get-voting-power (voter principal))
    (let (
            (user-balance (default-to u0 (map-get? user-balances voter)))
            (delegated-to (map-get? delegations voter))
        )
        (if (is-some delegated-to)
            u0
            (/ (* user-balance VOTING_POWER_MULTIPLIER) u100)
        )
    )
)

(define-private (get-total-voting-power (voter principal))
    (let (
            (own-power (get-voting-power voter))
            (delegated-power (fold get-delegated-power-for-voter (list voter) u0))
        )
        (+ own-power delegated-power)
    )
)

(define-private (get-delegated-power-for-voter
        (voter principal)
        (total uint)
    )
    (let ((delegators (filter is-delegated-to-voter (list voter))))
        (fold add-delegator-power delegators total)
    )
)

(define-private (is-delegated-to-voter (potential-delegator principal))
    (is-eq (map-get? delegations potential-delegator) (some tx-sender))
)

(define-private (add-delegator-power
        (delegator principal)
        (total uint)
    )
    (let (
            (delegator-balance (default-to u0 (map-get? user-balances delegator)))
            (delegator-power (/ (* delegator-balance VOTING_POWER_MULTIPLIER) u100))
        )
        (+ total delegator-power)
    )
)

(define-public (vote
        (proposal-id uint)
        (vote-for bool)
    )
    (let (
            (proposal (unwrap! (map-get? proposals proposal-id) ERR-NO-PROPOSAL))
            (vote-power (get-total-voting-power tx-sender))
        )
        (asserts! (< burn-block-height (get end-block proposal))
            ERR-PROPOSAL-INACTIVE
        )
        (asserts! (not (get executed proposal)) ERR-PROPOSAL-INACTIVE)
        (asserts!
            (not (default-to false
                (map-get? proposal-votes {
                    proposal-id: proposal-id,
                    voter: tx-sender,
                })
            ))
            ERR-ALREADY-VOTED
        )
        (map-set proposal-votes {
            proposal-id: proposal-id,
            voter: tx-sender,
        }
            true
        )
        (map-set member-withdrawals tx-sender
            (+ burn-block-height WITHDRAWAL-LOCK-PERIOD)
        )
        (if vote-for
            (map-set proposals proposal-id
                (merge proposal { yes-votes: (+ (get yes-votes proposal) vote-power) })
            )
            (map-set proposals proposal-id
                (merge proposal { no-votes: (+ (get no-votes proposal) vote-power) })
            )
        )
        (ok true)
    )
)

(define-public (execute-proposal (proposal-id uint))
    (let ((proposal (unwrap! (map-get? proposals proposal-id) ERR-NO-PROPOSAL)))
        (asserts! (>= burn-block-height (get end-block proposal))
            ERR-PROPOSAL-ACTIVE
        )
        (asserts! (not (get executed proposal)) ERR-PROPOSAL-INACTIVE)
        (asserts! (> (get yes-votes proposal) (get no-votes proposal))
            ERR-NOT-AUTHORIZED
        )
        (try! (as-contract (stx-transfer? (get amount proposal) tx-sender (get recipient proposal))))
        (map-set proposals proposal-id (merge proposal { executed: true }))
        (var-set total-funds (- (var-get total-funds) (get amount proposal)))
        (ok true)
    )
)

(define-read-only (get-proposal (proposal-id uint))
    (ok (unwrap! (map-get? proposals proposal-id) ERR-NO-PROPOSAL))
)

(define-public (withdraw (amount uint))
    (let (
            (user-balance (default-to u0 (map-get? user-balances tx-sender)))
            (withdrawal-lock (default-to u0 (map-get? member-withdrawals tx-sender)))
        )
        (asserts! (>= user-balance amount) ERR-INSUFFICIENT-FUNDS)
        (asserts! (>= burn-block-height withdrawal-lock) ERR-WITHDRAWAL-LOCKED)
        (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
        (map-set user-balances tx-sender (- user-balance amount))
        (var-set total-funds (- (var-get total-funds) amount))
        (ok true)
    )
)

(define-read-only (get-user-balance (user principal))
    (ok (default-to u0 (map-get? user-balances user)))
)

(define-read-only (get-withdrawal-lock (user principal))
    (ok (default-to u0 (map-get? member-withdrawals user)))
)

(define-public (delegate-voting-power (delegate principal))
    (begin
        (asserts! (not (is-eq tx-sender delegate)) ERR-CANNOT-DELEGATE-TO-SELF)
        (asserts! (> (default-to u0 (map-get? user-balances delegate)) u0)
            ERR-INVALID-DELEGATE
        )
        (map-set delegations tx-sender delegate)
        (ok true)
    )
)

(define-public (revoke-delegation)
    (begin
        (map-delete delegations tx-sender)
        (ok true)
    )
)

(define-read-only (get-delegate (user principal))
    (ok (map-get? delegations user))
)
