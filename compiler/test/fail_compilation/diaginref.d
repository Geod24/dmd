/*
REQUIRED_ARGS: -de
TEST_OUTPUT:
---
fail_compilation/diaginref.d(11): Deprecation: attribute pair `in ref` is deprecated, use `in` instead
fail_compilation/diaginref.d(13): Deprecation: attribute pair `ref in` is deprecated, use `in` instead
---
 */

void foo(in string) {}
void foo1(in ref string) {}
void foo2(T)(in T v, string) {}
void foo3(T)(ref in T v, string) {}
