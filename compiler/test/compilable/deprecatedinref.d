/*
 TEST_OUTPUT:
 ---
compilable/deprecatedinref.d(12): Deprecation: attribute pair `in ref` is deprecated, use `in` instead
void foo(in ref int);
            ^
compilable/deprecatedinref.d(13): Deprecation: attribute pair `ref in` is deprecated, use `in` instead
void foor(ref in int);
              ^
 ---
*/
void foo(in ref int);
void foor(ref in int);
