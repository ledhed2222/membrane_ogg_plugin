#include "payloader.h"
#include <unistd.h>

UNIFEX_TERM create(UnifexEnv *env, unsigned int serial) {
  State *state = unifex_alloc_state(env);
  if (ogg_stream_init(&state->stream, serial) == -1) {
    unifex_release_state(env, state);
    return unifex_raise(env, "Error initializing Ogg stream");
  }

  UNIFEX_TERM res = create_result_ok(env, state);
  unifex_release_state(env, state);
  return res;
}

UNIFEX_TERM make_pages(UnifexEnv *env, UnifexPayload *in_payload, UnifexNifState *state, unsigned int position, unsigned int packet_number, int header_type) {
  ogg_packet packet = {
    in_payload->data,
    in_payload->size,
    header_type == 1 ? 1 : 0,
    header_type == 2 ? 1 : 0,
    position,
    packet_number
  };
  if (ogg_stream_packetin(&state->stream, &packet) == -1) {
    return make_pages_result_error(env, "Error writing packet");
  }

  unsigned char *data = NULL;
  int total_size = 0;
  while (ogg_stream_pageout(&state->stream, &state->page)) {
    int addl_size = state->page.header_len + state->page.body_len;
    data = realloc(data, total_size + addl_size);
    unsigned char *pointer = data + total_size;

    memcpy(pointer, state->page.header, state->page.header_len);
    pointer += state->page.header_len;
    memcpy(pointer, state->page.body, state->page.body_len);

    total_size += addl_size;
  }

  UnifexPayload *out_payload = unifex_payload_alloc(env, UNIFEX_PAYLOAD_BINARY, total_size);
  if (total_size > 0) {
    memcpy(out_payload->data, data, total_size);
    free(data);
  }
  UNIFEX_TERM res = make_pages_result_ok(env, out_payload);
  unifex_payload_release(out_payload);
  return res;
}

UNIFEX_TERM flush(UnifexEnv *env, UnifexNifState *state) {
  int flush_result = ogg_stream_flush(&state->stream, &state->page);
  int total_size = flush_result == 0 ? 0 : state->page.header_len + state->page.body_len;
  UnifexPayload *out_payload = unifex_payload_alloc(env, UNIFEX_PAYLOAD_BINARY, total_size);

  if (flush_result != 0) {
    unsigned char *pointer = out_payload->data;
    memcpy(pointer, state->page.header, state->page.header_len);
    pointer += state->page.header_len;
    memcpy(pointer, state->page.body, state->page.body_len);
  }
  UNIFEX_TERM res = flush_result_ok(env, out_payload);
  unifex_payload_release(out_payload);
  return res;
}

void handle_destroy_state(UnifexEnv *env, UnifexNifState *state) {
  UNIFEX_UNUSED(env);
  ogg_stream_clear(&state->stream);
}
