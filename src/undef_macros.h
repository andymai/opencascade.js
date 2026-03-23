/* Fix OCCT macro conflicts with Emscripten val.h.
   OCCT's IntCurve_IntConicConic.lxx defines:
     #define CONSTRUCTOR IntCurve_IntConicConic::IntCurve_IntConicConic
   which conflicts with emscripten::val's EM_METHOD_CALLER_KIND::CONSTRUCTOR enum.
   We push/pop the macro around the problematic include. */
#pragma push_macro("CONSTRUCTOR")
#undef CONSTRUCTOR
#include <emscripten/val.h>
#pragma pop_macro("CONSTRUCTOR")
#define EMSCRIPTEN_VAL_H
