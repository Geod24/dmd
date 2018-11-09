// DISABLED: win32 win64 osx32
// EXTRA_CPP_SOURCES: cpp_stdlib.cpp
// CXXFLAGS: -std=c++11
import core.stdc.stdio;

// Disabled on windows because it needs bindings
// Disabled on osx32 because size_t is not properly mangled

version (CppRuntime_Clang)
{
    extern(C++, `std`, `__1`)
    {
        struct allocator(T);
        struct vector (T, A = allocator!T);
        struct array (T, size_t N);
    }
}
else
{
    extern(C++, `std`)
    {
        struct allocator(T);
        struct vector (T, A = allocator!T);
        struct array (T, size_t N);
    }
}

extern(C++):

ref T identity (T) (ref T v);
T** identityPP (T) (T** v);
vector!T* getVector (T) (size_t length, const T* ptr);
array!(T, N)* getArray(T, size_t N) (const T* ptr);

extern(C++, `ns`)
{
    struct xvector(T);
    void push_back(T, VectorT)(VectorT* this_, ref T value);
}

void main ()
{
    int i = 42;
    float f = 21.0f;

    int* pi = &i;
    float* pf = &f;

    assert(42 == identity(i));
    assert(21.0f == identity(f));
    assert(&pi == identityPP(&pi));
    assert(&pf == identityPP(&pf));

    auto vi = getVector(1, &i);
    auto vf = getVector(3, [f, f, f].ptr);
    assert(vi !is null);
    assert(vf !is null);

    auto ai = getArray!(int, 4)([2012, 10, 11, 42].ptr);
    auto af = getArray!(float, 4)([42.0f, 21.0f, 14.0f, 1957.0f].ptr);
    assert(ai !is null);
    assert(af !is null);

    xvector!int* xvi;
    push_back(xvi, i);
    push_back(vi, i);

    pragma(msg, push_back!(int, typeof(*xvi)).mangleof);
    pragma(msg, push_back!(int, typeof(*vi)).mangleof);

    printf("Success\n");
}
