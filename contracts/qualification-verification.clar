;; Qualification Verification Contract
;; Validates medical degrees and training

;; Error codes
(define-constant ERR_UNAUTHORIZED u1)
(define-constant ERR_ALREADY_EXISTS u2)
(define-constant ERR_NOT_FOUND u3)
(define-constant ERR_INVALID_INPUT u4)

;; Data structures
(define-map qualifications
  { qualification-id: uint }
  {
    provider-id: principal,
    issuer-id: principal,
    qualification-type: (string-utf8 50),
    qualification-name: (string-utf8 100),
    issue-date: uint,
    expiration-date: uint,
    verified: bool,
    verification-date: uint,
    metadata: (string-utf8 500)
  }
)

;; Track qualification issuers (medical schools, training programs, etc.)
(define-map issuers
  { issuer-id: principal }
  {
    name: (string-utf8 100),
    issuer-type: (string-utf8 50),
    website: (string-utf8 100),
    verified: bool,
    active: bool
  }
)

;; Track authorized admins
(define-map admins
  { admin-id: principal }
  { authorized: bool }
)

;; Initialize contract owner as admin
(define-data-var contract-owner principal tx-sender)

;; Counter for qualification IDs
(define-data-var qualification-id-counter uint u0)

;; Functions

;; Register as an issuer
(define-public (register-issuer
                (name (string-utf8 100))
                (issuer-type (string-utf8 50))
                (website (string-utf8 100)))
  (let ((issuer-exists (map-get? issuers {issuer-id: tx-sender})))
    (asserts! (is-none issuer-exists) (err ERR_ALREADY_EXISTS))

    ;; Store issuer data
    (map-set issuers
      {issuer-id: tx-sender}
      {
        name: name,
        issuer-type: issuer-type,
        website: website,
        verified: false,
        active: true
      }
    )

    (ok true)
  )
)

;; Verify an issuer (admin only)
(define-public (verify-issuer (issuer-id principal) (verified bool))
  (let ((is-admin (default-to false (get authorized (map-get? admins {admin-id: tx-sender}))))
        (issuer-data (map-get? issuers {issuer-id: issuer-id})))

    (asserts! is-admin (err ERR_UNAUTHORIZED))
    (asserts! (is-some issuer-data) (err ERR_NOT_FOUND))

    ;; Update issuer verification status
    (map-set issuers
      {issuer-id: issuer-id}
      (merge (unwrap-panic issuer-data)
        {verified: verified}
      )
    )

    (ok true)
  )
)

;; Add a qualification (can only be added by verified issuers)
(define-public (add-qualification
                (provider-id principal)
                (qualification-type (string-utf8 50))
                (qualification-name (string-utf8 100))
                (issue-date uint)
                (expiration-date uint)
                (metadata (string-utf8 500)))
  (let ((issuer-data (map-get? issuers {issuer-id: tx-sender}))
        (next-id (+ (var-get qualification-id-counter) u1)))

    ;; Check if issuer exists and is verified
    (asserts! (is-some issuer-data) (err ERR_NOT_FOUND))
    (asserts! (get verified (unwrap-panic issuer-data)) (err ERR_UNAUTHORIZED))

    ;; Increment qualification ID counter
    (var-set qualification-id-counter next-id)

    ;; Store qualification data
    (map-set qualifications
      {qualification-id: next-id}
      {
        provider-id: provider-id,
        issuer-id: tx-sender,
        qualification-type: qualification-type,
        qualification-name: qualification-name,
        issue-date: issue-date,
        expiration-date: expiration-date,
        verified: true,
        verification-date: block-height,
        metadata: metadata
      }
    )

    (ok next-id)
  )
)

;; Self-report a qualification (to be verified later)
(define-public (self-report-qualification
                (issuer-id principal)
                (qualification-type (string-utf8 50))
                (qualification-name (string-utf8 100))
                (issue-date uint)
                (expiration-date uint)
                (metadata (string-utf8 500)))
  (let ((next-id (+ (var-get qualification-id-counter) u1)))

    ;; Increment qualification ID counter
    (var-set qualification-id-counter next-id)

    ;; Store qualification data (unverified)
    (map-set qualifications
      {qualification-id: next-id}
      {
        provider-id: tx-sender,
        issuer-id: issuer-id,
        qualification-type: qualification-type,
        qualification-name: qualification-name,
        issue-date: issue-date,
        expiration-date: expiration-date,
        verified: false,
        verification-date: u0,
        metadata: metadata
      }
    )

    (ok next-id)
  )
)

;; Verify a self-reported qualification (issuer only)
(define-public (verify-qualification (qualification-id uint))
  (let ((qualification-data (map-get? qualifications {qualification-id: qualification-id})))

    (asserts! (is-some qualification-data) (err ERR_NOT_FOUND))

    ;; Check if the caller is the issuer
    (asserts! (is-eq tx-sender (get issuer-id (unwrap-panic qualification-data))) (err ERR_UNAUTHORIZED))

    ;; Update qualification verification status
    (map-set qualifications
      {qualification-id: qualification-id}
      (merge (unwrap-panic qualification-data)
        {
          verified: true,
          verification-date: block-height
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

;; Get qualification details
(define-read-only (get-qualification (qualification-id uint))
  (map-get? qualifications {qualification-id: qualification-id})
)

;; Get issuer details
(define-read-only (get-issuer (issuer-id principal))
  (map-get? issuers {issuer-id: issuer-id})
)

;; Check if a qualification is valid and not expired
(define-read-only (is-qualification-valid (qualification-id uint))
  (let ((qualification-data (map-get? qualifications {qualification-id: qualification-id})))
    (if (is-some qualification-data)
        (let ((qual (unwrap-panic qualification-data)))
          (and
            (get verified qual)
            (or
              (is-eq (get expiration-date qual) u0)
              (> (get expiration-date qual) block-height)
            )
          )
        )
        false
    )
  )
)
