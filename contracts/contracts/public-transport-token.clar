;; Public Transport Token System - City-wide transportation payments with usage-based governance
;; Smart Contract for managing public transport payments and governance tokens

;; Contract Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-insufficient-balance (err u101))
(define-constant err-invalid-amount (err u102))
(define-constant err-route-not-found (err u103))
(define-constant err-unauthorized (err u104))
(define-constant err-already-exists (err u105))
(define-constant err-not-found (err u106))

;; Token Configuration
(define-fungible-token transport-token)
(define-fungible-token governance-token)

;; Data Variables
(define-data-var total-revenue uint u0)
(define-data-var base-fare uint u100) ;; Base fare in tokens
(define-data-var governance-threshold uint u1000) ;; Min tokens for governance participation

;; Data Maps
(define-map routes 
  { route-id: uint }
  { 
    name: (string-ascii 50),
    base-price: uint,
    distance: uint,
    active: bool,
    operator: principal
  }
)

(define-map user-balances 
  { user: principal }
  { 
    transport-balance: uint,
    governance-balance: uint,
    total-trips: uint,
    last-trip-block: uint
  }
)

(define-map route-usage
  { route-id: uint }
  {
    total-trips: uint,
    total-revenue: uint,
    weekly-trips: uint
  }
)

(define-map operators
  { operator: principal }
  {
    name: (string-ascii 50),
    active: bool,
    total-routes: uint,
    revenue-share: uint
  }
)

(define-map governance-proposals
  { proposal-id: uint }
  {
    proposer: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    votes-for: uint,
    votes-against: uint,
    end-block: uint,
    executed: bool
  }
)

(define-data-var next-route-id uint u1)
(define-data-var next-proposal-id uint u1)

;; Public Functions

;; Mint transport tokens (only owner)
(define-public (mint-transport-tokens (recipient principal) (amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> amount u0) err-invalid-amount)
    (try! (ft-mint? transport-token amount recipient))
    (update-user-balance recipient amount u0 u0)
    (ok true)
  )
)

;; Purchase transport tokens with STX
(define-public (purchase-tokens (amount uint))
  (let ((stx-cost (* amount u2))) ;; 1 token = 2 STX
    (asserts! (> amount u0) err-invalid-amount)
    (try! (stx-transfer? stx-cost tx-sender contract-owner))
    (try! (ft-mint? transport-token amount tx-sender))
    (update-user-balance tx-sender amount u0 u0)
    (ok true)
  )
)

;; Add new transport route (only owner)
(define-public (add-route (name (string-ascii 50)) (base-price uint) (distance uint) (operator principal))
  (let ((route-id (var-get next-route-id)))
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> base-price u0) err-invalid-amount)
    (map-set routes
      { route-id: route-id }
      {
        name: name,
        base-price: base-price,
        distance: distance,
        active: true,
        operator: operator
      }
    )
    (map-set route-usage
      { route-id: route-id }
      {
        total-trips: u0,
        total-revenue: u0,
        weekly-trips: u0
      }
    )
    (var-set next-route-id (+ route-id u1))
    (ok route-id)
  )
)

;; Pay for transport ride
(define-public (pay-for-ride (route-id uint))
  (let (
    (route-data (unwrap! (map-get? routes { route-id: route-id }) err-route-not-found))
    (user-data (get-user-balance tx-sender))
    (fare (get base-price route-data))
    (governance-bonus (/ fare u10)) ;; 10% governance token bonus
  )
    (asserts! (get active route-data) err-route-not-found)
    (asserts! (>= (get transport-balance user-data) fare) err-insufficient-balance)
    
    ;; Transfer payment
    (try! (ft-transfer? transport-token fare tx-sender (get operator route-data)))
    
    ;; Update user balance and trip count
    (update-user-balance tx-sender (- u0 fare) governance-bonus u1)
    
    ;; Update route usage statistics
    (update-route-usage route-id u1 fare)
    
    ;; Update total revenue
    (var-set total-revenue (+ (var-get total-revenue) fare))
    
    ;; Mint governance tokens for frequent users
    (try! (ft-mint? governance-token governance-bonus tx-sender))
    
    (ok true)
  )
)

;; Register as transport operator
(define-public (register-operator (name (string-ascii 50)))
  (begin
    (asserts! (is-none (map-get? operators { operator: tx-sender })) err-already-exists)
    (map-set operators
      { operator: tx-sender }
      {
        name: name,
        active: true,
        total-routes: u0,
        revenue-share: u80 ;; 80% revenue share
      }
    )
    (ok true)
  )
)

;; Create governance proposal
(define-public (create-proposal (title (string-ascii 100)) (description (string-ascii 500)))
  (let (
    (proposal-id (var-get next-proposal-id))
    (user-data (get-user-balance tx-sender))
  )
    (asserts! (>= (get governance-balance user-data) (var-get governance-threshold)) err-unauthorized)
    (map-set governance-proposals
      { proposal-id: proposal-id }
      {
        proposer: tx-sender,
        title: title,
        description: description,
        votes-for: u0,
        votes-against: u0,
        end-block: (+ block-height u1440), ;; ~10 days
        executed: false
      }
    )
    (var-set next-proposal-id (+ proposal-id u1))
    (ok proposal-id)
  )
)

;; Vote on governance proposal
(define-public (vote-on-proposal (proposal-id uint) (vote-for bool))
  (let (
    (proposal (unwrap! (map-get? governance-proposals { proposal-id: proposal-id }) err-not-found))
    (user-data (get-user-balance tx-sender))
    (voting-power (get governance-balance user-data))
  )
    (asserts! (>= voting-power u1) err-unauthorized)
    (asserts! (< block-height (get end-block proposal)) err-unauthorized)
    
    (if vote-for
      (map-set governance-proposals
        { proposal-id: proposal-id }
        (merge proposal { votes-for: (+ (get votes-for proposal) voting-power) })
      )
      (map-set governance-proposals
        { proposal-id: proposal-id }
        (merge proposal { votes-against: (+ (get votes-against proposal) voting-power) })
      )
    )
    (ok true)
  )
)

;; Transfer tokens between users
(define-public (transfer-transport-tokens (recipient principal) (amount uint))
  (begin
    (asserts! (> amount u0) err-invalid-amount)
    (try! (ft-transfer? transport-token amount tx-sender recipient))
    (update-user-balance tx-sender (- u0 amount) u0 u0)
    (update-user-balance recipient amount u0 u0)
    (ok true)
  )
)

;; Private Functions

(define-private (get-user-balance (user principal))
  (default-to 
    { transport-balance: u0, governance-balance: u0, total-trips: u0, last-trip-block: u0 }
    (map-get? user-balances { user: user })
  )
)

(define-private (update-user-balance (user principal) (transport-change int) (governance-change uint) (trip-change uint))
  (let ((current-data (get-user-balance user)))
    (map-set user-balances
      { user: user }
      {
        transport-balance: (if (>= transport-change 0) 
                            (+ (get transport-balance current-data) (to-uint transport-change))
                            (- (get transport-balance current-data) (to-uint (- transport-change)))),
        governance-balance: (+ (get governance-balance current-data) governance-change),
        total-trips: (+ (get total-trips current-data) trip-change),
        last-trip-block: (if (> trip-change u0) block-height (get last-trip-block current-data))
      }
    )
  )
)

(define-private (update-route-usage (route-id uint) (trip-change uint) (revenue-change uint))
  (let ((current-usage (default-to 
                         { total-trips: u0, total-revenue: u0, weekly-trips: u0 }
                         (map-get? route-usage { route-id: route-id }))))
    (map-set route-usage
      { route-id: route-id }
      {
        total-trips: (+ (get total-trips current-usage) trip-change),
        total-revenue: (+ (get total-revenue current-usage) revenue-change),
        weekly-trips: (+ (get weekly-trips current-usage) trip-change)
      }
    )
  )
)

;; Read-only Functions

(define-read-only (get-token-balance (user principal))
  (ft-get-balance transport-token user)
)

(define-read-only (get-governance-balance (user principal))
  (ft-get-balance governance-token user)
)

(define-read-only (get-route-info (route-id uint))
  (map-get? routes { route-id: route-id })
)

(define-read-only (get-user-stats (user principal))
  (map-get? user-balances { user: user })
)

(define-read-only (get-route-stats (route-id uint))
  (map-get? route-usage { route-id: route-id })
)

(define-read-only (get-proposal (proposal-id uint))
  (map-get? governance-proposals { proposal-id: proposal-id })
)

(define-read-only (get-contract-stats)
  {
    total-revenue: (var-get total-revenue),
    base-fare: (var-get base-fare),
    governance-threshold: (var-get governance-threshold),
    total-routes: (- (var-get next-route-id) u1),
    total-proposals: (- (var-get next-proposal-id) u1)
  }
)