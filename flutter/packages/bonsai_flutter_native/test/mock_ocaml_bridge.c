#include "../src/bonsai_flutter_ocaml_bridge.h"

#include <stdlib.h>
#include <string.h>

static int destroy_count = 0;

int bf_ocaml_bridge_initialize(char *error, size_t error_capacity) {
  (void)error;
  (void)error_capacity;
  return 1;
}

bf_status bf_ocaml_bridge_create(const uint8_t *config,
                                 size_t config_length,
                                 uint64_t *handle,
                                 char *error,
                                 size_t error_capacity) {
  const char expected[] = "counter";
  (void)error;
  (void)error_capacity;
  if (config_length != sizeof(expected) - 1 ||
      memcmp(config, expected, sizeof(expected) - 1) != 0) {
    return BF_STATUS_FATAL_ERROR;
  }
  *handle = 42;
  return BF_STATUS_OK;
}

static bf_status respond(bf_ocaml_response *response,
                         const char *payload,
                         uint64_t revision) {
  size_t length = strlen(payload);
  response->data = (uint8_t *)malloc(length);
  if (response->data == NULL) {
    return BF_STATUS_FATAL_ERROR;
  }
  memcpy(response->data, payload, length);
  response->length = length;
  response->revision = revision;
  response->next_wakeup_ns = -1;
  response->error = NULL;
  response->status = BF_STATUS_OK;
  response->error_code = BF_ERROR_NONE;
  return BF_STATUS_OK;
}

bf_status bf_ocaml_bridge_step(uint64_t handle,
                               const uint8_t *input,
                               size_t input_length,
                               bf_ocaml_response *response) {
  (void)input;
  (void)input_length;
  if (handle != 42) {
    return BF_STATUS_FATAL_ERROR;
  }
  return respond(response, "frame", 1);
}

bf_status bf_ocaml_bridge_frame_presented(uint64_t handle,
                                          uint64_t revision,
                                          bf_ocaml_response *response) {
  if (handle != 42 || revision != 1) {
    return BF_STATUS_FATAL_ERROR;
  }
  response->status = BF_STATUS_OK;
  response->error_code = BF_ERROR_NONE;
  response->data = NULL;
  response->length = 0;
  response->revision = revision;
  response->next_wakeup_ns = -1;
  response->error = NULL;
  return BF_STATUS_OK;
}

void bf_ocaml_bridge_response_release(bf_ocaml_response *response) {
  free(response->data);
  free(response->error);
  memset(response, 0, sizeof(*response));
}

void bf_ocaml_bridge_destroy(uint64_t handle) {
  if (handle == 42) {
    destroy_count += 1;
  }
}

int bf_mock_destroy_count(void) { return destroy_count; }
