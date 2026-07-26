#include "../src/bonsai_flutter_native.h"

#include <assert.h>
#include <string.h>

int main(void) {
  static const uint8_t config[] = "counter";
  static const uint8_t frame_magic[] = {'B', 'F', 'F', 'R'};
  bf_output_buffer output;
  bf_runtime *runtime =
      bf_runtime_create(config, sizeof(config) - 1);

  assert(runtime != NULL);
  assert(bf_runtime_step(runtime, NULL, 0, &output) == BF_STATUS_OK);
  assert(output.status == BF_STATUS_OK);
  assert(output.revision == 1);
  assert(output.length > sizeof(frame_magic));
  assert(memcmp(output.data, frame_magic, sizeof(frame_magic)) == 0);
  assert(bf_runtime_outstanding_buffers(runtime) == 1);
  bf_buffer_free(runtime, output.data);
  assert(bf_runtime_outstanding_buffers(runtime) == 0);

  assert(bf_runtime_frame_presented(runtime, 1, &output) == BF_STATUS_OK);
  assert(output.status == BF_STATUS_OK);
  assert(output.length == 0);
  assert(output.revision == 1);

  bf_runtime_destroy(runtime);
  return 0;
}
