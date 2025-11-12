;; DAO Core Contract - Community Investment Governance

(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-VOTED (err u102))
(define-constant ERR-VOTING-PERIOD-ENDED (err u103))
(define-constant ERR-INSUFFICIENT-TOKENS (err u104))

(define-data-var proposal-counter uint u0)
(define-data-var minimum-quorum uint u10)
(define-data-var voting-period uint u1008)

(define-map proposals
    uint
    {
        proposer: principal,
        title: (string-ascii 100),
        description: (string-ascii 500),
        investment-amount: uint,
        target-address: principal,
        votes-for: uint,
        votes-against: uint,
        start-block: uint,
        end-block: uint,
        executed: bool,
    }
)

(define-map member-votes
    {
        proposal-id: uint,
        voter: principal,
    }
    bool
)
(define-map dao-members
    principal
    {
        tokens: uint,
        joined-block: uint,
        is-active: bool,
    }
)

(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals proposal-id)
)

(define-read-only (get-member-info (member principal))
    (map-get? dao-members member)
)

(define-read-only (has-voted
        (proposal-id uint)
        (voter principal)
    )
    (is-some (map-get? member-votes {
        proposal-id: proposal-id,
        voter: voter,
    }))
)

(define-read-only (get-proposal-count)
    (var-get proposal-counter)
)

(define-public (join-dao (token-amount uint))
    (begin
        (asserts! (>= token-amount u5) ERR-INSUFFICIENT-TOKENS)
        (map-set dao-members tx-sender {
            tokens: token-amount,
            joined-block: block-height,
            is-active: true,
        })
        (ok true)
    )
)

(define-public (create-proposal
        (title (string-ascii 100))
        (description (string-ascii 500))
        (investment-amount uint)
        (target-address principal)
    )
    (let (
            (proposal-id (+ (var-get proposal-counter) u1))
            (member-info (unwrap! (get-member-info tx-sender) ERR-NOT-AUTHORIZED))
        )
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
            executed: false,
        })

        (var-set proposal-counter proposal-id)
        (ok proposal-id)
    )
)

(define-public (vote-on-proposal
        (proposal-id uint)
        (vote-for bool)
    )
    (let (
            (proposal (unwrap! (get-proposal proposal-id) ERR-PROPOSAL-NOT-FOUND))
            (member-info (unwrap! (get-member-info tx-sender) ERR-NOT-AUTHORIZED))
        )
        (asserts! (get is-active member-info) ERR-NOT-AUTHORIZED)
        (asserts! (not (has-voted proposal-id tx-sender)) ERR-ALREADY-VOTED)
        (asserts! (<= block-height (get end-block proposal))
            ERR-VOTING-PERIOD-ENDED
        )

        (map-set member-votes {
            proposal-id: proposal-id,
            voter: tx-sender,
        }
            true
        )

        (if vote-for
            (map-set proposals proposal-id
                (merge proposal { votes-for: (+ (get votes-for proposal) (get tokens member-info)) })
            )
            (map-set proposals proposal-id
                (merge proposal { votes-against: (+ (get votes-against proposal) (get tokens member-info)) })
            )
        )

        (ok true)
    )
)

(define-constant QF_CHOICE_AGAINST u0)
(define-constant QF_CHOICE_FOR u1)
(define-constant QF_CHOICE_ABSTAIN u2)
(define-constant ERR_QF_NOT_FOUND u7001)
(define-constant ERR_QF_FINALIZED u7002)
(define-constant ERR_QF_VOTING_CLOSED u7003)
(define-constant ERR_QF_ALREADY_VOTED u7004)
(define-constant ERR_QF_BAD_CHOICE u7005)
(define-constant ERR_QF_QUORUM_NOT_MET u7006)
(define-constant ERR_QF_NOT_AUTHORIZED u7007)
(define-constant ERR_QF_BAD_DURATION u7008)
(define-constant ERR_QF_BAD_QUORUM u7009)

(define-data-var qf-proposal-id uint u0)
(define-data-var qf-quorum-min-votes uint u1)
(define-data-var qf-admin (optional principal) none)

(define-map qf-proposals
    uint
    {
        proposer: principal,
        start-height: uint,
        end-height: uint,
        for: uint,
        against: uint,
        abstain: uint,
        finalized: bool,
        passed: bool,
    }
)

(define-map qf-votes
    {
        id: uint,
        voter: principal,
    }
    { choice: uint }
)

(define-public (qf-propose (duration uint))
    (begin
        (asserts! (> duration u0) (err ERR_QF_BAD_DURATION))
        (let (
                (start block-height)
                (end (+ block-height duration))
                (id (+ (var-get qf-proposal-id) u1))
            )
            (var-set qf-proposal-id id)
            (map-set qf-proposals id {
                proposer: tx-sender,
                start-height: start,
                end-height: end,
                for: u0,
                against: u0,
                abstain: u0,
                finalized: false,
                passed: false,
            })
            (ok id)
        )
    )
)

(define-public (qf-cast-vote
        (id uint)
        (choice uint)
    )
    (let ((prop (unwrap! (map-get? qf-proposals id) (err ERR_QF_NOT_FOUND))))
        (begin
            (asserts! (not (get finalized prop)) (err ERR_QF_FINALIZED))
            (asserts! (not (> block-height (get end-height prop)))
                (err ERR_QF_VOTING_CLOSED)
            )
            (asserts!
                (or (is-eq choice QF_CHOICE_FOR) (or (is-eq choice QF_CHOICE_AGAINST) (is-eq choice QF_CHOICE_ABSTAIN)))
                (err ERR_QF_BAD_CHOICE)
            )
            (match (map-get? qf-votes {
                id: id,
                voter: tx-sender,
            })
                existing (err ERR_QF_ALREADY_VOTED)
                (let (
                        (f (get for prop))
                        (a (get against prop))
                        (ab (get abstain prop))
                        (new-for (if (is-eq choice QF_CHOICE_FOR)
                            (+ f u1)
                            f
                        ))
                        (new-against (if (is-eq choice QF_CHOICE_AGAINST)
                            (+ a u1)
                            a
                        ))
                        (new-abstain (if (is-eq choice QF_CHOICE_ABSTAIN)
                            (+ ab u1)
                            ab
                        ))
                    )
                    (begin
                        (map-set qf-votes {
                            id: id,
                            voter: tx-sender,
                        } { choice: choice }
                        )
                        (map-set qf-proposals id {
                            proposer: (get proposer prop),
                            start-height: (get start-height prop),
                            end-height: (get end-height prop),
                            for: new-for,
                            against: new-against,
                            abstain: new-abstain,
                            finalized: (get finalized prop),
                            passed: (get passed prop),
                        })
                        (ok true)
                    )
                )
            )
        )
    )
)

(define-public (qf-finalize (id uint))
    (let ((prop (unwrap! (map-get? qf-proposals id) (err ERR_QF_NOT_FOUND))))
        (begin
            (asserts! (not (get finalized prop)) (err ERR_QF_FINALIZED))
            (asserts! (> block-height (get end-height prop))
                (err ERR_QF_VOTING_CLOSED)
            )
            (let (
                    (total (+ (+ (get for prop) (get against prop)) (get abstain prop)))
                    (min (var-get qf-quorum-min-votes))
                )
                (begin
                    (asserts! (>= total min) (err ERR_QF_QUORUM_NOT_MET))
                    (let ((passed? (> (get for prop) (get against prop))))
                        (begin
                            (map-set qf-proposals id {
                                proposer: (get proposer prop),
                                start-height: (get start-height prop),
                                end-height: (get end-height prop),
                                for: (get for prop),
                                against: (get against prop),
                                abstain: (get abstain prop),
                                finalized: true,
                                passed: passed?,
                            })
                            (ok passed?)
                        )
                    )
                )
            )
        )
    )
)

(define-public (qf-set-quorum-min (min uint))
    (begin
        (asserts! (> min u0) (err ERR_QF_BAD_QUORUM))
        (let ((current (var-get qf-admin)))
            (begin
                (match current
                    admin (asserts! (is-eq admin tx-sender) (err ERR_QF_NOT_AUTHORIZED))
                    (var-set qf-admin (some tx-sender))
                )
                (var-set qf-quorum-min-votes min)
                (ok true)
            )
        )
    )
)

(define-read-only (qf-get-proposal (id uint))
    (map-get? qf-proposals id)
)

(define-read-only (qf-get-vote
        (id uint)
        (voter principal)
    )
    (map-get? qf-votes {
        id: id,
        voter: voter,
    })
)

(define-read-only (qf-get-quorum-min)
    (var-get qf-quorum-min-votes)
)
