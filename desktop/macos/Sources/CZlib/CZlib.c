// Newer SwiftPM build systems expect every target to produce an object file.
// This target only re-exports zlib through its module map, so it provides an
// empty translation unit.
#include "CZlib.h"

typedef int agentstick_czlib_placeholder_t;
