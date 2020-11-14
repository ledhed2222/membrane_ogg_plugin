#pragma once

#define MEMBRANE_LOG_TAG "Membrane.Ogg.PayloaderNative"
#include <membrane/log.h>
#include <ogg/ogg.h>

typedef struct _PayloaderState UnifexNifState;
typedef UnifexNifState State;

struct _PayloaderState {
  ogg_stream_state stream;
  ogg_page page;
};

#include "_generated/payloader.h"
