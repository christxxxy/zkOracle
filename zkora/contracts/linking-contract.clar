;; ZK-Oracle: Consensus-Based Zero-Knowledge Proof Verification Network
;; Multiple validators reach consensus on proof verification through voting

;; ==============================================================================
;; CONSTANTS & ERROR CODES
;; ==============================================================================

(define-constant ORACLE_ADMIN tx-sender)
(define-constant ERR_ACCESS_FORBIDDEN (err u500))
(define-constant ERR_SUBMISSION_NOT_FOUND (err u501))
(define-constant ERR_INVALID_SUBMISSION (err u502))
(define-constant ERR_SUBMISSION_EXISTS (err u503))
(define-constant ERR_BOND_INSUFFICIENT (err u504))
(define-constant ERR_VALIDATOR_INACTIVE (err u505))
(define-constant ERR_PROTOCOL_UNSUPPORTED (err u506))

;; ==============================================================================
;; DATA VARIABLES
;; ==============================================================================

(define-data-var consensus-threshold uint u3) ;; Minimum 3 validators for consensus
(define-data-var validator-bond uint u3000000) ;; 3 STX validator bond
(define-data-var submission-counter uint u1)
(define-data-var oracle-network-active bool true)

;; ==============================================================================
;; DATA MAPS
;; ==============================================================================

;; Proof submissions awaiting consensus
(define-map proof-submissions
  { submission-id: uint }
  {
    submitter: principal,
    protocol-family: (string-ascii 24),
    proof-commitment: (buff 32),
    witness-inputs: (buff 1024),
    verification-params: (buff 512),
    consensus-reward: uint,
    votes-for: uint,
    votes-against: uint,
    consensus-reached: bool,
    final-result: bool,
    submission-time: uint,
    voting-deadline: uint
  }
)

;; Network validators and their voting power
(define-map network-validators
  { validator: principal }
  {
    validator-name: (string-ascii 52),
    specializations: (list 10 (string-ascii 24)),
    voting-power: uint,
    correct-votes: uint,
    total-votes: uint,
    bonded-amount: uint,
    is-active: bool
  }
)

;; Individual validator votes on submissions
(define-map validator-votes
  { submission-id: uint, validator: principal }
  {
    vote-choice: bool, ;; true = valid, false = invalid
    vote-weight: uint,
    vote-timestamp: uint,
    confidence-level: uint
  }
)

;; Submitter activity and reputation
(define-map submitter-profiles
  { submitter: principal }
  {
    submissions-made: uint,
    successful-submissions: uint,
    reputation-score: uint,
    last-submission: uint
  }
)

;; Protocol family configurations
(define-map protocol-families
  { protocol: (string-ascii 24) }
  {
    base-reward: uint,
    voting-period: uint,
    required-expertise: bool,
    is-enabled: bool
  }
)

;; ==============================================================================
;; PRIVATE FUNCTIONS
;; ==============================================================================

(define-private (is-oracle-admin)
  (is-eq tx-sender ORACLE_ADMIN)
)

(define-private (update-submitter-profile (submitter principal) (success bool))
  (let (
    (current-profile (default-to
      { submissions-made: u0, successful-submissions: u0, reputation-score: u50, last-submission: u0 }
      (map-get? submitter-profiles { submitter: submitter })
    ))
  )
    (map-set submitter-profiles
      { submitter: submitter }
      {
        submissions-made: (+ (get submissions-made current-profile) u1),
        successful-submissions: (if success 
          (+ (get successful-submissions current-profile) u1)
          (get successful-submissions current-profile)
        ),
        reputation-score: (if success
          (+ (get reputation-score current-profile) u2)
          (if (> (get reputation-score current-profile) u1)
            (- (get reputation-score current-profile) u1)
            u0
          )
        ),
        last-submission: block-height
      }
    )
  )
)

(define-private (is-supported-protocol (protocol (string-ascii 24)))
  (is-some (map-get? protocol-families { protocol: protocol }))
)

(define-private (check-consensus (submission-id uint))
  (match (map-get? proof-submissions { submission-id: submission-id })
    submission-data 
      (let (
        (total-votes (+ (get votes-for submission-data) (get votes-against submission-data)))
        (threshold (var-get consensus-threshold))
      )
        (and 
          (>= total-votes threshold)
          (or 
            (>= (get votes-for submission-data) threshold)
            (>= (get votes-against submission-data) threshold)
          )
        )
      )
    false ;; Return false if submission not found
  )
)

;; ==============================================================================
;; PUBLIC FUNCTIONS - ORACLE NETWORK SETUP
;; ==============================================================================

(define-public (initialize-oracle-network)
  (begin
    (asserts! (is-oracle-admin) ERR_ACCESS_FORBIDDEN)
    ;; Register standard protocol families
    (try! (add-protocol-family "stark-based" u2000000 u150 true))
    (try! (add-protocol-family "snark-based" u1500000 u120 true))
    (try! (add-protocol-family "bulletproof" u1000000 u100 false))
    (try! (add-protocol-family "plonk-based" u1800000 u140 true))
    (ok true)
  )
)

(define-public (add-protocol-family 
  (protocol (string-ascii 24))
  (base-reward uint)
  (voting-period uint)
  (required-expertise bool)
)
  (begin
    (asserts! (is-oracle-admin) ERR_ACCESS_FORBIDDEN)
    (map-set protocol-families
      { protocol: protocol }
      {
        base-reward: base-reward,
        voting-period: voting-period,
        required-expertise: required-expertise,
        is-enabled: true
      }
    )
    (ok true)
  )
)

(define-public (join-validator-network 
  (validator-name (string-ascii 52))
  (specializations (list 10 (string-ascii 24)))
)
  (let (
    (bond-amount (var-get validator-bond))
  )
    (begin
      (asserts! (>= (stx-get-balance tx-sender) bond-amount) ERR_BOND_INSUFFICIENT)
      
      ;; Lock validator bond
      (try! (stx-transfer? bond-amount tx-sender (as-contract tx-sender)))
      
      ;; Register validator
      (map-set network-validators
        { validator: tx-sender }
        {
          validator-name: validator-name,
          specializations: specializations,
          voting-power: u1, ;; Initial voting power
          correct-votes: u0,
          total-votes: u0,
          bonded-amount: bond-amount,
          is-active: true
        }
      )
      (ok true)
    )
  )
)

;; ==============================================================================
;; PUBLIC FUNCTIONS - PROOF SUBMISSION & VOTING
;; ==============================================================================

(define-public (submit-for-consensus
  (protocol-family (string-ascii 24))
  (proof-commitment (buff 32))
  (witness-inputs (buff 1024))
  (verification-params (buff 512))
  (consensus-reward uint)
)
  (let (
    (submission-id (var-get submission-counter))
    (protocol-config (unwrap! (map-get? protocol-families { protocol: protocol-family }) ERR_PROTOCOL_UNSUPPORTED))
    (min-reward (get base-reward protocol-config))
  )
    (begin
      (asserts! (var-get oracle-network-active) ERR_ACCESS_FORBIDDEN)
      (asserts! (>= consensus-reward min-reward) ERR_BOND_INSUFFICIENT)
      (asserts! (>= (stx-get-balance tx-sender) consensus-reward) ERR_BOND_INSUFFICIENT)
      
      ;; Lock consensus reward
      (try! (stx-transfer? consensus-reward tx-sender (as-contract tx-sender)))
      
      ;; Create submission
      (map-set proof-submissions
        { submission-id: submission-id }
        {
          submitter: tx-sender,
          protocol-family: protocol-family,
          proof-commitment: proof-commitment,
          witness-inputs: witness-inputs,
          verification-params: verification-params,
          consensus-reward: consensus-reward,
          votes-for: u0,
          votes-against: u0,
          consensus-reached: false,
          final-result: false,
          submission-time: block-height,
          voting-deadline: (+ block-height (get voting-period protocol-config))
        }
      )
      
      ;; Update counters
      (var-set submission-counter (+ submission-id u1))
      (update-submitter-profile tx-sender false)
      
      (ok submission-id)
    )
  )
)

(define-public (cast-vote 
  (submission-id uint)
  (vote-choice bool)
  (confidence-level uint)
)
  (let (
    (submission-data (unwrap! (map-get? proof-submissions { submission-id: submission-id }) ERR_SUBMISSION_NOT_FOUND))
    (validator-data (unwrap! (map-get? network-validators { validator: tx-sender }) ERR_VALIDATOR_INACTIVE))
  )
    (begin
      (asserts! (get is-active validator-data) ERR_ACCESS_FORBIDDEN)
      (asserts! (< block-height (get voting-deadline submission-data)) ERR_INVALID_SUBMISSION)
      (asserts! (not (get consensus-reached submission-data)) ERR_SUBMISSION_EXISTS)
      (asserts! (<= confidence-level u100) ERR_INVALID_SUBMISSION)
      
      ;; Check if validator already voted
      (asserts! (is-none (map-get? validator-votes { submission-id: submission-id, validator: tx-sender })) ERR_SUBMISSION_EXISTS)
      
      ;; Record vote
      (let (
        (vote-weight (get voting-power validator-data))
      )
        (map-set validator-votes
          { submission-id: submission-id, validator: tx-sender }
          {
            vote-choice: vote-choice,
            vote-weight: vote-weight,
            vote-timestamp: block-height,
            confidence-level: confidence-level
          }
        )
        
        ;; Update submission vote counts
        (map-set proof-submissions
          { submission-id: submission-id }
          (merge submission-data {
            votes-for: (if vote-choice 
              (+ (get votes-for submission-data) vote-weight)
              (get votes-for submission-data)
            ),
            votes-against: (if vote-choice
              (get votes-against submission-data)
              (+ (get votes-against submission-data) vote-weight)
            )
          })
        )
        
        ;; Update validator stats
        (map-set network-validators
          { validator: tx-sender }
          (merge validator-data {
            total-votes: (+ (get total-votes validator-data) u1)
          })
        )
      )
      
      (ok true)
    )
  )
)

(define-public (finalize-consensus (submission-id uint))
  (let (
    (submission-data (unwrap! (map-get? proof-submissions { submission-id: submission-id }) ERR_SUBMISSION_NOT_FOUND))
  )
    (begin
      (asserts! (not (get consensus-reached submission-data)) ERR_SUBMISSION_EXISTS)
      (asserts! (check-consensus submission-id) ERR_INVALID_SUBMISSION)
      
      ;; Determine final result
      (let (
        (final-outcome (> (get votes-for submission-data) (get votes-against submission-data)))
        (reward-amount (get consensus-reward submission-data))
        (winning-validators (if final-outcome (get votes-for submission-data) (get votes-against submission-data)))
      )
        ;; Mark consensus as reached
        (map-set proof-submissions
          { submission-id: submission-id }
          (merge submission-data {
            consensus-reached: true,
            final-result: final-outcome
          })
        )
        
        ;; Distribute rewards to winning validators
        ;; (Simplified - in practice would iterate through winning voters)
        (try! (if final-outcome
          (as-contract (stx-transfer? (/ reward-amount u2) tx-sender (get submitter submission-data)))
          (as-contract (stx-transfer? reward-amount tx-sender (get submitter submission-data)))
        ))
        
        ;; Update submitter profile
        (update-submitter-profile (get submitter submission-data) final-outcome)
        
        (ok true)
      )
    )
  )
)

;; ==============================================================================
;; QUERY FUNCTIONS
;; ==============================================================================

(define-read-only (get-submission-details (submission-id uint))
  (map-get? proof-submissions { submission-id: submission-id })
)

(define-read-only (get-validator-info (validator principal))
  (map-get? network-validators { validator: validator })
)

(define-read-only (get-vote-details (submission-id uint) (validator principal))
  (map-get? validator-votes { submission-id: submission-id, validator: validator })
)

(define-read-only (get-submitter-stats (submitter principal))
  (map-get? submitter-profiles { submitter: submitter })
)

(define-read-only (get-protocol-config (protocol (string-ascii 24)))
  (map-get? protocol-families { protocol: protocol })
)

(define-read-only (get-consensus-threshold)
  (var-get consensus-threshold)
)

(define-read-only (has-consensus-been-reached (submission-id uint))
  (match (map-get? proof-submissions { submission-id: submission-id })
    submission-data (and 
      (get consensus-reached submission-data)
      (get final-result submission-data)
    )
    false
  )
)

;; ==============================================================================
;; UTILITY FUNCTIONS
;; ==============================================================================

(define-public (reclaim-expired-submission (submission-id uint))
  (let (
    (submission-data (unwrap! (map-get? proof-submissions { submission-id: submission-id }) ERR_SUBMISSION_NOT_FOUND))
  )
    (begin
      (asserts! (is-eq tx-sender (get submitter submission-data)) ERR_ACCESS_FORBIDDEN)
      (asserts! (> block-height (get voting-deadline submission-data)) ERR_INVALID_SUBMISSION)
      (asserts! (not (get consensus-reached submission-data)) ERR_SUBMISSION_EXISTS)
      
      ;; Return locked reward to submitter
      (try! (as-contract (stx-transfer? (get consensus-reward submission-data) tx-sender (get submitter submission-data))))
      
      (ok true)
    )
  )
)

(define-public (increase-voting-power)
  (let (
    (validator-data (unwrap! (map-get? network-validators { validator: tx-sender }) ERR_VALIDATOR_INACTIVE))
    (additional-bond u1000000) ;; 1 STX to increase voting power
  )
    (begin
      (asserts! (get is-active validator-data) ERR_ACCESS_FORBIDDEN)
      (try! (stx-transfer? additional-bond tx-sender (as-contract tx-sender)))
      
      ;; Increase voting power
      (map-set network-validators
        { validator: tx-sender }
        (merge validator-data {
          voting-power: (+ (get voting-power validator-data) u1),
          bonded-amount: (+ (get bonded-amount validator-data) additional-bond)
        })
      )
      
      (ok true)
    )
  )
)

;; ==============================================================================
;; ADMIN FUNCTIONS
;; ==============================================================================

(define-public (update-consensus-threshold (new-threshold uint))
  (begin
    (asserts! (is-oracle-admin) ERR_ACCESS_FORBIDDEN)
    (var-set consensus-threshold new-threshold)
    (ok true)
  )
)

(define-public (halt-oracle-network)
  (begin
    (asserts! (is-oracle-admin) ERR_ACCESS_FORBIDDEN)
    (var-set oracle-network-active false)
    (ok true)
  )
)

(define-public (restart-oracle-network)
  (begin
    (asserts! (is-oracle-admin) ERR_ACCESS_FORBIDDEN)
    (var-set oracle-network-active true)
    (ok true)
  )
)

(define-public (withdraw-network-fees (amount uint))
  (begin
    (asserts! (is-oracle-admin) ERR_ACCESS_FORBIDDEN)
    (as-contract (stx-transfer? amount tx-sender ORACLE_ADMIN))
  )
)