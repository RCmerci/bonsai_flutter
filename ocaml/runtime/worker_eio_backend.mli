(** Eio backend selected for the native Worker Domain. *)

type environment

val run : (environment -> 'a) -> 'a
val stdenv : environment -> Eio_unix.Stdenv.base
val mono_clock : environment -> Eio.Time.Mono.ty Eio.Resource.t
val net : environment -> [ `Generic ] Eio.Net.ty Eio.Resource.t
val fs : environment -> Eio.Fs.dir_ty Eio.Path.t
