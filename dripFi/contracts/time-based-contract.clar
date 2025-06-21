;; Micropayment Streaming Contract - Stage 1
;; Basic streaming functionality with deposit and withdrawal

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_STREAM_NOT_FOUND (err u101))
(define-constant ERR_INSUFFICIENT_BALANCE (err u102))
(define-constant ERR_STREAM_ALREADY_EXISTS (err u103))
(define-constant ERR_INVALID_PARAMS (err u104))

;; Stream data structure
(define-map streams
  { stream-id: uint }
  {
    sender: principal,
    recipient: principal,
    rate-per-second: uint,     ;; Amount per second in micro-units
    start-time: uint,          ;; Block timestamp when stream started
    total-deposit: uint,       ;; Total amount deposited for this stream
    withdrawn: uint,           ;; Amount already withdrawn by recipient
    is-active: bool            ;; Stream status
  }
)

;; Track balances for each user
(define-map user-balances
  { user: principal }
  { balance: uint }
)

;; Track stream counter
(define-data-var stream-counter uint u0)

;; Helper function to get current block timestamp
(define-read-only (get-current-time)
  block-height ;; Using block height as time proxy
)

;; Get user balance
(define-read-only (get-balance (user principal))
  (default-to u0 (get balance (map-get? user-balances { user: user })))
)

;; Get stream details
(define-read-only (get-stream (stream-id uint))
  (map-get? streams { stream-id: stream-id })
)

;; Calculate available amount for withdrawal
(define-read-only (get-available-amount (stream-id uint))
  (match (map-get? streams { stream-id: stream-id })
    stream-data
    (let (
      (current-time (get-current-time))
      (start-time (get start-time stream-data))
      (rate (get rate-per-second stream-data))
      (withdrawn (get withdrawn stream-data))
      (total-deposit (get total-deposit stream-data))
      (is-active (get is-active stream-data))
    )
    (if is-active
      (let (
        (elapsed-time (if (>= current-time start-time) (- current-time start-time) u0))
        (total-earned (* elapsed-time rate))
        (available (if (> total-earned withdrawn) (- total-earned withdrawn) u0))
        (max-available (if (> total-deposit withdrawn) (- total-deposit withdrawn) u0))
      )
      (if (< available max-available) available max-available))
      u0))
    u0)
)

;; Deposit funds to user balance
(define-public (deposit (amount uint))
  (let (
    (current-balance (get-balance tx-sender))
    (new-balance (+ current-balance amount))
  )
  (map-set user-balances
    { user: tx-sender }
    { balance: new-balance }
  )
  (ok new-balance))
)

;; Withdraw funds from user balance
(define-public (withdraw (amount uint))
  (let (
    (current-balance (get-balance tx-sender))
  )
  (if (>= current-balance amount)
    (begin
      (map-set user-balances
        { user: tx-sender }
        { balance: (- current-balance amount) }
      )
      (ok (- current-balance amount)))
    ERR_INSUFFICIENT_BALANCE))
)

;; Create a new payment stream
(define-public (create-stream 
  (recipient principal) 
  (rate-per-second uint) 
  (deposit-amount uint))
  (let (
    (stream-id (+ (var-get stream-counter) u1))
    (sender-balance (get-balance tx-sender))
    (current-time (get-current-time))
  )
  (asserts! (> rate-per-second u0) ERR_INVALID_PARAMS)
  (asserts! (> deposit-amount u0) ERR_INVALID_PARAMS)
  (asserts! (>= sender-balance deposit-amount) ERR_INSUFFICIENT_BALANCE)
  (asserts! (is-none (map-get? streams { stream-id: stream-id })) ERR_STREAM_ALREADY_EXISTS)
  
  ;; Deduct deposit from sender balance
  (map-set user-balances
    { user: tx-sender }
    { balance: (- sender-balance deposit-amount) }
  )
  
  ;; Create stream
  (map-set streams
    { stream-id: stream-id }
    {
      sender: tx-sender,
      recipient: recipient,
      rate-per-second: rate-per-second,
      start-time: current-time,
      total-deposit: deposit-amount,
      withdrawn: u0,
      is-active: true
    }
  )
  
  ;; Update stream counter
  (var-set stream-counter stream-id)
  
  (ok stream-id)))

;; Withdraw available funds from a stream
(define-public (withdraw-from-stream (stream-id uint))
  (match (map-get? streams { stream-id: stream-id })
    stream-data
    (let (
      (recipient (get recipient stream-data))
      (available-amount (get-available-amount stream-id))
      (current-withdrawn (get withdrawn stream-data))
      (recipient-balance (get-balance recipient))
    )
    (asserts! (is-eq tx-sender recipient) ERR_UNAUTHORIZED)
    (asserts! (get is-active stream-data) ERR_UNAUTHORIZED)
    (asserts! (> available-amount u0) ERR_INSUFFICIENT_BALANCE)
    
    ;; Update stream withdrawn amount
    (map-set streams
      { stream-id: stream-id }
      (merge stream-data { withdrawn: (+ current-withdrawn available-amount) })
    )
    
    ;; Add to recipient balance
    (map-set user-balances
      { user: recipient }
      { balance: (+ recipient-balance available-amount) }
    )
    
    (ok available-amount))
    ERR_STREAM_NOT_FOUND)
)

;; Cancel a stream and refund remaining balance (sender only)
(define-public (cancel-stream (stream-id uint))
  (match (map-get? streams { stream-id: stream-id })
    stream-data
    (let (
      (sender (get sender stream-data))
      (available-for-recipient (get-available-amount stream-id))
      (total-deposit (get total-deposit stream-data))
      (withdrawn (get withdrawn stream-data))
      (refund-amount (if (> (- total-deposit withdrawn) available-for-recipient)
                       (- (- total-deposit withdrawn) available-for-recipient)
                       u0))
      (sender-balance (get-balance sender))
      (recipient-balance (get-balance (get recipient stream-data)))
    )
    (asserts! (is-eq tx-sender sender) ERR_UNAUTHORIZED)
    (asserts! (get is-active stream-data) ERR_UNAUTHORIZED)
    
    ;; Mark stream as inactive
    (map-set streams
      { stream-id: stream-id }
      (merge stream-data { is-active: false })
    )
    
    ;; Refund remaining balance to sender
    (if (> refund-amount u0)
      (map-set user-balances
        { user: sender }
        { balance: (+ sender-balance refund-amount) })
      true)
    
    ;; Give available amount to recipient
    (if (> available-for-recipient u0)
      (begin
        (map-set user-balances
          { user: (get recipient stream-data) }
          { balance: (+ recipient-balance available-for-recipient) })
        (map-set streams
          { stream-id: stream-id }
          (merge stream-data { 
            withdrawn: (+ withdrawn available-for-recipient),
            is-active: false 
          })))
      true)
    
    (ok { refunded: refund-amount, paid-to-recipient: available-for-recipient }))
    ERR_STREAM_NOT_FOUND)
)

;; Get total stream count
(define-read-only (get-total-streams)
  (var-get stream-counter)
)