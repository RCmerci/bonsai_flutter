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
  (base (and (>= v0.17) (< v0.18~)))
  (bonsai (and (>= v0.17) (< v0.18~)))
  (core (and (>= v0.17) (< v0.18~)))
  (incr_dom (and (>= v0.17) (< v0.18~)))
  (sqlite3 (= 5.4.0))
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
  (virtual_dom (and (>= v0.17) (< v0.18~)))))
