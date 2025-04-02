;; Hospital Privileging Contract
;; Tracks approved procedures by institution

;; Error codes
(define-constant ERR_UNAUTHORIZED u1)
(define-constant ERR_ALREADY_EXISTS u2)
(define-constant ERR_NOT_FOUND u3)
(define-constant ERR_INVALID_INPUT u4)
(define-constant ERR_EXPIRED u5)

;; Data structures
(define-map hospitals
  { hospital-id: principal }
  {
    name: (string-utf8 100),
    location: (string-utf8 100),
    verified: bool,
    active: bool
  }
)

(define-map privileges
  { privilege-id: uint }
  {
    provider-id: principal,
    hospital-id: principal,
    procedure-code: (string-ascii 20),
    procedure-name: (string-utf8 100),
    granted-date: uint,
    expiration-date: uint,
    status: (string-ascii 20),
    restrictions: (string-utf8 200),
    last-reviewed: uint
  }
)

;; Track authorized admins
(define-map admins
  { admin-id: principal }
  { authorized: bool }
)

;; Initialize contract owner as admin
(define-data-var contract-owner principal tx-sender)

;; Counter for privilege IDs
(define-data-var privilege-id-counter uint u0)

;; Functions

;; Register as a hospital
(define-public (register-hospital
                (name (string-utf8 100))
                (location (string-utf8 100)))
  (let ((hospital-exists (map-get? hospitals {hospital-id: tx-sender})))
    (asserts! (is-none hospital-exists) (err ERR_ALREADY_EXISTS))

    ;; Store hospital data
    (map-set hospitals
      {hospital-id: tx-sender}
      {
        name: name,
        location: location,
        verified: false,
        active: true
      }
    )

    (ok true)
  )
)

;; Verify a hospital (admin only)
(define-public (verify-hospital (hospital-id principal) (verified bool))
  (let ((is-admin (default-to false (get authorized (map-get? admins {admin-id: tx-sender}))))
        (hospital-data (map-get? hospitals {hospital-id: hospital-id})))

    (asserts! is-admin (err ERR_UNAUTHORIZED))
    (asserts! (is-some hospital-data) (err ERR_NOT_FOUND))

    ;; Update hospital verification status
    (map-set hospitals
      {hospital-id: hospital-id}
      (merge (unwrap-panic hospital-data)
        {verified: verified}
      )
    )

    (ok true)
  )
)

;; Grant privileges (hospital only)
(define-public (grant-privilege
                (provider-id principal)
                (procedure-code (string-ascii 20))
                (procedure-name (string-utf8 100))
                (expiration-date uint)
                (restrictions (string-utf8 200)))
  (let ((hospital-data (map-get? hospitals {hospital-id: tx-sender}))
        (next-id (+ (var-get privilege-id-counter) u1)))

    ;; Check if hospital exists and is verified
    (asserts! (is-some hospital-data) (err ERR_NOT_FOUND))
    (asserts! (get verified (unwrap-panic hospital-data)) (err ERR_UNAUTHORIZED))

    ;; Increment privilege ID counter
    (var-set privilege-id-counter next-id)

    ;; Store privilege data
    (map-set privileges
      {privilege-id: next-id}
      {
        provider-id: provider-id,
        hospital-id: tx-sender,
        procedure-code: procedure-code,
        procedure-name: procedure-name,
        granted-date: block-height,
        expiration-date: expiration-date,
        status: "active",
        restrictions: restrictions,
        last-reviewed: block-height
      }
    )

    (ok next-id)
  )
)

;; Update privilege status (hospital only)
(define-public (update-privilege-status
                (privilege-id uint)
                (status (string-ascii 20))
                (restrictions (string-utf8 200)))
  (let ((privilege-data (map-get? privileges {privilege-id: privilege-id})))

    (asserts! (is-some privilege-data) (err ERR_NOT_FOUND))

    ;; Check if the caller is the hospital that granted the privilege
    (asserts! (is-eq tx-sender (get hospital-id (unwrap-panic privilege-data))) (err ERR_UNAUTHORIZED))

    ;; Update privilege status
    (map-set privileges
      {privilege-id: privilege-id}
      (merge (unwrap-panic privilege-data)
        {
          status: status,
          restrictions: restrictions,
          last-reviewed: block-height
        }
      )
    )

    (ok true)
  )
)

;; Renew privilege (hospital only)
(define-public (renew-privilege
                (privilege-id uint)
                (new-expiration-date uint))
  (let ((privilege-data (map-get? privileges {privilege-id: privilege-id})))

    (asserts! (is-some privilege-data) (err ERR_NOT_FOUND))

    ;; Check if the caller is the hospital that granted the privilege
    (asserts! (is-eq tx-sender (get hospital-id (unwrap-panic privilege-data))) (err ERR_UNAUTHORIZED))

    ;; Update privilege expiration
    (map-set privileges
      {privilege-id: privilege-id}
      (merge (unwrap-panic privilege-data)
        {
          expiration-date: new-expiration-date,
          last-reviewed: block-height
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

;; Get privilege details
(define-read-only (get-privilege (privilege-id uint))
  (map-get? privileges {privilege-id: privilege-id})
)

;; Get hospital details
(define-read-only (get-hospital (hospital-id principal))
  (map-get? hospitals {hospital-id: hospital-id})
)

;; Check if a privilege is valid and not expired
(define-read-only (is-privilege-valid (privilege-id uint))
  (let ((privilege-data (map-get? privileges {privilege-id: privilege-id})))
    (if (is-some privilege-data)
        (let ((priv (unwrap-panic privilege-data)))
          (and
            (is-eq (get status priv) "active")
            (or
              (is-eq (get expiration-date priv) u0)
              (> (get expiration-date priv) block-height)
            )
          )
        )
        false
    )
  )
)
