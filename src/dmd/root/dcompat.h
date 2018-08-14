/* Compiler implementation of the D programming language
 * Copyright (C) 1999-2018 by The D Language Foundation, All Rights Reserved
 * written by Walter Bright
 * http://www.digitalmars.com
 * Distributed under the Boost Software License, Version 1.0.
 * http://www.boost.org/LICENSE_1_0.txt
 * https://github.com/dlang/dmd/blob/master/src/mars.h
 */

#ifndef DMD_ROOT_DCOMPAT_H
#define DMD_ROOT_DCOMPAT_H

#ifdef __DMC__
#pragma once
#endif

/// Represents a D [ ] array
template<typename T>
struct DArray
{
    size_t length;
    T *ptr;
};

#endif /* DMD_ROOT_DCOMPAT_H */
