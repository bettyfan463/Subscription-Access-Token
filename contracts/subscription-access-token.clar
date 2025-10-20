(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_SUBSCRIPTION_EXPIRED (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_SUBSCRIPTION_NOT_FOUND (err u103))
(define-constant ERR_ALREADY_SUBSCRIBED (err u104))
(define-constant ERR_INVALID_TIER (err u105))
(define-constant ERR_INSUFFICIENT_PAYMENT (err u106))
(define-constant ERR_INVALID_REFERRAL_CODE (err u107))
(define-constant ERR_CANNOT_REFER_SELF (err u108))
(define-constant ERR_REFERRAL_CODE_EXISTS (err u109))
(define-constant ERR_INSUFFICIENT_LOYALTY_POINTS (err u110))
(define-constant ERR_INVALID_REDEMPTION (err u111))

(define-constant CONTRACT_OWNER tx-sender)

(define-data-var subscription-counter uint u0)
(define-data-var token-counter uint u0)
(define-data-var referral-counter uint u0)
(define-data-var loyalty-points-per-block uint u1)

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

(define-map referral-codes
  { code: uint }
  {
    referrer: principal,
    created-at: uint,
    uses-remaining: uint,
    total-referrals: uint,
    active: bool
  }
)

(define-map referral-rewards
  { user: principal }
  {
    total-earned: uint,
    successful-referrals: uint,
    pending-rewards: uint
  }
)

(define-map user-referral-codes
  { user: principal }
  { code: uint }
)

(define-map loyalty-points
  { user: principal }
  {
    total-points: uint,
    last-updated: uint,
    redeemed-points: uint
  }
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

(define-public (create-referral-code (max-uses uint))
  (let ((code-id (+ (var-get referral-counter) u1))
        (existing-code (map-get? user-referral-codes { user: tx-sender })))
    (asserts! (> max-uses u0) ERR_INVALID_AMOUNT)
    (asserts! (<= max-uses u100) ERR_INVALID_AMOUNT)
    (asserts! (is-none existing-code) ERR_REFERRAL_CODE_EXISTS)
    (map-set referral-codes
      { code: code-id }
      {
        referrer: tx-sender,
        created-at: stacks-block-height,
        uses-remaining: max-uses,
        total-referrals: u0,
        active: true
      }
    )
    (map-set user-referral-codes
      { user: tx-sender }
      { code: code-id }
    )
    (var-set referral-counter code-id)
    (ok { code: code-id, max-uses: max-uses })
  )
)

(define-public (subscribe-with-referral (tier uint) (referral-code uint))
  (let ((tier-info (unwrap! (get-subscription-tier tier) ERR_INVALID_TIER))
        (price (get price tier-info))
        (duration (get duration-blocks tier-info))
        (expires-at (+ stacks-block-height duration))
        (existing-sub (get-subscription tx-sender tier))
        (referral (unwrap! (map-get? referral-codes { code: referral-code }) ERR_INVALID_REFERRAL_CODE))
        (discount-amount (/ price u10))
        (discounted-price (- price discount-amount)))
    (asserts! (> tier u0) ERR_INVALID_TIER)
    (asserts! (<= tier u3) ERR_INVALID_TIER)
    (asserts! (is-none existing-sub) ERR_ALREADY_SUBSCRIBED)
    (asserts! (get active referral) ERR_INVALID_REFERRAL_CODE)
    (asserts! (> (get uses-remaining referral) u0) ERR_INVALID_REFERRAL_CODE)
    (asserts! (not (is-eq tx-sender (get referrer referral))) ERR_CANNOT_REFER_SELF)
    (try! (stx-transfer? discounted-price tx-sender CONTRACT_OWNER))
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
    (update-revenue-stats discounted-price)
    (process-referral-reward referral-code discount-amount)
    (ok { subscription-id: (var-get subscription-counter), expires-at: expires-at, discount: discount-amount })
  )
)

(define-private (process-referral-reward (referral-code uint) (reward-amount uint))
  (let ((referral (unwrap-panic (map-get? referral-codes { code: referral-code })))
        (referrer (get referrer referral))
        (current-rewards (default-to 
          { total-earned: u0, successful-referrals: u0, pending-rewards: u0 }
          (map-get? referral-rewards { user: referrer })
        )))
    (map-set referral-codes
      { code: referral-code }
      {
        referrer: (get referrer referral),
        created-at: (get created-at referral),
        uses-remaining: (- (get uses-remaining referral) u1),
        total-referrals: (+ (get total-referrals referral) u1),
        active: (> (- (get uses-remaining referral) u1) u0)
      }
    )
    (map-set referral-rewards
      { user: referrer }
      {
        total-earned: (+ (get total-earned current-rewards) reward-amount),
        successful-referrals: (+ (get successful-referrals current-rewards) u1),
        pending-rewards: (+ (get pending-rewards current-rewards) reward-amount)
      }
    )
  )
)

(define-public (claim-referral-rewards)
  (let ((rewards (unwrap! (map-get? referral-rewards { user: tx-sender }) ERR_SUBSCRIPTION_NOT_FOUND))
        (pending-amount (get pending-rewards rewards)))
    (asserts! (> pending-amount u0) ERR_INVALID_AMOUNT)
    (try! (as-contract (stx-transfer? pending-amount tx-sender tx-sender)))
    (map-set referral-rewards
      { user: tx-sender }
      {
        total-earned: (get total-earned rewards),
        successful-referrals: (get successful-referrals rewards),
        pending-rewards: u0
      }
    )
    (ok { claimed: pending-amount })
  )
)

(define-public (deactivate-referral-code)
  (let ((user-code (unwrap! (map-get? user-referral-codes { user: tx-sender }) ERR_INVALID_REFERRAL_CODE))
        (code-id (get code user-code))
        (referral (unwrap! (map-get? referral-codes { code: code-id }) ERR_INVALID_REFERRAL_CODE)))
    (map-set referral-codes
      { code: code-id }
      {
        referrer: (get referrer referral),
        created-at: (get created-at referral),
        uses-remaining: (get uses-remaining referral),
        total-referrals: (get total-referrals referral),
        active: false
      }
    )
    (ok { deactivated: code-id })
  )
)

(define-public (extend-referral-code (additional-uses uint))
  (let ((user-code (unwrap! (map-get? user-referral-codes { user: tx-sender }) ERR_INVALID_REFERRAL_CODE))
        (code-id (get code user-code))
        (referral (unwrap! (map-get? referral-codes { code: code-id }) ERR_INVALID_REFERRAL_CODE)))
    (asserts! (> additional-uses u0) ERR_INVALID_AMOUNT)
    (asserts! (<= additional-uses u50) ERR_INVALID_AMOUNT)
    (map-set referral-codes
      { code: code-id }
      {
        referrer: (get referrer referral),
        created-at: (get created-at referral),
        uses-remaining: (+ (get uses-remaining referral) additional-uses),
        total-referrals: (get total-referrals referral),
        active: true
      }
    )
    (ok { code: code-id, new-uses: (+ (get uses-remaining referral) additional-uses) })
  )
)

(define-read-only (get-referral-code (code uint))
  (map-get? referral-codes { code: code })
)

(define-read-only (get-user-referral-code (user principal))
  (match (map-get? user-referral-codes { user: user })
    user-code (map-get? referral-codes { code: (get code user-code) })
    none
  )
)

(define-read-only (get-referral-rewards (user principal))
  (default-to 
    { total-earned: u0, successful-referrals: u0, pending-rewards: u0 }
    (map-get? referral-rewards { user: user })
  )
)

(define-read-only (get-referral-stats)
  {
    total-codes-created: (var-get referral-counter),
    current-block: stacks-block-height
  }
)

(define-read-only (validate-referral-code (code uint))
  (match (map-get? referral-codes { code: code })
    referral {
      valid: (and (get active referral) (> (get uses-remaining referral) u0)),
      uses-remaining: (get uses-remaining referral),
      total-referrals: (get total-referrals referral),
      referrer: (get referrer referral)
    }
    { valid: false, uses-remaining: u0, total-referrals: u0, referrer: CONTRACT_OWNER }
  )
)

(define-read-only (calculate-referral-discount (tier uint))
  (match (get-subscription-tier tier)
    tier-info 
    (let ((price (get price tier-info))
          (discount (/ price u10)))
      { original-price: price, discount: discount, final-price: (- price discount) }
    )
    { original-price: u0, discount: u0, final-price: u0 }
  )
)

(define-public (bulk-referral-subscribe (tier uint) (referral-code uint) (recipients (list 5 principal)))
  (let ((tier-info (unwrap! (get-subscription-tier tier) ERR_INVALID_TIER))
        (referral (unwrap! (map-get? referral-codes { code: referral-code }) ERR_INVALID_REFERRAL_CODE))
        (price (get price tier-info))
        (discount-amount (/ price u10))
        (discounted-price (- price discount-amount))
        (total-cost (* discounted-price (len recipients))))
    (asserts! (> (len recipients) u0) ERR_INVALID_AMOUNT)
    (asserts! (get active referral) ERR_INVALID_REFERRAL_CODE)
    (asserts! (>= (get uses-remaining referral) (len recipients)) ERR_INVALID_REFERRAL_CODE)
    (try! (stx-transfer? total-cost tx-sender CONTRACT_OWNER))
    (ok (map process-bulk-referral recipients))
  )
)

(define-private (process-bulk-referral (recipient principal))
  { recipient: recipient, success: true }
)

(define-private (calculate-loyalty-points (user principal) (tier uint))
  (let ((subscription (get-subscription user tier))
        (current-points (default-to
          { total-points: u0, last-updated: stacks-block-height, redeemed-points: u0 }
          (map-get? loyalty-points { user: user })
        )))
    (match subscription
      sub (let ((blocks-held (- stacks-block-height (get last-updated current-points)))
                (tier-multiplier (if (is-eq tier u3) u3 (if (is-eq tier u2) u2 u1)))
                (new-points (* (* blocks-held (var-get loyalty-points-per-block)) tier-multiplier)))
            (+ (get total-points current-points) new-points))
      (get total-points current-points)
    )
  )
)

(define-public (sync-loyalty-points (tier uint))
  (let ((user-points (default-to
          { total-points: u0, last-updated: stacks-block-height, redeemed-points: u0 }
          (map-get? loyalty-points { user: tx-sender })
        ))
        (calculated-points (calculate-loyalty-points tx-sender tier)))
    (map-set loyalty-points
      { user: tx-sender }
      {
        total-points: calculated-points,
        last-updated: stacks-block-height,
        redeemed-points: (get redeemed-points user-points)
      }
    )
    (ok { synced-points: calculated-points })
  )
)

(define-public (redeem-loyalty-for-extension (tier uint) (points-to-redeem uint))
  (let ((user-points (unwrap! (map-get? loyalty-points { user: tx-sender }) ERR_SUBSCRIPTION_NOT_FOUND))
        (available-points (- (get total-points user-points) (get redeemed-points user-points)))
        (existing-sub (unwrap! (get-subscription tx-sender tier) ERR_SUBSCRIPTION_NOT_FOUND))
        (blocks-to-extend (/ points-to-redeem (var-get loyalty-points-per-block))))
    (asserts! (> points-to-redeem u0) ERR_INVALID_AMOUNT)
    (asserts! (>= available-points points-to-redeem) ERR_INSUFFICIENT_LOYALTY_POINTS)
    (asserts! (> blocks-to-extend u0) ERR_INVALID_REDEMPTION)
    (map-set subscriptions
      { user: tx-sender, tier: tier }
      {
        expires-at: (+ (get expires-at existing-sub) blocks-to-extend),
        created-at: (get created-at existing-sub),
        auto-renew: (get auto-renew existing-sub),
        payments-made: (get payments-made existing-sub)
      }
    )
    (map-set loyalty-points
      { user: tx-sender }
      {
        total-points: (get total-points user-points),
        last-updated: stacks-block-height,
        redeemed-points: (+ (get redeemed-points user-points) points-to-redeem)
      }
    )
    (ok { redeemed: points-to-redeem, extension-blocks: blocks-to-extend })
  )
)

(define-public (redeem-loyalty-for-token (tier uint) (points-to-redeem uint))
  (let ((user-points (unwrap! (map-get? loyalty-points { user: tx-sender }) ERR_SUBSCRIPTION_NOT_FOUND))
        (available-points (- (get total-points user-points) (get redeemed-points user-points)))
        (token-id (+ (var-get token-counter) u1))
        (tier-info (unwrap! (get-subscription-tier tier) ERR_INVALID_TIER))
        (duration (get duration-blocks tier-info))
        (expires-at (+ stacks-block-height duration)))
    (asserts! (> points-to-redeem u0) ERR_INVALID_AMOUNT)
    (asserts! (>= available-points points-to-redeem) ERR_INSUFFICIENT_LOYALTY_POINTS)
    (asserts! (>= points-to-redeem u100) ERR_INVALID_REDEMPTION)
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
    (map-set loyalty-points
      { user: tx-sender }
      {
        total-points: (get total-points user-points),
        last-updated: stacks-block-height,
        redeemed-points: (+ (get redeemed-points user-points) points-to-redeem)
      }
    )
    (var-set token-counter token-id)
    (ok { token-id: token-id, redeemed-points: points-to-redeem, expires-at: expires-at })
  )
)

(define-read-only (get-loyalty-points (user principal))
  (default-to
    { total-points: u0, last-updated: stacks-block-height, redeemed-points: u0 }
    (map-get? loyalty-points { user: user })
  )
)

(define-read-only (get-available-loyalty-points (user principal))
  (let ((user-points (get-loyalty-points user)))
    (- (get total-points user-points) (get redeemed-points user-points))
  )
)

(define-read-only (estimate-loyalty-points (user principal) (tier uint) (blocks uint))
  (let ((tier-multiplier (if (is-eq tier u3) u3 (if (is-eq tier u2) u2 u1))))
    (* (* blocks (var-get loyalty-points-per-block)) tier-multiplier)
  )
)
