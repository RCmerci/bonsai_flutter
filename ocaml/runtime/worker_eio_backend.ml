type environment = Eio_unix.Stdenv.base

let run main = Eio_posix.run main
let stdenv environment = environment
let mono_clock environment = environment#mono_clock
let net environment = (environment#net :> [ `Generic ] Eio.Net.ty Eio.Resource.t)
let fs environment = environment#fs
