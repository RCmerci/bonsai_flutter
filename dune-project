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
  (ocaml (= 5.3.0))
  (dune (>= 3.17))
  (bonsai (= v0.18~preview.130.106+341))
  (core (= v0.18~preview.130.106+341))))

(package
 (name bonsai_flutter_test)
 (synopsis "Headless test handles for bonsai_flutter applications")
 (description
  "Renderer-independent queries and interactions for testing Bonsai Flutter applications.")
 (depends
  (ocaml (= 5.3.0))
  (dune (>= 3.17))
  (bonsai_flutter (= :version))
  (bonsai (= v0.18~preview.130.106+341))
  (core (= v0.18~preview.130.106+341))))
