(namespace (read-msg "ns"))

(module sushi-exchange-tokens GOVERNANCE

  @model
    [
     ;; prop-supply-write-issuer-guard
     (property
      (forall (token:string)
        (when (row-written supplies token)
          (enforce-guard (at 'guard (read issuers ISSUER_KEY)))))
      { 'except:
        [ transfer-crosschain ;; VACUOUS
          debit               ;; PRIVATE
          credit              ;; PRIVATE
          update-supply       ;; PRIVATE
        ] })

     ;; prop-ledger-write-guard
     (property
      (forall (key:string)
        (when (row-written ledger key)
          (or
            (enforce-guard (at 'guard (read issuers ISSUER_KEY)))    ;; issuer write
            (enforce-guard (at 'guard (read ledger key))))))          ;; owner write
      { 'except:
        [ transfer-crosschain ;; VACUOUS
          debit               ;; PRIVATE
          credit              ;; PRIVATE
          create-account      ;; prop-ledger-conserves-mass, prop-supply-conserves-mass
          transfer            ;; prop-ledger-conserves-mass, prop-supply-conserves-mass
          transfer-create     ;; prop-ledger-conserves-mass, prop-supply-conserves-mass
        ] })


     ;; prop-ledger-conserves-mass
     (property
      (= (column-delta ledger 'balance) 0.0)
      { 'except:
         [ transfer-crosschain ;; VACUOUS
           debit               ;; PRIVATE
           credit              ;; PRIVATE
           burn                ;; prop-ledger-write-guard
           mint                ;; prop-ledger-write-guard
         ] } )

      ;; prop-supply-conserves-mass
      (property
       (= (column-delta supplies 'supply) 0.0)
       { 'except:
        [ transfer-crosschain ;; VACUOUS
          debit               ;; PRIVATE
          credit              ;; PRIVATE
          update-supply       ;; PRIVATE
          burn                ;; prop-ledger-write-guard
          mint                ;; prop-ledger-write-guard
       ] } )
    ]


  (defcap GOVERNANCE ()
    (enforce-guard constants.ADMIN_GUARD))


  (defcap ROTATE (token:string account:string new-guard:guard)
    (with-read ledger (key token account)
      { "guard" := old-guard }
      
      (enforce-guard old-guard)
      
      (enforce (= "guard" (typeof new-guard)) "New guard must be a valid guard")
    )
  )

  (defschema entry
    token:string
    account:string
    balance:decimal
    guard:guard
    )

  (deftable ledger:{entry})

  ;; @lint-ignore
  (use fungible-util)

  (defschema issuer
    guard:guard
  )

  (deftable issuers:{issuer})

  (defschema supply
    supply:decimal
    )

  (deftable supplies:{supply})

  (defconst ISSUER_KEY "I")

  (defcap DEBIT (token:string sender:string)
    (enforce-guard
      (at 'guard
        (read ledger (key token sender)))))

  (defun get-guard:guard (token:string sender:string)
    (at 'guard (read ledger (key token sender)))
  )

  (defcap CREDIT (receiver:string)
    (enforce (> (length receiver) 0) "Receiver cannot be blank")
    true)

  (defcap UPDATE_SUPPLY ()
    "private cap for update-supply"
    true)

  (defcap ISSUE ()
    (enforce-guard (at 'guard (read issuers ISSUER_KEY)))
  )

  (defcap MINT_EVENT
    (token:string
     account:string
     amount:decimal)
    @doc "Event emitted when tokens are minted"
    @event true)

  (defcap MINT (token:string account:string amount:decimal)
    @managed ;; one-shot for a given amount
    (let ((issue-granted (try false (compose-capability (ISSUE)))))
      (enforce issue-granted "Capability ISSUE not granted")
      true))

  (defcap BURN (token:string account:string amount:decimal)
    @managed ;; one-shot for a given amount
    (compose-capability (ISSUE))
  )

  (defcap BURN_EVENT
    (token:string
     account:string
     amount:decimal)
    @doc "Event emitted when tokens are burned"
    @event true)

  (defun init-issuer (guard:guard)
    (with-capability (GOVERNANCE)
      (insert issuers ISSUER_KEY {'guard: guard}))
  )

  (defun override-issuer (guard:guard)
    (with-capability (GOVERNANCE)
      (update issuers ISSUER_KEY {'guard: guard}))
  )

  (defun key ( token:string account:string )
    (format "{}:{}" [token account])
  )

  (defun total-supply:decimal (token:string)
    (with-default-read supplies token
      { 'supply : 0.0 }
      { 'supply := s }
      s)
  )

  (defcap TRANSFER:bool
    ( token:string
      sender:string
      receiver:string
      amount:decimal
    )
    @managed amount TRANSFER-mgr
    (enforce-unit token amount)
    (compose-capability (DEBIT token sender))
    (compose-capability (CREDIT receiver))
  )

  (defcap TRANSFER_EVENT
    (token:string
     sender:string
     receiver:string
     amount:decimal)
    @doc "Event emitted when tokens are transferred"
    @event true)

  (defun TRANSFER-mgr:decimal
    ( managed:decimal
      requested:decimal
    )

    (let ((newbal (- managed requested)))
      (enforce (>= newbal 0.0)
        (format "TRANSFER exceeded for balance {}" [managed]))
      newbal)
  )

  (defconst MINIMUM_PRECISION 12)

  (defun enforce-unit:bool (token:string amount:decimal)
    (enforce
      (= (floor amount (precision token))
         amount)
      "precision violation")
  )

  (defun truncate:decimal (token:string amount:decimal)
    (floor amount (precision token))
  )


  (defun create-account:string
    ( token:string
      account:string
      guard:guard
    )
    (enforce-valid-account account)
    (enforce-reserved account guard)
    (insert ledger (key token account)
      { "balance" : 0.0
      , "guard"   : guard
      , "token" : token
      , "account" : account
      })
    )

  (defun get-balance:decimal (token:string account:string)
    (at 'balance (read ledger (key token account)))
    )

  (defun details
    ( token:string account:string )
    (read ledger (key token account))
    )

  (defun rotate:string (token:string account:string new-guard:guard)
    (with-capability (ROTATE token account new-guard)
      (update ledger (key token account)
        { "guard" : new-guard })
      
      "Guard successfully rotated."
    )
  )


  (defun precision:integer (token:string)
    MINIMUM_PRECISION)

  (defun transfer:string
    ( token:string
      sender:string
      receiver:string
      amount:decimal
    )
    (with-read ledger (key token receiver)
    {"guard" := g}
    (transfer-create token sender receiver g amount)
    )
    )
    
  (defun transfer-create:string
    ( token:string
      sender:string
      receiver:string
      receiver-guard:guard
      amount:decimal
      )
        
        (enforce-valid-transfer sender receiver (precision token) amount)
        
    (with-capability (TRANSFER token sender receiver amount)
    (emit-event (TRANSFER_EVENT token sender receiver amount))
      (debit token sender amount)
      (credit token receiver receiver-guard amount))
    )

  (defun mint:string
    ( token:string
      account:string
      guard:guard
      amount:decimal
    )
    (with-capability (MINT token account amount)
      (with-capability (CREDIT account)
        (emit-event (MINT_EVENT token account amount))
        (credit token account guard amount)))
  )

  (defun burn:string
    ( token:string
      account:string
      amount:decimal
    )
    (with-capability (BURN token account amount)
      (with-capability (DEBIT token account)
        (emit-event (BURN_EVENT token account amount))
        (debit token account amount)))
  )

  (defun debit:string
    ( token:string
      account:string
      amount:decimal
    )

    (require-capability (DEBIT token account))

    (enforce-unit token amount)

    (with-read ledger (key token account)
      { "balance" := balance }

      (enforce (<= amount balance) "Insufficient funds")

      (update ledger (key token account)
        { "balance" : (- balance amount) }
        ))
    (with-capability (UPDATE_SUPPLY)
      (update-supply token (- amount)))
  )


  (defun credit:string
    ( token:string
      account:string
      guard:guard
      amount:decimal
    )

    (require-capability (CREDIT account))

    (enforce-unit token amount)

    (with-default-read ledger (key token account)
      { "balance" : -1.0, "guard" : guard }
      { "balance" := balance, "guard" := retg }
      (enforce (= retg guard)
        "account guards do not match")

      (let ((is-new
        (if (= balance -1.0)
            (enforce-reserved account guard)
          false)))

        (write ledger (key token account)
          { "balance" : (if is-new amount (+ balance amount))
          , "guard"   : retg
          , "token"   : token
          , "account" : account
          }))

      (with-capability (UPDATE_SUPPLY)
        (update-supply token amount))
      ))

  (defun update-supply (token:string amount:decimal)
    (with-default-read supplies token
      { 'supply: 0.0 }
      { 'supply := s }
      (enforce (>= (+ s amount) 0.0) "Supply cannot go below zero")
      (require-capability (UPDATE_SUPPLY))
      (write supplies token {'supply: (+ s amount)}))
  )

  (defpact transfer-crosschain:string
    ( token:string
      sender:string
      receiver:string
      receiver-guard:guard
      target-chain:string
      amount:decimal )
    (step (format "{}" [(enforce false "cross chain not supported")]))
    )

  (defun get-tokens ()
    "Get all token identifiers"
    (keys supplies))

)