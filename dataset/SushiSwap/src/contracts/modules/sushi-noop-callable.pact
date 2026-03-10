(namespace (read-msg "ns"))

(module sushi-noop-callable GOVERNANCE
    "Noop implementation of swap-callable-v1"
    (implements sushi-callable-v1)
    (defcap GOVERNANCE () (enforce-guard constants.ADMIN_GUARD))
    (defun swap-call:bool
      ( token-in:module{fungible-v2}
        token-out:module{fungible-v2}
        amount-out:decimal
        sender:string
        recipient:string
        recipient-guard:guard
      )
      "Noop implementation"
      true
    )
  )