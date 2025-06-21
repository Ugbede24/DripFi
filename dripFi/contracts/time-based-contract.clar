;; Micropayment Streaming Contract 
;; Advanced features: pause/resume, finite streams, user tracking, top-up

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_STREAM_NOT_FOUND (err u101))
(define-constant ERR_INSUFFICIENT_BALANCE (err u102))
(define-constant ERR_STREAM_ALREADY_EXISTS (err u103))
(define-constant ERR_INVALID_PARAMS (err u104))
(define-constant ERR_STREAM_ENDED (err u105))
(define-constant ERR_STREAM_PAUSED (err u106))

;; Stream data structure
(define-map streams
  { stream-id: uint }
  {
    sender: principal,
    recipient: principal,
    rate-per-second: uint,     ;; Amount per second in micro-units
    start-time: uint,          ;; Block timestamp when stream started
    end-time: (optional uint), ;; Optional end time for finite streams
    total-deposit: uint,       ;; Total amount deposited for this stream
    withdrawn: uint,           ;; Amount already withdrawn by recipient
    is-active: bool,           ;; Stream status
    is-paused: bool,           ;; Pause status
    pause-time: (optional uint) ;; When stream was paused
  }
)

;; Track balances for each user
(define-map user-balances
  { user: principal }
  { balance: uint }
)

;; Track stream counter
(define-data-var stream-counter uint u0)

;; Track total streams per user (for enumeration)
(define-map user-stream-count
  { user: principal }
  { sent-count: uint, received-count: uint }
)

;; Map user to their stream IDs
(define-map user-sent-streams
  { user: principal, index: uint }
  { stream-id: uint }
)

(define-map user-received-streams
  { user: principal, index: uint }
  { stream-id: uint }
)

;; Events
(define-data-var last-event-id uint u0)

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
      (end-time (get end-time stream-data))
      (rate (get rate-per-second stream-data))
      (withdrawn (get withdrawn stream-data))
      (total-deposit (get total-deposit stream-data))
      (is-active (get is-active stream-data))
      (is-paused (get is-paused stream-data))
      (pause-time (get pause-time stream-data))
    )
    (if (and is-active (not is-paused))
      (let (
        (effective-end-time (match end-time
          some-end some-end
          current-time))
        (actual-end-time (if (> effective-end-time current-time) current-time effective-end-time))
        (elapsed-time (if (>= actual-end-time start-time) (- actual-end-time start-time) u0))
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
  (deposit-amount uint)
  (duration (optional uint)))
  (let (
    (stream-id (+ (var-get stream-counter) u1))
    (sender-balance (get-balance tx-sender))
    (current-time (get-current-time))
    (end-time (match duration
      some-duration (some (+ current-time some-duration))
      none))
    (sender-count (default-to { sent-count: u0, received-count: u0 } 
                   (map-get? user-stream-count { user: tx-sender })))
    (recipient-count (default-to { sent-count: u0, received-count: u0 } 
                      (map-get? user-stream-count { user: recipient })))
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
      end-time: end-time,
      total-deposit: deposit-amount,
      withdrawn: u0,
      is-active: true,
      is-paused: false,
      pause-time: none
    }
  )
  
  ;; Update stream counter
  (var-set stream-counter stream-id)
  
  ;; Update user stream mappings
  (map-set user-sent-streams
    { user: tx-sender, index: (get sent-count sender-count) }
    { stream-id: stream-id }
  )
  
  (map-set user-received-streams
    { user: recipient, index: (get received-count recipient-count) }
    { stream-id: stream-id }
  )
  
  ;; Update stream counts
  (map-set user-stream-count
    { user: tx-sender }
    { sent-count: (+ (get sent-count sender-count) u1), 
      received-count: (get received-count sender-count) }
  )
  
  (map-set user-stream-count
    { user: recipient }
    { sent-count: (get sent-count recipient-count), 
      received-count: (+ (get received-count recipient-count) u1) }
  )
  
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
    (asserts! (get is-active stream-data) ERR_STREAM_ENDED)
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

;; Pause a stream (sender only)
(define-public (pause-stream (stream-id uint))
  (match (map-get? streams { stream-id: stream-id })
    stream-data
    (let (
      (sender (get sender stream-data))
      (current-time (get-current-time))
    )
    (asserts! (is-eq tx-sender sender) ERR_UNAUTHORIZED)
    (asserts! (get is-active stream-data) ERR_STREAM_ENDED)
    (asserts! (not (get is-paused stream-data)) ERR_STREAM_PAUSED)
    
    (map-set streams
      { stream-id: stream-id }
      (merge stream-data { 
        is-paused: true,
        pause-time: (some current-time)
      })
    )
    
    (ok true))
    ERR_STREAM_NOT_FOUND)
)

;; Resume a paused stream (sender only)
(define-public (resume-stream (stream-id uint))
  (match (map-get? streams { stream-id: stream-id })
    stream-data
    (let (
      (sender (get sender stream-data))
      (current-time (get-current-time))
      (pause-time (get pause-time stream-data))
    )
    (asserts! (is-eq tx-sender sender) ERR_UNAUTHORIZED)
    (asserts! (get is-active stream-data) ERR_STREAM_ENDED)
    (asserts! (get is-paused stream-data) ERR_STREAM_PAUSED)
    
    ;; Adjust start time to account for paused duration
    (let (
      (paused-duration (match pause-time
        some-pause-time (- current-time some-pause-time)
        u0))
      (new-start-time (+ (get start-time stream-data) paused-duration))
      (new-end-time (match (get end-time stream-data)
        some-end (some (+ some-end paused-duration))
        none))
    )
    
    (map-set streams
      { stream-id: stream-id }
      (merge stream-data { 
        is-paused: false,
        pause-time: none,
        start-time: new-start-time,
        end-time: new-end-time
      })
    )
    
    (ok true)))
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
    (asserts! (get is-active stream-data) ERR_STREAM_ENDED)
    
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

;; Top up an existing stream (sender only)
(define-public (top-up-stream (stream-id uint) (amount uint))
  (match (map-get? streams { stream-id: stream-id })
    stream-data
    (let (
      (sender (get sender stream-data))
      (sender-balance (get-balance sender))
      (current-deposit (get total-deposit stream-data))
    )
    (asserts! (is-eq tx-sender sender) ERR_UNAUTHORIZED)
    (asserts! (get is-active stream-data) ERR_STREAM_ENDED)
    (asserts! (>= sender-balance amount) ERR_INSUFFICIENT_BALANCE)
    (asserts! (> amount u0) ERR_INVALID_PARAMS)
    
    ;; Deduct from sender balance
    (map-set user-balances
      { user: sender }
      { balance: (- sender-balance amount) }
    )
    
    ;; Update stream deposit
    (map-set streams
      { stream-id: stream-id }
      (merge stream-data { total-deposit: (+ current-deposit amount) })
    )
    
    (ok (+ current-deposit amount)))
    ERR_STREAM_NOT_FOUND)
)

;; Get stream count for a user
(define-read-only (get-user-stream-count (user principal))
  (default-to { sent-count: u0, received-count: u0 }
    (map-get? user-stream-count { user: user }))
)

;; Get stream ID by user and index
(define-read-only (get-user-sent-stream (user principal) (index uint))
  (map-get? user-sent-streams { user: user, index: index })
)

(define-read-only (get-user-received-stream (user principal) (index uint))
  (map-get? user-received-streams { user: user, index: index })
)

;; Get total stream count
(define-read-only (get-total-streams)
  (var-get stream-counter)
)

;; Check if stream has ended naturally
(define-read-only (has-stream-ended (stream-id uint))
  (match (map-get? streams { stream-id: stream-id })
    stream-data
    (let (
      (current-time (get-current-time))
      (end-time (get end-time stream-data))
      (total-deposit (get total-deposit stream-data))
      (rate (get rate-per-second stream-data))
    )
    (or 
      (not (get is-active stream-data))
      (match end-time
        some-end (>= current-time some-end)
        false)
      ;; Or if all funds have been streamed
      (>= (get withdrawn stream-data) total-deposit)))
    false)
)