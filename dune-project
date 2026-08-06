(lang dune 3.17)
(name bonsai_flutter)
(generate_opam_files false)
(implicit_transitive_deps false)
(license MIT)
(source
 (github rcmerci/bonsai_flutter))

(package
 (name bonsai_flutter)
 (synopsis "A native Flutter backend for Jane Street Bonsai")
 (description
  "An OCaml-first UI framework that reconciles Bonsai views into atomic binary patches rendered by Flutter.")
 (depends
  (ocaml (= 5.1.1))
  (dune (>= 3.17))
  (eio (= 1.2))
  (eio_posix (= 1.2))
  (mtime (= 2.1.0))
  (base (and (>= v0.17) (< v0.18~)))
  (bonsai (and (>= v0.17) (< v0.18~)))
  (core (and (>= v0.17) (< v0.18~)))
  (incr_dom (and (>= v0.17) (< v0.18~)))
  (virtual_dom (and (>= v0.17) (< v0.18~)))))

(package
 (name bonsai_flutter_test)
 (synopsis "Headless test handles for bonsai_flutter applications")
 (description
  "Renderer-independent queries and interactions for testing Bonsai Flutter applications.")
 (depends
  (ocaml (= 5.1.1))
  (dune (>= 3.17))
  (bonsai_flutter (= :version))
  (base (and (>= v0.17) (< v0.18~)))
  (bonsai (and (>= v0.17) (< v0.18~)))
  (core (and (>= v0.17) (< v0.18~)))
  (incr_dom (and (>= v0.17) (< v0.18~)))
  (sqlite3 (= 5.4.0))
  (virtual_dom (and (>= v0.17) (< v0.18~)))))

(package
 (name bonsai_flutter_network_example)
 (synopsis "Secure HTTPS and WebSocket example for bonsai_flutter")
 (description
  "An OCaml-owned HTTPS and secure WebSocket example using the pure OCaml tls-eio stack.")
 (depends
  (ocaml (= 5.1.1))
  (dune (>= 3.17))
  (bonsai_flutter (= :version))
  (alcotest (and :with-test (= 1.7.0)))
  (base (and (>= v0.17) (< v0.18~)))
  (bonsai (and (>= v0.17) (< v0.18~)))
  (core (and (>= v0.17) (< v0.18~)))
  (incr_dom (and (>= v0.17) (< v0.18~)))
  (virtual_dom (and (>= v0.17) (< v0.18~)))
  (eio (= 1.2))
  (eio_posix (= 1.2))
  (bigstringaf (= 0.10.0))
  (cstruct (= 6.2.0))
  (digestif (= 1.3.1))
  (domain-name (= 0.5.0))
  (gluten (= 0.5.2))
  (gluten-eio (= 0.5.2))
  (httpun (= 0.2.0))
  (httpun-eio (= 0.2.0))
  (httpun-ws (= 0.2.0))
  (ca-certs-nss (= 3.126))
  (mirage-crypto-rng (= 2.2.0))
  (ptime (= 1.2.0))
  (tls (= 2.1.2))
  (tls-eio (= 2.1.2))
  (uri (= 4.4.0))
  (x509 (= 1.1.1))))

(package
 (name bonsai_flutter_tool)
 (synopsis "OCaml-first tooling for Bonsai Flutter applications")
 (description
  "The bonsai-flutter command initializes, validates, builds, and runs external Bonsai Flutter applications.")
 (depends
  (ocaml (= 5.1.1))
  (dune (>= 3.17))
  (alcotest (and :with-test (= 1.7.0)))
  (cmdliner (>= 1.3.0))
  (digestif (= 1.3.1))
  (sexplib (and (>= v0.17) (< v0.18~)))))
