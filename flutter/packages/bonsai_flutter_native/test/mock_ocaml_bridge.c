#include "../src/bonsai_flutter_ocaml_bridge.h"

#include <stdlib.h>
#include <string.h>

static int destroy_count = 0;
static int pump_count = 0;
static int presentation_succeeded_count = 0;
static int presentation_rejected_count = 0;
static int64_t last_monotonic_now_ns = -1;
static uint64_t last_presentation_id = 0;
static uint64_t last_revision = 0;
static int32_t last_rejection_reason = -1;

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
                         uint64_t presentation_id,
                         uint64_t revision) {
  size_t length = strlen(payload);
  if (length == 0) {
    response->data = NULL;
  } else {
    response->data = (uint8_t *)malloc(length);
    if (response->data == NULL) {
      return BF_STATUS_FATAL_ERROR;
    }
    memcpy(response->data, payload, length);
  }
  response->length = length;
  response->presentation_id = presentation_id;
  response->revision = revision;
  response->error = NULL;
  response->status = BF_STATUS_OK;
  response->error_code = BF_ERROR_NONE;
  return BF_STATUS_OK;
}

bf_status bf_ocaml_bridge_pump(uint64_t handle,
                               int64_t monotonic_now_ns,
                               const uint8_t *input,
                               size_t input_length,
                               bf_ocaml_response *response) {
  if (handle != 42) {
    return BF_STATUS_FATAL_ERROR;
  }
  pump_count += 1;
  last_monotonic_now_ns = monotonic_now_ns;
  if (input_length == 1 && input != NULL && input[0] == 0xee) {
    bf_status status = respond(response, "recoverable", 8, 2);
    if (status != BF_STATUS_OK) {
      return status;
    }
    response->status = BF_STATUS_RECOVERABLE_ERROR;
    response->error_code = BF_ERROR_STALE_EVENT;
    response->error = (char *)malloc(sizeof("dropped input batch"));
    if (response->error == NULL) {
      bf_ocaml_bridge_response_release(response);
      return BF_STATUS_FATAL_ERROR;
    }
    memcpy(response->error, "dropped input batch", sizeof("dropped input batch"));
    return BF_STATUS_RECOVERABLE_ERROR;
  }
  if (input_length == 1 && input != NULL && input[0] == 0) {
    return respond(response, "", 9, 2);
  }
  return respond(response, "frame", 7, 1);
}

bf_status bf_ocaml_bridge_presentation_succeeded(
    uint64_t handle,
    uint64_t presentation_id,
    uint64_t revision,
    int64_t monotonic_now_ns,
    bf_ocaml_response *response) {
  if (handle != 42) {
    return BF_STATUS_FATAL_ERROR;
  }
  presentation_succeeded_count += 1;
  last_presentation_id = presentation_id;
  last_revision = revision;
  last_monotonic_now_ns = monotonic_now_ns;
  return respond(response, "", 0, 0);
}

bf_status bf_ocaml_bridge_presentation_rejected(
    uint64_t handle,
    uint64_t presentation_id,
    uint64_t revision,
    int32_t rejection_reason,
    bf_ocaml_response *response) {
  if (handle != 42) {
    return BF_STATUS_FATAL_ERROR;
  }
  presentation_rejected_count += 1;
  last_presentation_id = presentation_id;
  last_revision = revision;
  last_rejection_reason = rejection_reason;
  return respond(response, "", 0, 0);
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
int bf_mock_pump_count(void) { return pump_count; }
int bf_mock_presentation_succeeded_count(void) {
  return presentation_succeeded_count;
}
int bf_mock_presentation_rejected_count(void) {
  return presentation_rejected_count;
}
int64_t bf_mock_last_monotonic_now_ns(void) { return last_monotonic_now_ns; }
uint64_t bf_mock_last_presentation_id(void) { return last_presentation_id; }
uint64_t bf_mock_last_revision(void) { return last_revision; }
int32_t bf_mock_last_rejection_reason(void) { return last_rejection_reason; }
