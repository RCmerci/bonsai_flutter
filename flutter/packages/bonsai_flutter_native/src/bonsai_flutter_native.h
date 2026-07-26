#ifndef BONSAI_FLUTTER_NATIVE_H
#define BONSAI_FLUTTER_NATIVE_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#define BF_EXPORT __declspec(dllexport)
#else
#define BF_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct bf_runtime bf_runtime;

typedef int32_t bf_status;
typedef int32_t bf_error_code;

#define BF_STATUS_OK 0
#define BF_STATUS_RECOVERABLE_ERROR 1
#define BF_STATUS_FATAL_ERROR 2

#define BF_ERROR_NONE 0
#define BF_ERROR_PROTOCOL 1
#define BF_ERROR_REVISION_MISMATCH 2
#define BF_ERROR_DUPLICATE_KEY 3
#define BF_ERROR_UNSUPPORTED_NODE_KIND 4
#define BF_ERROR_INVALID_PROP 5
#define BF_ERROR_HANDLER_MISSING 6
#define BF_ERROR_STALE_EVENT 7
#define BF_ERROR_HOST_EFFECT_FAILURE 8
#define BF_ERROR_OCAML_EXCEPTION 9
#define BF_ERROR_DART_RENDERER_EXCEPTION 10
#define BF_ERROR_LIFECYCLE_EXCEPTION 11
#define BF_ERROR_NATIVE_LIBRARY_LOADING_ERROR 12

typedef struct bf_output_buffer {
  const uint8_t *data;
  size_t length;
  uint64_t revision;
  int64_t next_wakeup_ns;
  bf_status status;
  bf_error_code error_code;
} bf_output_buffer;

BF_EXPORT uint16_t bf_protocol_version_major(void);
BF_EXPORT uint16_t bf_protocol_version_minor(void);

BF_EXPORT bf_runtime *bf_runtime_create(const uint8_t *config,
                                        size_t config_length);

BF_EXPORT bf_status bf_runtime_step(bf_runtime *runtime,
                                    const uint8_t *input,
                                    size_t input_length,
                                    bf_output_buffer *output);

BF_EXPORT bf_status bf_runtime_frame_presented(bf_runtime *runtime,
                                               uint64_t revision,
                                               bf_output_buffer *output);

BF_EXPORT bf_status bf_runtime_get_last_error(bf_runtime *runtime,
                                              bf_output_buffer *output);

BF_EXPORT void bf_buffer_free(bf_runtime *runtime, const uint8_t *data);

BF_EXPORT size_t bf_runtime_outstanding_buffers(const bf_runtime *runtime);

BF_EXPORT void bf_runtime_destroy(bf_runtime *runtime);

#ifdef __cplusplus
}
#endif

#endif
