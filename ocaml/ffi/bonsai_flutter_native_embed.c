#define BF_WITH_OCAML

#include "bonsai_flutter_native.c"
#include "bonsai_flutter_ocaml_bridge.c"

CAMLprim value bf_native_embed_link_anchor(value unit) {
  (void)unit;
  return Val_unit;
}
