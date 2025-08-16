(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_SUBSCRIPTION_EXPIRED (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_SUBSCRIPTION_NOT_FOUND (err u103))
(define-constant ERR_ALREADY_SUBSCRIBED (err u104))
(define-constant ERR_INVALID_TIER (err u105))
(define-constant ERR_INSUFFICIENT_PAYMENT (err u106))

(define-constant CONTRACT_OWNER tx-sender)

(define-data-var subscription-counter uint u0)
(define-data-var token-counter uint u0)

(define-map subscriptions
  { user: principal, tier: uint }
  {
    expires-at: uint,
    created-at: uint,
    auto-renew: bool,
    payments-made: uint
  }
)

(define-map subscription-tiers
  { tier-id: uint }
  {
    name: (string-ascii 50),
    price: uint,
    duration-blocks: uint,
    max-access-level: uint
  }
)

(define-map access-tokens
  { token-id: uint }
  {
    user: principal,
    tier: uint,
    issued-at: uint,
    expires-at: uint,
    used: bool
  }
)

(define-map revenue-tracking
  { period: uint }
  { total-revenue: uint, subscriptions-sold: uint }
)

(define-private (update-revenue-stats (amount uint))
  (let ((current-period (/ stacks-block-height u1008))
        (current-stats (get-revenue-stats current-period)))
    (map-set revenue-tracking
      { period: current-period }
      {
        total-revenue: (+ (get total-revenue current-stats) amount),
        subscriptions-sold: (+ (get subscriptions-sold current-stats) u1)
      }
    )
  )
)

(define-read-only (get-current-block-height)
  stacks-block-height
)

(define-read-only (get-subscription (user principal) (tier uint))
  (map-get? subscriptions { user: user, tier: tier })
)

(define-read-only (get-subscription-tier (tier-id uint))
  (map-get? subscription-tiers { tier-id: tier-id })
)

(define-read-only (is-subscription-active (user principal) (tier uint))
  (match (map-get? subscriptions { user: user, tier: tier })
    subscription (> (get expires-at subscription) stacks-block-height)
    false
  )
)

(define-read-only (get-access-token (token-id uint))
  (map-get? access-tokens { token-id: token-id })
)

(define-read-only (is-token-valid (token-id uint))
  (match (map-get? access-tokens { token-id: token-id })
    token (and 
            (> (get expires-at token) stacks-block-height)
            (not (get used token))
          )
    false
  )
)

(define-read-only (get-user-active-subscriptions (user principal))
  (let ((tier-1 (is-subscription-active user u1))
        (tier-2 (is-subscription-active user u2))
        (tier-3 (is-subscription-active user u3)))
    {
      tier-1: tier-1,
      tier-2: tier-2,
      tier-3: tier-3,
      has-any-active: (or tier-1 (or tier-2 tier-3))
    }
  )
)

(define-read-only (get-revenue-stats (period uint))
  (default-to 
    { total-revenue: u0, subscriptions-sold: u0 }
    (map-get? revenue-tracking { period: period })
  )
)

(define-public (initialize-tiers)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set subscription-tiers 
      { tier-id: u1 }
      { name: "Basic", price: u1000000, duration-blocks: u1008, max-access-level: u1 }
    )
    (map-set subscription-tiers 
      { tier-id: u2 }
      { name: "Premium", price: u2500000, duration-blocks: u2016, max-access-level: u2 }
    )
    (map-set subscription-tiers 
      { tier-id: u3 }
      { name: "Enterprise", price: u5000000, duration-blocks: u4032, max-access-level: u3 }
    )
    (ok true)
  )
)

(define-public (subscribe (tier uint))
  (let ((tier-info (unwrap! (get-subscription-tier tier) ERR_INVALID_TIER))
        (price (get price tier-info))
        (duration (get duration-blocks tier-info))
        (expires-at (+ stacks-block-height duration))
        (existing-sub (get-subscription tx-sender tier)))
    (asserts! (> tier u0) ERR_INVALID_TIER)
    (asserts! (<= tier u3) ERR_INVALID_TIER)
    (asserts! (is-none existing-sub) ERR_ALREADY_SUBSCRIBED)
    (try! (stx-transfer? price tx-sender CONTRACT_OWNER))
    (map-set subscriptions
      { user: tx-sender, tier: tier }
      {
        expires-at: expires-at,
        created-at: stacks-block-height,
        auto-renew: false,
        payments-made: u1
      }
    )
    (var-set subscription-counter (+ (var-get subscription-counter) u1))
    (update-revenue-stats price)
    (ok { subscription-id: (var-get subscription-counter), expires-at: expires-at })
  )
)

(define-public (renew-subscription (tier uint))
  (let ((tier-info (unwrap! (get-subscription-tier tier) ERR_INVALID_TIER))
        (price (get price tier-info))
        (duration (get duration-blocks tier-info))
        (existing-sub (unwrap! (get-subscription tx-sender tier) ERR_SUBSCRIPTION_NOT_FOUND)))
    (try! (stx-transfer? price tx-sender CONTRACT_OWNER))
    (map-set subscriptions
      { user: tx-sender, tier: tier }
      {
        expires-at: (+ (get expires-at existing-sub) duration),
        created-at: (get created-at existing-sub),
        auto-renew: (get auto-renew existing-sub),
        payments-made: (+ (get payments-made existing-sub) u1)
      }
    )
    (update-revenue-stats price)
    (ok { renewed: true, new-expires-at: (+ (get expires-at existing-sub) duration) })
  )
)

(define-public (set-auto-renew (tier uint) (auto-renew bool))
  (let ((existing-sub (unwrap! (get-subscription tx-sender tier) ERR_SUBSCRIPTION_NOT_FOUND)))
    (map-set subscriptions
      { user: tx-sender, tier: tier }
      {
        expires-at: (get expires-at existing-sub),
        created-at: (get created-at existing-sub),
        auto-renew: auto-renew,
        payments-made: (get payments-made existing-sub)
      }
    )
    (ok auto-renew)
  )
)

(define-public (generate-access-token (tier uint))
  (let ((token-id (+ (var-get token-counter) u1))
        (tier-info (unwrap! (get-subscription-tier tier) ERR_INVALID_TIER))
        (duration (get duration-blocks tier-info))
        (expires-at (+ stacks-block-height duration)))
    (asserts! (is-subscription-active tx-sender tier) ERR_SUBSCRIPTION_EXPIRED)
    (map-set access-tokens
      { token-id: token-id }
      {
        user: tx-sender,
        tier: tier,
        issued-at: stacks-block-height,
        expires-at: expires-at,
        used: false
      }
    )
    (var-set token-counter token-id)
    (ok { token-id: token-id, expires-at: expires-at })
  )
)

(define-public (use-access-token (token-id uint))
  (let ((token (unwrap! (get-access-token token-id) ERR_SUBSCRIPTION_NOT_FOUND)))
    (asserts! (is-eq (get user token) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-token-valid token-id) ERR_SUBSCRIPTION_EXPIRED)
    (map-set access-tokens
      { token-id: token-id }
      {
        user: (get user token),
        tier: (get tier token),
        issued-at: (get issued-at token),
        expires-at: (get expires-at token),
        used: true
      }
    )
    (ok { used: true, access-level: (get max-access-level (unwrap-panic (get-subscription-tier (get tier token)))) })
  )
)

(define-public (validate-access (user principal) (tier uint) (required-level uint))
  (let ((tier-info (unwrap! (get-subscription-tier tier) ERR_INVALID_TIER)))
    (asserts! (is-subscription-active user tier) ERR_SUBSCRIPTION_EXPIRED)
    (asserts! (>= (get max-access-level tier-info) required-level) ERR_UNAUTHORIZED)
    (ok true)
  )
)

(define-public (batch-validate-users (users (list 10 principal)) (tier uint) (required-level uint))
  (ok (map validate-user-access users))
)

(define-private (validate-user-access (user principal))
  (is-subscription-active user u1)
)

(define-public (upgrade-subscription (from-tier uint) (to-tier uint))
  (let ((from-tier-info (unwrap! (get-subscription-tier from-tier) ERR_INVALID_TIER))
        (to-tier-info (unwrap! (get-subscription-tier to-tier) ERR_INVALID_TIER))
        (existing-sub (unwrap! (get-subscription tx-sender from-tier) ERR_SUBSCRIPTION_NOT_FOUND))
        (price-diff (- (get price to-tier-info) (get price from-tier-info))))
    (asserts! (> to-tier from-tier) ERR_INVALID_TIER)
    (asserts! (is-subscription-active tx-sender from-tier) ERR_SUBSCRIPTION_EXPIRED)
    (try! (stx-transfer? price-diff tx-sender CONTRACT_OWNER))
    (map-delete subscriptions { user: tx-sender, tier: from-tier })
    (map-set subscriptions
      { user: tx-sender, tier: to-tier }
      {
        expires-at: (get expires-at existing-sub),
        created-at: (get created-at existing-sub),
        auto-renew: (get auto-renew existing-sub),
        payments-made: (+ (get payments-made existing-sub) u1)
      }
    )
    (update-revenue-stats price-diff)
    (ok { upgraded: true, new-tier: to-tier })
  )
)

(define-public (cancel-subscription (tier uint))
  (let ((existing-sub (unwrap! (get-subscription tx-sender tier) ERR_SUBSCRIPTION_NOT_FOUND)))
    (map-delete subscriptions { user: tx-sender, tier: tier })
    (ok { cancelled: true, tier: tier })
  )
)

(define-public (extend-subscription (user principal) (tier uint) (additional-blocks uint))
  (let ((existing-sub (unwrap! (get-subscription user tier) ERR_SUBSCRIPTION_NOT_FOUND)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set subscriptions
      { user: user, tier: tier }
      {
        expires-at: (+ (get expires-at existing-sub) additional-blocks),
        created-at: (get created-at existing-sub),
        auto-renew: (get auto-renew existing-sub),
        payments-made: (get payments-made existing-sub)
      }
    )
    (ok { extended: true, new-expires-at: (+ (get expires-at existing-sub) additional-blocks) })
  )
)

(define-read-only (get-subscription-status (user principal) (tier uint))
  (match (get-subscription user tier)
    subscription 
    {
      active: (is-subscription-active user tier),
      expires-at: (get expires-at subscription),
      blocks-remaining: (if (> (get expires-at subscription) stacks-block-height)
                         (- (get expires-at subscription) stacks-block-height)
                         u0),
      auto-renew: (get auto-renew subscription),
      payments-made: (get payments-made subscription)
    }
    {
      active: false,
      expires-at: u0,
      blocks-remaining: u0,
      auto-renew: false,
      payments-made: u0
    }
  )
)

(define-read-only (get-user-tokens (user principal) (max-tokens uint))
  (let ((tokens (list)))
    (fold check-token-ownership (list u1 u2 u3 u4 u5) tokens)
  )
)

(define-private (check-token-ownership (token-id uint) (acc (list 5 uint)))
  (match (map-get? access-tokens { token-id: token-id })
    token (if (is-eq (get user token) tx-sender)
            (unwrap-panic (as-max-len? (append acc token-id) u5))
            acc)
    acc
  )
)

(define-read-only (get-contract-stats)
  {
    total-subscriptions: (var-get subscription-counter),
    total-tokens-issued: (var-get token-counter),
    current-block: stacks-block-height,
    contract-owner: CONTRACT_OWNER
  }
)

(define-read-only (calculate-subscription-value (tier uint) (blocks uint))
  (match (get-subscription-tier tier)
    tier-info
    (let ((price-per-block (/ (get price tier-info) (get duration-blocks tier-info))))
      (* price-per-block blocks)
    )
    u0
  )
)

(define-read-only (preview-subscription-cost (tier uint) (blocks uint))
  (match (get-subscription-tier tier)
    tier-info
    (let ((base-price (get price tier-info))
          (base-duration (get duration-blocks tier-info))
          (cost-per-block (/ base-price base-duration)))
      { estimated-cost: (* cost-per-block blocks), tier: tier }
    )
    { estimated-cost: u0, tier: u0 }
  )
)

(define-public (gift-subscription (recipient principal) (tier uint))
  (let ((tier-info (unwrap! (get-subscription-tier tier) ERR_INVALID_TIER))
        (price (get price tier-info))
        (duration (get duration-blocks tier-info))
        (expires-at (+ stacks-block-height duration))
        (existing-sub (get-subscription recipient tier)))
    (asserts! (> tier u0) ERR_INVALID_TIER)
    (asserts! (<= tier u3) ERR_INVALID_TIER)
    (asserts! (is-none existing-sub) ERR_ALREADY_SUBSCRIBED)
    (try! (stx-transfer? price tx-sender CONTRACT_OWNER))
    (map-set subscriptions
      { user: recipient, tier: tier }
      {
        expires-at: expires-at,
        created-at: stacks-block-height,
        auto-renew: false,
        payments-made: u1
      }
    )
    (var-set subscription-counter (+ (var-get subscription-counter) u1))
    (update-revenue-stats price)
    (ok { gifted-to: recipient, tier: tier, expires-at: expires-at })
  )
)

(define-public (batch-gift-subscriptions (recipients (list 5 principal)) (tier uint))
  (let ((tier-info (unwrap! (get-subscription-tier tier) ERR_INVALID_TIER))
        (single-price (get price tier-info))
        (total-cost (* single-price (len recipients))))
    (asserts! (> (len recipients) u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? total-cost tx-sender CONTRACT_OWNER))
    (ok (map process-gift-recipient recipients))
  )
)

(define-private (process-gift-recipient (recipient principal))
  { recipient: recipient, success: true }
)

(define-public (withdraw-revenue (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (as-contract (stx-transfer? amount tx-sender CONTRACT_OWNER)))
    (ok { withdrawn: amount })
  )
)

(define-public (emergency-extend-subscription (user principal) (tier uint) (blocks uint))
  (let ((existing-sub (unwrap! (get-subscription user tier) ERR_SUBSCRIPTION_NOT_FOUND)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set subscriptions
      { user: user, tier: tier }
      {
        expires-at: (+ (get expires-at existing-sub) blocks),
        created-at: (get created-at existing-sub),
        auto-renew: (get auto-renew existing-sub),
        payments-made: (get payments-made existing-sub)
      }
    )
    (ok true)
  )
)

(define-public (create-temporary-token (tier uint) (duration-blocks uint))
  (let ((token-id (+ (var-get token-counter) u1))
        (expires-at (+ stacks-block-height duration-blocks)))
    (asserts! (is-subscription-active tx-sender tier) ERR_SUBSCRIPTION_EXPIRED)
    (asserts! (> duration-blocks u0) ERR_INVALID_AMOUNT)
    (asserts! (<= duration-blocks u4032) ERR_INVALID_AMOUNT)
    (map-set access-tokens
      { token-id: token-id }
      {
        user: tx-sender,
        tier: tier,
        issued-at: stacks-block-height,
        expires-at: expires-at,
        used: false
      }
    )
    (var-set token-counter token-id)
    (ok { token-id: token-id, expires-at: expires-at })
  )
)

(define-public (revoke-token (token-id uint))
  (let ((token (unwrap! (get-access-token token-id) ERR_SUBSCRIPTION_NOT_FOUND)))
    (asserts! (is-eq (get user token) tx-sender) ERR_UNAUTHORIZED)
    (map-set access-tokens
      { token-id: token-id }
      {
        user: (get user token),
        tier: (get tier token),
        issued-at: (get issued-at token),
        expires-at: stacks-block-height,
        used: true
      }
    )
    (ok { revoked: true, token-id: token-id })
  )
)

(define-public (transfer-subscription (tier uint) (new-owner principal))
  (let ((existing-sub (unwrap! (get-subscription tx-sender tier) ERR_SUBSCRIPTION_NOT_FOUND)))
    (asserts! (is-subscription-active tx-sender tier) ERR_SUBSCRIPTION_EXPIRED)
    (map-delete subscriptions { user: tx-sender, tier: tier })
    (map-set subscriptions
      { user: new-owner, tier: tier }
      existing-sub
    )
    (ok { transferred: true, new-owner: new-owner, tier: tier })
  )
)

(define-read-only (get-subscription-history (user principal))
  {
    tier-1: (get-subscription user u1),
    tier-2: (get-subscription user u2),
    tier-3: (get-subscription user u3),
    active-count: (+ (if (is-subscription-active user u1) u1 u0)
                    (+ (if (is-subscription-active user u2) u1 u0)
                       (if (is-subscription-active user u3) u1 u0)))
  }
)

(define-read-only (get-tier-analytics (tier uint))
  (let ((tier-info (get-subscription-tier tier)))
    (match tier-info
      info {
        tier: tier,
        name: (get name info),
        price: (get price info),
        duration: (get duration-blocks info),
        access-level: (get max-access-level info)
      }
      { tier: u0, name: "", price: u0, duration: u0, access-level: u0 }
    )
  )
)

(define-public (pause-subscription (tier uint))
  (let ((existing-sub (unwrap! (get-subscription tx-sender tier) ERR_SUBSCRIPTION_NOT_FOUND)))
    (asserts! (is-subscription-active tx-sender tier) ERR_SUBSCRIPTION_EXPIRED)
    (map-set subscriptions
      { user: tx-sender, tier: tier }
      {
        expires-at: stacks-block-height,
        created-at: (get created-at existing-sub),
        auto-renew: false,
        payments-made: (get payments-made existing-sub)
      }
    )
    (ok { paused: true, tier: tier })
  )
)

(define-read-only (estimate-renewal-cost (user principal) (tier uint))
  (let ((tier-info (get-subscription-tier tier))
        (existing-sub (get-subscription user tier)))
    (match tier-info
      info (match existing-sub
             sub {
               tier: tier,
               current-price: (get price info),
               expires-at: (get expires-at sub),
               is-expired: (<= (get expires-at sub) stacks-block-height)
             }
             { tier: u0, current-price: u0, expires-at: u0, is-expired: true })
      { tier: u0, current-price: u0, expires-at: u0, is-expired: true }
    )
  )
)
