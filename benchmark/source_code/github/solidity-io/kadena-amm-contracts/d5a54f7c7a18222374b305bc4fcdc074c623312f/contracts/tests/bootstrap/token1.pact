(namespace (read-msg "ns"))

(module token1 GOVERNANCE
  @model
  [
    (property (forall (k:string)
      (when (row-written ledger k)
        (row-enforced ledger 'guard k)))
      { 'except: [ transfer ] })
  ]

  (implements fungible-v2)

  (defcap GOVERNANCE ()
    (enforce-guard constants.ADMIN_GUARD))

  (defcap TRANSFER:bool
    ( sender:string
      receiver:string
      amount:decimal
    )
    @managed amount TRANSFER-mgr
    (enforce-guard (at 'guard (read ledger (key sender))))
    true)

  (defun TRANSFER-mgr:decimal
    ( managed:decimal
      requested:decimal
    )
    (let ((newbal (- managed requested)))
      (enforce (>= newbal 0.0)
        (format "TRANSFER exceeded for balance {}" [managed]))
      newbal))

  (defun transfer:string
    ( sender:string
      receiver:string
      amount:decimal
    )
    (with-capability (TRANSFER sender receiver amount)
      (with-read ledger (key sender) { 'balance := balance }
        (enforce (>= balance amount) "Insufficient funds")
        (with-read ledger (key receiver) { 'balance := rbalance }
          (update ledger (key sender) { 'balance: (- balance amount) })
          (update ledger (key receiver) { 'balance: (+ rbalance amount) })
          "Transfer successful"))))

  (defun transfer-create:string
    ( sender:string
      receiver:string
      receiver-guard:guard
      amount:decimal
    )
    (with-capability (TRANSFER sender receiver amount)
      (with-read ledger (key sender) { 'balance := balance }
        (enforce (>= balance amount) "Insufficient funds")
        (with-default-read ledger (key receiver) { 'balance: 0.0, 'guard: receiver-guard } { 'balance := rbalance }
          (update ledger (key sender) { 'balance: (- balance amount) })
          (update ledger (key receiver) { 'balance: (+ rbalance amount) })
          "Transfer successful"))))

  (defpact transfer-crosschain:string
    ( sender:string
      receiver:string
      receiver-guard:guard
      target-chain:string
      amount:decimal
    )
    (step
      (with-read ledger (key sender) { 'balance := balance }
        (enforce (>= balance amount) "Insufficient funds")
        (update ledger (key sender) { 'balance: (- balance amount) })
        (yield { 'receiver: receiver
               , 'receiver-guard: receiver-guard
               , 'amount: amount })))
    (step
      (with-default-read ledger (key receiver) { 'balance: 0.0, 'guard: receiver-guard } { 'balance := rbalance }
        (update ledger (key receiver) { 'balance: (+ rbalance amount) })
        "Cross-chain transfer successful")))

  (defun get-balance:decimal
    ( account:string )
    (at 'balance (read ledger (key account))))

  (defun details:object{fungible-v2.account-details}
    ( account:string )
    (read ledger (key account)))

  (defun precision:integer
    ()
    12)

  (defun enforce-unit:bool
    ( amount:decimal )
    (= (floor amount (precision)) amount))

  (defun create-account:string
    ( account:string
      guard:guard
    )
    (insert ledger (key account)
      { "balance": 0.0
      , "guard": guard
      , "account": account
      })
    "Account created")

  (defun rotate:string
    ( account:string
      new-guard:guard
    )
    (with-read ledger (key account) { 'guard := old-guard }
      (enforce-guard old-guard)
      (update ledger (key account) { 'guard: new-guard })
      "Guard rotated"))

  (defun key (account:string)
    (format "{}" [account]))

  (defcap MINT (account:string amount:decimal)
    (enforce-guard (read-keyset "admin-keyset"))
    true)

  (defun mint:string (account:string amount:decimal)
    (with-capability (MINT account amount)
      (with-read ledger (key account) { 'balance := balance }
        (update ledger (key account) { 'balance: (+ balance amount) })
        "Mint successful")))

  (deftable ledger:{fungible-v2.account-details})) 