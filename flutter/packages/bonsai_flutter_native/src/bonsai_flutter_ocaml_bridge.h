#ifndef BONSAI_FLUTTER_OCAML_BRIDGE_H
#define BONSAI_FLUTTER_OCAML_BRIDGE_H

#include "bonsai_flutter_native.h"

typedef struct bf_ocaml_response {
  bf_status status;
  bf_error_code error_code;
  uint8_t *data;
  size_t length;
  uint64_t revision;
  int64_t next_wakeup_ns;
  char *error;
} bf_ocaml_response;

int bf_ocaml_bridge_initialize(char *error, size_t error_capacity);

bf_status bf_ocaml_bridge_create(const uint8_t *config,
                                 size_t config_length,
                                 uint64_t *handle,
                                 char *error,
                                 size_t error_capacity);

bf_status bf_ocaml_bridge_step(uint64_t handle,
                               const uint8_t *input,
                               size_t input_length,
                               bf_ocaml_response *response);

bf_status bf_ocaml_bridge_frame_presented(uint64_t handle,
                                          uint64_t revision,
                                          bf_ocaml_response *response);

void bf_ocaml_bridge_response_release(bf_ocaml_response *response);
void bf_ocaml_bridge_destroy(uint64_t handle);

#endif
