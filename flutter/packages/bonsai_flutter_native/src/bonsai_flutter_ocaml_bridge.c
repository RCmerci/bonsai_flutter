#include "bonsai_flutter_ocaml_bridge.h"

#include <caml/alloc.h>
#include <caml/callback.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/threads.h>

#include <pthread.h>
#include <stdlib.h>
#include <string.h>

static pthread_once_t bf_ocaml_once = PTHREAD_ONCE_INIT;
static int bf_ocaml_initialized = 0;
static char bf_ocaml_initialization_error[256] = {0};

static const value *bf_create_callback = NULL;
static const value *bf_step_callback = NULL;
static const value *bf_frame_presented_callback = NULL;
static const value *bf_destroy_callback = NULL;

static void bf_copy_error(char *destination,
                          size_t capacity,
                          const char *message) {
  size_t length;

  if (destination == NULL || capacity == 0) {
    return;
  }
  if (message == NULL) {
    destination[0] = '\0';
    return;
  }
  length = strlen(message);
  if (length >= capacity) {
    length = capacity - 1;
  }
  memcpy(destination, message, length);
  destination[length] = '\0';
}

static void bf_ocaml_initialize_once(void) {
  char *argv[] = {"bonsai_flutter", NULL};
  value startup_result = caml_startup_exn(argv);

  if (Is_exception_result(startup_result)) {
    bf_copy_error(bf_ocaml_initialization_error,
                  sizeof(bf_ocaml_initialization_error),
                  "OCaml runtime initialization raised an exception");
    return;
  }
  bf_create_callback = caml_named_value("bonsai_flutter.create");
  bf_step_callback = caml_named_value("bonsai_flutter.step");
  bf_frame_presented_callback =
      caml_named_value("bonsai_flutter.frame_presented");
  bf_destroy_callback = caml_named_value("bonsai_flutter.destroy");
  if (bf_create_callback == NULL || bf_step_callback == NULL ||
      bf_frame_presented_callback == NULL || bf_destroy_callback == NULL) {
    bf_copy_error(bf_ocaml_initialization_error,
                  sizeof(bf_ocaml_initialization_error),
                  "OCaml runtime callbacks are not registered");
    return;
  }
  bf_ocaml_initialized = 1;
  caml_release_runtime_system();
}

int bf_ocaml_bridge_initialize(char *error, size_t error_capacity) {
  if (pthread_once(&bf_ocaml_once, bf_ocaml_initialize_once) != 0) {
    bf_copy_error(error, error_capacity, "pthread_once failed");
    return 0;
  }
  if (!bf_ocaml_initialized) {
    bf_copy_error(error, error_capacity, bf_ocaml_initialization_error);
    return 0;
  }
  if (error != NULL && error_capacity != 0) {
    error[0] = '\0';
  }
  return 1;
}

static int bf_enter_ocaml(void) {
  int registered = caml_c_thread_register();
  caml_acquire_runtime_system();
  return registered;
}

static void bf_leave_ocaml(int registered) {
  caml_release_runtime_system();
  if (registered) {
    (void)caml_c_thread_unregister();
  }
}

static int bf_valid_tuple(value tuple, mlsize_t fields) {
  return Is_block(tuple) && Tag_val(tuple) == 0 && Wosize_val(tuple) == fields;
}

static int bf_status_from_value(value status, bf_status *result) {
  int code;

  if (!Is_long(status)) {
    return 0;
  }
  code = Int_val(status);
  if (code < BF_STATUS_OK || code > BF_STATUS_FATAL_ERROR) {
    return 0;
  }
  *result = (bf_status)code;
  return 1;
}

static int bf_error_code_from_value(value code_value,
                                    bf_error_code *result) {
  int code;

  if (!Is_long(code_value)) {
    return 0;
  }
  code = Int_val(code_value);
  if (code < BF_ERROR_NONE ||
      code > BF_ERROR_NATIVE_LIBRARY_LOADING_ERROR) {
    return 0;
  }
  *result = (bf_error_code)code;
  return 1;
}

static int bf_copy_ocaml_bytes(value source,
                               uint8_t **destination,
                               size_t *length) {
  mlsize_t source_length;
  uint8_t *copy;

  if (!Is_block(source) || Tag_val(source) != String_tag) {
    return 0;
  }
  source_length = caml_string_length(source);
  if (source_length == 0) {
    *destination = NULL;
    *length = 0;
    return 1;
  }
  copy = (uint8_t *)malloc(source_length);
  if (copy == NULL) {
    return 0;
  }
  memcpy(copy, String_val(source), source_length);
  *destination = copy;
  *length = source_length;
  return 1;
}

static int bf_copy_ocaml_error(value source, char **destination) {
  mlsize_t source_length;
  char *copy;

  if (!Is_block(source) || Tag_val(source) != String_tag) {
    return 0;
  }
  source_length = caml_string_length(source);
  copy = (char *)malloc(source_length + 1);
  if (copy == NULL) {
    return 0;
  }
  memcpy(copy, String_val(source), source_length);
  copy[source_length] = '\0';
  *destination = copy;
  return 1;
}

static void bf_response_reset(bf_ocaml_response *response) {
  memset(response, 0, sizeof(*response));
  response->status = BF_STATUS_FATAL_ERROR;
  response->error_code = BF_ERROR_OCAML_EXCEPTION;
  response->next_wakeup_ns = -1;
}

static void bf_response_failure(bf_ocaml_response *response,
                                const char *message) {
  size_t length = strlen(message);

  bf_ocaml_bridge_response_release(response);
  bf_response_reset(response);
  response->error = (char *)malloc(length + 1);
  if (response->error != NULL) {
    memcpy(response->error, message, length + 1);
  }
}

static bf_status bf_ocaml_bridge_create_locked(const uint8_t *config,
                                               size_t config_length,
                                               uint64_t *handle,
                                               char *error,
                                               size_t error_capacity) {
  CAMLparam0();
  CAMLlocal2(argument, result);
  bf_status status = BF_STATUS_FATAL_ERROR;
  const char *config_bytes =
      config_length == 0 ? "" : (const char *)config;

  argument = caml_alloc_initialized_string(config_length, config_bytes);
  result = caml_callback_exn(*bf_create_callback, argument);
  if (Is_exception_result(result)) {
    bf_copy_error(error, error_capacity, "OCaml create callback raised");
  } else if (!bf_valid_tuple(result, 3) ||
             !bf_status_from_value(Field(result, 0), &status) ||
             !Is_block(Field(result, 1)) ||
             Tag_val(Field(result, 1)) != Custom_tag ||
             !Is_block(Field(result, 2)) ||
             Tag_val(Field(result, 2)) != String_tag) {
    status = BF_STATUS_FATAL_ERROR;
    bf_copy_error(error, error_capacity, "OCaml create callback returned invalid data");
  } else {
    int64_t signed_handle = Int64_val(Field(result, 1));
    if (signed_handle <= 0) {
      status = BF_STATUS_FATAL_ERROR;
      bf_copy_error(error, error_capacity, "OCaml create returned an invalid handle");
    } else {
      *handle = (uint64_t)signed_handle;
      bf_copy_error(error,
                    error_capacity,
                    String_val(Field(result, 2)));
    }
  }
  CAMLreturnT(bf_status, status);
}

bf_status bf_ocaml_bridge_create(const uint8_t *config,
                                 size_t config_length,
                                 uint64_t *handle,
                                 char *error,
                                 size_t error_capacity) {
  int registered;
  bf_status status;

  if (!bf_ocaml_initialized || handle == NULL) {
    bf_copy_error(error, error_capacity, "OCaml bridge is not initialized");
    return BF_STATUS_FATAL_ERROR;
  }
  registered = bf_enter_ocaml();
  status = bf_ocaml_bridge_create_locked(config,
                                         config_length,
                                         handle,
                                         error,
                                         error_capacity);
  bf_leave_ocaml(registered);
  return status;
}

static bf_status bf_call_output_callback_locked(
    const value *callback,
    uint64_t handle,
    const uint8_t *input,
    size_t input_length,
    uint64_t revision,
    int is_frame_presented,
    bf_ocaml_response *response) {
  CAMLparam0();
  CAMLlocal3(handle_value, argument, result);
  bf_status status = BF_STATUS_FATAL_ERROR;
  const char *input_bytes =
      input_length == 0 ? "" : (const char *)input;

  bf_response_reset(response);
  handle_value = caml_copy_int64((int64_t)handle);
  if (is_frame_presented) {
    argument = caml_copy_int64((int64_t)revision);
    result = caml_callback2_exn(*callback, handle_value, argument);
  } else {
    argument = caml_alloc_initialized_string(input_length, input_bytes);
    result = caml_callback2_exn(*callback, handle_value, argument);
  }
  if (Is_exception_result(result)) {
    bf_response_failure(response, "OCaml runtime callback raised");
  } else if (!bf_valid_tuple(result, 6) ||
             !bf_status_from_value(Field(result, 0), &status) ||
             !bf_error_code_from_value(Field(result, 4),
                                       &response->error_code) ||
             !Is_block(Field(result, 2)) ||
             Tag_val(Field(result, 2)) != Custom_tag ||
             !Is_block(Field(result, 3)) ||
             Tag_val(Field(result, 3)) != Custom_tag) {
    bf_response_failure(response, "OCaml runtime callback returned invalid data");
    status = BF_STATUS_FATAL_ERROR;
  } else {
    response->status = status;
    response->revision = (uint64_t)Int64_val(Field(result, 2));
    response->next_wakeup_ns = Int64_val(Field(result, 3));
    if (!bf_copy_ocaml_bytes(Field(result, 1),
                             &response->data,
                             &response->length) ||
        !bf_copy_ocaml_error(Field(result, 5), &response->error)) {
      bf_response_failure(response, "Failed to copy the OCaml runtime response");
      status = BF_STATUS_FATAL_ERROR;
    }
  }
  CAMLreturnT(bf_status, status);
}

static bf_status bf_call_output_callback(const value *callback,
                                         uint64_t handle,
                                         const uint8_t *input,
                                         size_t input_length,
                                         uint64_t revision,
                                         int is_frame_presented,
                                         bf_ocaml_response *response) {
  int registered;
  bf_status status;

  if (!bf_ocaml_initialized || callback == NULL || response == NULL) {
    return BF_STATUS_FATAL_ERROR;
  }
  registered = bf_enter_ocaml();
  status = bf_call_output_callback_locked(callback,
                                          handle,
                                          input,
                                          input_length,
                                          revision,
                                          is_frame_presented,
                                          response);
  bf_leave_ocaml(registered);
  return status;
}

bf_status bf_ocaml_bridge_step(uint64_t handle,
                               const uint8_t *input,
                               size_t input_length,
                               bf_ocaml_response *response) {
  return bf_call_output_callback(bf_step_callback,
                                 handle,
                                 input,
                                 input_length,
                                 0,
                                 0,
                                 response);
}

bf_status bf_ocaml_bridge_frame_presented(uint64_t handle,
                                          uint64_t revision,
                                          bf_ocaml_response *response) {
  return bf_call_output_callback(bf_frame_presented_callback,
                                 handle,
                                 NULL,
                                 0,
                                 revision,
                                 1,
                                 response);
}

void bf_ocaml_bridge_response_release(bf_ocaml_response *response) {
  if (response == NULL) {
    return;
  }
  free(response->data);
  free(response->error);
  memset(response, 0, sizeof(*response));
}

static void bf_ocaml_bridge_destroy_locked(uint64_t handle) {
  CAMLparam0();
  CAMLlocal2(handle_value, result);

  handle_value = caml_copy_int64((int64_t)handle);
  result = caml_callback_exn(*bf_destroy_callback, handle_value);
  (void)result;
  CAMLreturn0;
}

void bf_ocaml_bridge_destroy(uint64_t handle) {
  int registered;

  if (!bf_ocaml_initialized || bf_destroy_callback == NULL) {
    return;
  }
  registered = bf_enter_ocaml();
  bf_ocaml_bridge_destroy_locked(handle);
  bf_leave_ocaml(registered);
}
