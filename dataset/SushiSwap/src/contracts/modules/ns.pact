;; This file creates the principal namespace for the protocol based on our
;; admin keyset.
(let ((ns-name (ns.create-principal-namespace (read-keyset "admin-keyset"))))
  (define-namespace ns-name (read-keyset "admin-keyset") (read-keyset "admin-keyset"))
  (namespace ns-name))