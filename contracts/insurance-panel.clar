;; Insurance Panel Contract
;; Manages participation in insurance networks

;; Error codes
(define-constant ERR_UNAUTHORIZED u1)
(define-constant ERR_ALREADY_EXISTS u2)
(define-constant ERR_NOT_FOUND u3)
(define-constant ERR_INVALID_INPUT u4)
(define-constant ERR_EXPIRED u5)

;; Data structures
(define-map insurers
  { insurer-id: principal }
  {
    name: (string-utf8 100),
    insurer-type: (string-utf8 50),
    verified: bool,
    active: bool
  }
)

(define-map panels
  { panel-id: uint }
  {
    provider-id: principal,
    insurer-id: principal,
    network-name: (string-utf8 100),
    network-tier: (string-ascii 20),
    effective-date: uint,
    termination-date: uint,
    status: (string-ascii 20),
    specialties: (string-utf8 200),
    last-updated: uint
  }
)

;; Track authorized admins
(define-map admins
  { admin-id: principal }
  { authorized: bool }
)

;; Initialize contract owner as admin
(define-data-var contract-owner principal tx-sender)

;; Counter for panel IDs
(define-data-var panel-id-counter uint u0)

;; Functions

;; Register as an insurer
(define-public (register-insurer
                (name (string-utf8 100))
                (insurer-type (string-utf8 50)))
  (let ((insurer-exists (map-get? insurers {insurer-id: tx-sender})))
    (asserts! (is-none insurer-exists) (err ERR_ALREADY_EXISTS))

    ;; Store insurer data
    (map-set insurers
      {insurer-id: tx-sender}
      {
        name: name,
        insurer-type: insurer-type,
        verified: false,
        active: true
      }
    )

    (ok true)
  )
)

;; Verify an insurer (admin only)
(define-public (verify-insurer (insurer-id principal) (verified bool))
  (let ((is-admin (default-to false (get authorized (map-get? admins {admin-id: tx-sender}))))
        (insurer-data (map-get? insurers {insurer-id: insurer-id})))

    (asserts! is-admin (err ERR_UNAUTHORIZED))
    (asserts! (is-some insurer-data) (err ERR_NOT_FOUND))

    ;; Update insurer verification status
    (map-set insurers
      {insurer-id: insurer-id}
      (merge (unwrap-panic insurer-data)
        {verified: verified}
      )
    )

    (ok true)
  )
)

;; Add provider to panel (insurer only)
(define-public (add-to-panel
                (provider-id principal)
                (network-name (string-utf8 100))
                (network-tier (string-ascii 20))
                (effective-date uint)
                (termination-date uint)
                (specialties (string-utf8 200)))
  (let ((insurer-data (map-get? insurers {insurer-id: tx-sender}))
        (next-id (+ (var-get panel-id-counter) u1)))

    ;; Check if insurer exists and is verified
    (asserts! (is-some insurer-data) (err ERR_NOT_FOUND))
    (asserts! (get verified (unwrap-panic insurer-data)) (err ERR_UNAUTHORIZED))

    ;; Increment panel ID counter
    (var-set panel-id-counter next-id)

    ;; Store panel data
    (map-set panels
      {panel-id: next-id}
      {
        provider-id: provider-id,
        insurer-id: tx-sender,
        network-name: network-name,
        network-tier: network-tier,
        effective-date: effective-date,
        termination-date: termination-date,
        status: "active",
        specialties: specialties,
        last-updated: block-height
      }
    )

    (ok next-id)
  )
)

;; Update panel status (insurer only)
(define-public (update-panel-status
                (panel-id uint)
                (status (string-ascii 20)))
  (let ((panel-data (map-get? panels {panel-id: panel-id})))

    (asserts! (is-some panel-data) (err ERR_NOT_FOUND))

    ;; Check if the caller is the insurer that created the panel
    (asserts! (is-eq tx-sender (get insurer-id (unwrap-panic panel-data))) (err ERR_UNAUTHORIZED))

    ;; Update panel status
    (map-set panels
      {panel-id: panel-id}
      (merge (unwrap-panic panel-data)
        {
          status: status,
          last-updated: block-height
        }
      )
    )

    (ok true)
  )
)

;; Renew panel participation (insurer only)
(define-public (renew-panel
                (panel-id uint)
                (new-termination-date uint))
  (let ((panel-data (map-get? panels {panel-id: panel-id})))

    (asserts! (is-some panel-data) (err ERR_NOT_FOUND))

    ;; Check if the caller is the insurer that created the panel
    (asserts! (is-eq tx-sender (get insurer-id (unwrap-panic panel-data))) (err ERR_UNAUTHORIZED))

    ;; Update panel termination date
    (map-set panels
      {panel-id: panel-id}
      (merge (unwrap-panic panel-data)
        {
          termination-date: new-termination-date,
          last-updated: block-height
        }
      )
    )

    (ok true)
  )
)

;; Add an admin
(define-public (add-admin (admin-id principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR_UNAUTHORIZED))
    (map-set admins {admin-id: admin-id} {authorized: true})
    (ok true)
  )
)

;; Remove an admin
(define-public (remove-admin (admin-id principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR_UNAUTHORIZED))
    (map-set admins {admin-id: admin-id} {authorized: false})
    (ok true)
  )
)

;; Read-only functions

;; Get panel details
(define-read-only (get-panel (panel-id uint))
  (map-get? panels {panel-id: panel-id})
)

;; Get insurer details
(define-read-only (get-insurer (insurer-id principal))
  (map-get? insurers {insurer-id: insurer-id})
)

;; Check if a panel participation is valid and not expired
(define-read-only (is-panel-valid (panel-id uint))
  (let ((panel-data (map-get? panels {panel-id: panel-id})))
    (if (is-some panel-data)
        (let ((panel (unwrap-panic panel-data)))
          (and
            (is-eq (get status panel) "active")
            (or
              (is-eq (get termination-date panel) u0)
              (> (get termination-date panel) block-height)
            )
          )
        )
        false
    )
  )
)
