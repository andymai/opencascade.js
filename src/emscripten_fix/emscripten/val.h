// Wrapper to fix OCCT CONSTRUCTOR macro clash with emscripten val.h
#pragma push_macro("CONSTRUCTOR")
#undef CONSTRUCTOR
#include_next <emscripten/val.h>
#pragma pop_macro("CONSTRUCTOR")
