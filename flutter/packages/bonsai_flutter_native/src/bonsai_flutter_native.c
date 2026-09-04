#include "bonsai_flutter_native.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(BF_WITH_OCAML)
#include "bonsai_flutter_ocaml_bridge.h"
#endif

#define BF_PROTOCOL_MAJOR 2
#define BF_PROTOCOL_MINOR 26
#define BF_ABI_MAJOR 2
#define BF_ABI_MINOR 0

typedef struct bf_allocation {
  uint8_t *data;
  struct bf_allocation *next;
} bf_allocation;

struct bf_runtime {
  bf_allocation *allocations;
  size_t allocation_count;
  char last_error[256];
  char *last_error_detail;
  bf_error_code last_error_code;
#if defined(BF_WITH_OCAML)
  uint64_t backend_handle;
#endif
};

static void bf_store_error(bf_runtime *runtime,
                           bf_error_code error_code,
                           const char *message) {
  size_t length;
  int preserve_detail = 0;

  if (runtime == NULL) {
    return;
  }
  free(runtime->last_error_detail);
  runtime->last_error_detail = NULL;
  preserve_detail = error_code == BF_ERROR_DUPLICATE_KEY;
  if (message == NULL) {
    message = "bonsai_flutter runtime error";
  }
  if (preserve_detail) {
    length = strlen(message);
    runtime->last_error_detail = (char *)malloc(length + 1);
    if (runtime->last_error_detail != NULL) {
      memcpy(runtime->last_error_detail, message, length + 1);
    }
  }
#if defined(NDEBUG)
  if (runtime->last_error_detail == NULL) {
    (void)snprintf(runtime->last_error,
                   sizeof(runtime->last_error),
                   "bonsai_flutter runtime error %d",
                   (int)error_code);
  }
#else
  if (runtime->last_error_detail == NULL) {
    length = strlen(message);
    if (length >= sizeof(runtime->last_error)) {
      length = sizeof(runtime->last_error) - 1;
    }
    memcpy(runtime->last_error, message, length);
    runtime->last_error[length] = '\0';
  }
#endif
  runtime->last_error_code = error_code;
}

static void bf_output_reset(bf_output_buffer *output,
                            bf_status status,
                            bf_error_code error_code) {
  if (output == NULL) {
    return;
  }
  output->data = NULL;
  output->length = 0;
  output->presentation_id = 0;
  output->revision = 0;
  output->status = status;
  output->error_code = error_code;
}

static bf_status bf_set_error(bf_runtime *runtime,
                              bf_output_buffer *output,
                              bf_status status,
  bf_error_code error_code,
  const char *message) {
  bf_store_error(runtime, error_code, message);
  bf_output_reset(output, status, error_code);
  return status;
}

static uint8_t *bf_allocate_output(bf_runtime *runtime, size_t length) {
  bf_allocation *allocation;
  uint8_t *data;

  if (runtime == NULL || length == 0) {
    return NULL;
  }
  data = (uint8_t *)malloc(length);
  if (data == NULL) {
    return NULL;
  }
  allocation = (bf_allocation *)malloc(sizeof(bf_allocation));
  if (allocation == NULL) {
    free(data);
    return NULL;
  }
  allocation->data = data;
  allocation->next = runtime->allocations;
  runtime->allocations = allocation;
  runtime->allocation_count += 1;
  return data;
}

#if defined(BF_WITH_OCAML)
static bf_status bf_apply_ocaml_response(bf_runtime *runtime,
                                         bf_output_buffer *output,
                                         bf_status returned_status,
                                         bf_ocaml_response *response,
                                         int requires_presentation_id) {
  uint8_t *data = NULL;

  if (returned_status != response->status) {
    bf_ocaml_bridge_response_release(response);
    return bf_set_error(runtime,
                        output,
                        BF_STATUS_FATAL_ERROR,
                        BF_ERROR_OCAML_EXCEPTION,
                        "OCaml bridge returned inconsistent status values");
  }
  if (response->error != NULL && response->error[0] != '\0') {
    bf_store_error(runtime, response->error_code, response->error);
  }
  if (returned_status == BF_STATUS_FATAL_ERROR) {
    if (response->error == NULL || response->error[0] == '\0') {
      bf_store_error(runtime,
                     response->error_code,
                     "OCaml runtime call failed without a diagnostic");
    }
    bf_output_reset(output, returned_status, response->error_code);
    bf_ocaml_bridge_response_release(response);
    return returned_status;
  }
  if (requires_presentation_id && response->presentation_id == 0) {
    bf_ocaml_bridge_response_release(response);
    return bf_set_error(runtime,
                        output,
                        BF_STATUS_FATAL_ERROR,
                        BF_ERROR_OCAML_EXCEPTION,
                        "OCaml pump returned no presentation token");
  }
  if (response->length != 0 && response->data == NULL) {
    bf_ocaml_bridge_response_release(response);
    return bf_set_error(runtime,
                        output,
                        BF_STATUS_FATAL_ERROR,
                        BF_ERROR_OCAML_EXCEPTION,
                        "OCaml bridge returned a null nonempty buffer");
  }
  if (response->length != 0) {
    data = bf_allocate_output(runtime, response->length);
    if (data == NULL) {
      bf_ocaml_bridge_response_release(response);
      return bf_set_error(runtime,
                          output,
                          BF_STATUS_FATAL_ERROR,
                          BF_ERROR_NATIVE_LIBRARY_LOADING_ERROR,
                          "Failed to allocate the runtime output buffer");
    }
    memcpy(data, response->data, response->length);
  }
  bf_output_reset(output, BF_STATUS_OK, BF_ERROR_NONE);
  output->data = data;
  output->length = response->length;
  output->presentation_id = response->presentation_id;
  output->revision = response->revision;
  output->status = returned_status;
  output->error_code = response->error_code;
  bf_ocaml_bridge_response_release(response);
  return returned_status;
}
#endif

uint16_t bf_abi_version_major(void) { return BF_ABI_MAJOR; }

uint16_t bf_abi_version_minor(void) { return BF_ABI_MINOR; }

uint16_t bf_protocol_version_major(void) { return BF_PROTOCOL_MAJOR; }

uint16_t bf_protocol_version_minor(void) { return BF_PROTOCOL_MINOR; }

bf_runtime *bf_runtime_create(const uint8_t *config, size_t config_length) {
  bf_runtime *runtime;

  if (config == NULL && config_length != 0) {
    return NULL;
  }
  runtime = (bf_runtime *)calloc(1, sizeof(bf_runtime));
  if (runtime == NULL) {
    return NULL;
  }
#if defined(BF_WITH_OCAML)
  {
    uint64_t handle = 0;
    char error[256] = {0};
    bf_status status;

    if (!bf_ocaml_bridge_initialize(error, sizeof(error))) {
      free(runtime);
      return NULL;
    }
    status = bf_ocaml_bridge_create(config,
                                    config_length,
                                    &handle,
                                    error,
                                    sizeof(error));
    if (status != BF_STATUS_OK || handle == 0) {
      free(runtime);
      return NULL;
    }
    runtime->backend_handle = handle;
  }
#else
  (void)config;
#endif
  memcpy(runtime->last_error, "No error", sizeof("No error"));
  runtime->last_error_code = BF_ERROR_NONE;
  return runtime;
}

bf_status bf_runtime_pump(bf_runtime *runtime,
                          int64_t monotonic_now_ns,
                          const uint8_t *input,
                          size_t input_length,
                          bf_output_buffer *output) {
  if (runtime == NULL || output == NULL) {
    return BF_STATUS_FATAL_ERROR;
  }
  if (input == NULL && input_length != 0) {
    return bf_set_error(runtime,
                        output,
                        BF_STATUS_RECOVERABLE_ERROR,
                        BF_ERROR_PROTOCOL,
                        "Input pointer is null for a nonempty batch");
  }
  if (monotonic_now_ns < 0) {
    return bf_set_error(runtime,
                        output,
                        BF_STATUS_RECOVERABLE_ERROR,
                        BF_ERROR_INVALID_MONOTONIC_TIME,
                        "Monotonic time must be nonnegative");
  }
#if defined(BF_WITH_OCAML)
  {
    bf_ocaml_response response = {0};
    bf_status status =
        bf_ocaml_bridge_pump(runtime->backend_handle,
                             monotonic_now_ns,
                             input,
                             input_length,
                             &response);
    return bf_apply_ocaml_response(runtime, output, status, &response, 1);
  }
#else
  (void)input;
  return bf_set_error(runtime,
                      output,
                      BF_STATUS_FATAL_ERROR,
                      BF_ERROR_NATIVE_LIBRARY_LOADING_ERROR,
                      "OCaml runtime backend is not linked");
#endif
}

bf_status bf_runtime_presentation_succeeded(bf_runtime *runtime,
                                            uint64_t presentation_id,
                                            uint64_t revision,
                                            int64_t monotonic_now_ns,
                                            bf_output_buffer *output) {
  if (runtime == NULL || output == NULL) {
    return BF_STATUS_FATAL_ERROR;
  }
  if (presentation_id == 0) {
    return bf_set_error(runtime,
                        output,
                        BF_STATUS_RECOVERABLE_ERROR,
                        BF_ERROR_INVALID_PRESENTATION,
                        "Presentation ID must be positive");
  }
  if (monotonic_now_ns < 0) {
    return bf_set_error(runtime,
                        output,
                        BF_STATUS_RECOVERABLE_ERROR,
                        BF_ERROR_INVALID_MONOTONIC_TIME,
                        "Monotonic time must be nonnegative");
  }
#if defined(BF_WITH_OCAML)
  {
    bf_ocaml_response response = {0};
    bf_status status =
        bf_ocaml_bridge_presentation_succeeded(runtime->backend_handle,
                                               presentation_id,
                                               revision,
                                               monotonic_now_ns,
                                               &response);
    return bf_apply_ocaml_response(runtime, output, status, &response, 0);
  }
#else
  (void)presentation_id;
  (void)revision;
  (void)monotonic_now_ns;
  return bf_set_error(runtime,
                      output,
                      BF_STATUS_FATAL_ERROR,
                      BF_ERROR_NATIVE_LIBRARY_LOADING_ERROR,
                      "OCaml runtime backend is not linked");
#endif
}

bf_status bf_runtime_presentation_rejected(bf_runtime *runtime,
                                           uint64_t presentation_id,
                                           uint64_t revision,
                                           int32_t rejection_reason,
                                           bf_output_buffer *output) {
  if (runtime == NULL || output == NULL) {
    return BF_STATUS_FATAL_ERROR;
  }
  if (presentation_id == 0 || rejection_reason < BF_REJECTION_DECODE_FAILED ||
      rejection_reason > BF_REJECTION_RENDERER_REVISION_MISMATCH) {
    return bf_set_error(runtime,
                        output,
                        BF_STATUS_RECOVERABLE_ERROR,
                        BF_ERROR_INVALID_PRESENTATION,
                        "Invalid presentation rejection");
  }
#if defined(BF_WITH_OCAML)
  {
    bf_ocaml_response response = {0};
    bf_status status = bf_ocaml_bridge_presentation_rejected(
        runtime->backend_handle,
        presentation_id,
        revision,
        rejection_reason,
        &response);
    return bf_apply_ocaml_response(runtime, output, status, &response, 0);
  }
#else
  (void)presentation_id;
  (void)revision;
  (void)rejection_reason;
  return bf_set_error(runtime,
                      output,
                      BF_STATUS_FATAL_ERROR,
                      BF_ERROR_NATIVE_LIBRARY_LOADING_ERROR,
                      "OCaml runtime backend is not linked");
#endif
}

bf_status bf_runtime_get_last_error(bf_runtime *runtime,
                                    bf_output_buffer *output) {
  size_t length;
  uint8_t *data;
  const char *message;

  if (runtime == NULL || output == NULL) {
    return BF_STATUS_FATAL_ERROR;
  }
  message = runtime->last_error_detail == NULL ? runtime->last_error
                                               : runtime->last_error_detail;
  length = strlen(message);
  data = bf_allocate_output(runtime, length);
  if (length != 0 && data == NULL) {
    return bf_set_error(runtime,
                        output,
                        BF_STATUS_FATAL_ERROR,
                        BF_ERROR_NATIVE_LIBRARY_LOADING_ERROR,
                        "Failed to allocate the error buffer");
  }
  if (length != 0) {
    memcpy(data, message, length);
  }
  bf_output_reset(output, BF_STATUS_OK, runtime->last_error_code);
  output->data = data;
  output->length = length;
  return BF_STATUS_OK;
}

void bf_buffer_free(bf_runtime *runtime, const uint8_t *data) {
  bf_allocation **cursor;

  if (runtime == NULL || data == NULL) {
    return;
  }
  cursor = &runtime->allocations;
  while (*cursor != NULL) {
    bf_allocation *allocation = *cursor;
    if (allocation->data == data) {
      *cursor = allocation->next;
      free(allocation->data);
      free(allocation);
      runtime->allocation_count -= 1;
      return;
    }
    cursor = &allocation->next;
  }
}

size_t bf_runtime_outstanding_buffers(const bf_runtime *runtime) {
  return runtime == NULL ? 0 : runtime->allocation_count;
}

void bf_runtime_destroy(bf_runtime *runtime) {
  bf_allocation *allocation;

  if (runtime == NULL) {
    return;
  }
#if defined(BF_WITH_OCAML)
  bf_ocaml_bridge_destroy(runtime->backend_handle);
#endif
  allocation = runtime->allocations;
  while (allocation != NULL) {
    bf_allocation *next = allocation->next;
    free(allocation->data);
    free(allocation);
    allocation = next;
  }
  free(runtime->last_error_detail);
  memset(runtime, 0, sizeof(bf_runtime));
  free(runtime);
}
