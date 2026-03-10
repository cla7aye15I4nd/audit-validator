(namespace (read-msg "ns"))
(define-keyset (+ (read-msg "ns") ".admin-keyset") (read-keyset "admin-keyset"))

(module constants GOVERNANCE
  (defcap GOVERNANCE:bool () (enforce-guard ADMIN_GUARD))

  (defconst ADMIN_KEYSET (+ (read-msg "ns") ".admin-keyset"))
  (defconst ADMIN_GUARD (keyset-ref-guard ADMIN_KEYSET))
)

(enforce-guard ADMIN_GUARD)