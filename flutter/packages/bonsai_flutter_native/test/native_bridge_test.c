#include "../src/bonsai_flutter_native.h"

#include <assert.h>
#include <string.h>

int bf_mock_destroy_count(void);

int main(void) {
  const uint8_t config[] = "counter";
  bf_output_buffer output;
  bf_runtime *runtime =
      bf_runtime_create(config, sizeof(config) - 1);

  assert(runtime != NULL);
  assert(bf_protocol_version_major() == 1);
  assert(bf_protocol_version_minor() == 12);
  assert(bf_runtime_step(runtime, NULL, 0, &output) == BF_STATUS_OK);
  assert(output.status == BF_STATUS_OK);
  assert(output.error_code == BF_ERROR_NONE);
  assert(output.revision == 1);
  assert(output.length == 5);
  assert(memcmp(output.data, "frame", 5) == 0);
  assert(bf_runtime_outstanding_buffers(runtime) == 1);
  bf_buffer_free(runtime, output.data);
  assert(bf_runtime_outstanding_buffers(runtime) == 0);
  assert(bf_runtime_frame_presented(runtime, 1, &output) == BF_STATUS_OK);
  assert(output.status == BF_STATUS_OK);
  assert(output.length == 0);
  bf_runtime_destroy(runtime);
  assert(bf_mock_destroy_count() == 1);
  return 0;
}
