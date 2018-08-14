/**
 * Compiler implementation of the D programming language
 * http://dlang.org
 *
 * Copyright: Copyright (C) 1999-2018 by The D Language Foundation, All Rights Reserved
 * Authors:   Walter Bright, http://www.digitalmars.com
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Source:    $(LINK2 https://github.com/dlang/dmd/blob/master/src/dmd/root/filename.d, root/_filename.d)
 * Documentation:  https://dlang.org/phobos/dmd_root_filename.html
 * Coverage:    https://codecov.io/gh/dlang/dmd/src/master/src/dmd/root/filename.d
 */

module dmd.root.filename;

import core.stdc.ctype;
import core.stdc.errno;
import core.stdc.string;
import core.sys.posix.stdlib;
import core.sys.posix.sys.stat;
import core.sys.windows.windows;
import dmd.root.array;
import dmd.root.file;
import dmd.root.outbuffer;
import dmd.root.rmem;
import dmd.root.rootobject;
import dmd.utils;

nothrow
{
version (Windows) extern (C) int stricmp(const char*, const char*) pure;
version (Windows) extern (Windows) DWORD GetFullPathNameW(LPCWSTR, DWORD, LPWSTR, LPWSTR*) @nogc;
version (Windows) extern (Windows) void SetLastError(DWORD) @nogc;
version (Windows) extern (C) char* getcwd(char* buffer, size_t maxlen);
version (Posix) extern (C) char* canonicalize_file_name(const char*);
version (Posix) import core.sys.posix.unistd : getcwd;
}
alias Strings = Array!(const(char)*);
alias Files = Array!(File*);

/***********************************************************
 * Encapsulate path and file names.
 */
struct FileName
{
nothrow:
    const(char)* str;

    extern (D) this(const(char)* str)
    {
        this.str = mem.xstrdup(str);
    }

    extern (C++) bool equals(const RootObject obj) const pure
    {
        return compare(obj) == 0;
    }

    extern (C++) static bool equals(const(char)* name1, const(char)* name2) pure
    {
        return compare(name1, name2) == 0;
    }

    extern (C++) int compare(const RootObject obj) const pure
    {
        return compare(str, (cast(FileName*)obj).str);
    }

    extern (C++) static int compare(const(char)* name1, const(char)* name2) pure
    {
        version (Windows)
        {
            return stricmp(name1, name2);
        }
        else
        {
            return strcmp(name1, name2);
        }
    }

    /************************************
     * Determine if path is absolute.
     * Params:
     *  name = path
     * Returns:
     *  true if absolute path name.
     */
    extern (C++) static bool absolute(const(char)* name) pure
    {
        return absolute(name[0 .. strlen(name)]);
    }

    /// Ditto
    extern (D) static bool absolute(const(char)[] name) pure
    {
        if (!name.length)
            return false;

        version (Windows)
        {
            return (name[0] == '\\') || (name[0] == '/')
                || (name.length >= 2 && name[1] == ':');
        }
        else version (Posix)
        {
            return (name[0] == '/');
        }
        else
        {
            assert(0);
        }
    }

    /**
    Return the given name as an absolute path

    Params:
        name = path
        base = the absolute base to prefix name with if it is relative

    Returns: name as an absolute path relative to base
    */
    extern (C++) static const(char)* toAbsolute(const(char)* name, const(char)* base = null)
    {
        return absolute(name) ? name : combine(base ? base : getcwd(null, 0), name);
    }

    /********************************
     * Determine file name extension as slice of input.
     * Params:
     *  str = file name
     * Returns:
     *  filename extension (read-only).
     *  Points past '.' of extension.
     *  If there isn't one, return null.
     */
    extern (C++) static const(char)* ext(const(char)* str) pure
    {
        return ext(str[0 .. strlen(str)]).ptr;
    }

    /// Ditto
    extern (D) static const(char)[] ext(const(char)[] str) pure
    {
        foreach_reverse (idx, char e; str)
        {
            switch (e)
            {
            case '.':
                return str[idx + 1 .. $];
                version (Posix)
                {
                case '/':
                    break;
                }
                version (Windows)
                {
                case '\\':
                case ':':
                case '/':
                    break;
                }
            default:
                break;
            }
        }
        return null;
    }

    extern (C++) const(char)* ext() const pure
    {
        return ext(str);
    }

    /********************************
     * Return file name without extension.
     * Params:
     *  str = file name
     * Returns:
     *  mem.xmalloc'd filename with extension removed.
     */
    extern (C++) static const(char)* removeExt(const(char)* str)
    {
        const(char)* e = ext(str);
        if (e)
        {
            size_t len = (e - str) - 1;
            char* n = cast(char*)mem.xmalloc(len + 1);
            memcpy(n, str, len);
            n[len] = 0;
            return n;
        }
        return mem.xstrdup(str);
    }

    /********************************
     * Return filename name excluding path (read-only).
     */
    extern (C++) static const(char)* name(const(char)* str) pure
    {
        return name(str[0 .. strlen(str)]).ptr;
    }

    /// Ditto
    extern (D) static const(char)[] name(const(char)[] str) pure
    {
        foreach_reverse (idx, char e; str)
        {
            switch (e)
            {
                version (Posix)
                {
                case '/':
                    return str[idx + 1 .. $];
                }
                version (Windows)
                {
                case '/':
                case '\\':
                    return str[idx + 1 .. $];
                case ':':
                    /* The ':' is a drive letter only if it is the second
                     * character or the last character,
                     * otherwise it is an ADS (Alternate Data Stream) separator.
                     * Consider ADS separators as part of the file name.
                     */
                    if (idx == 1 || idx == str.length - 1)
                        return str[idx + 1 .. $];
                    break;
                }
            default:
                break;
            }
        }
        return str;
    }

    extern (C++) const(char)* name() const pure
    {
        return name(str);
    }

    /**************************************
     * Return path portion of str.
     * Path will does not include trailing path separator.
     */
    extern (C++) static const(char)* path(const(char)* str)
    {
        const(char)* n = name(str);
        size_t pathlen;
        if (n > str)
        {
            version (Posix)
            {
                if (n[-1] == '/')
                    n--;
            }
            else version (Windows)
            {
                if (n[-1] == '\\' || n[-1] == '/')
                    n--;
            }
            else
            {
                assert(0);
            }
        }
        pathlen = n - str;
        char* path = cast(char*)mem.xmalloc(pathlen + 1);
        memcpy(path, str, pathlen);
        path[pathlen] = 0;
        return path;
    }

    /**************************************
     * Replace filename portion of path.
     */
    extern (C++) static const(char)* replaceName(const(char)* path, const(char)* name)
    {
        return replaceName(path[0 .. strlen(path)], name[0 .. strlen(name)]).ptr;
    }

    /// Ditto
    extern (D) static const(char)[] replaceName(const(char)[] path, const(char)[] name)
    {
        if (absolute(name))
            return name;
        auto n = FileName.name(path);
        if (n == path)
            return name;
        return combine(path[0 .. $ - n.length], name);
    }

    /**
       Combine a `path` and a file `name`

       Returns:
         The `\0` terminated string which is the combination of `path` and `name`
         and a valid path.
    */
    extern (C++) static const(char)* combine(const(char)* path, const(char)* name)
    {
        if (!path)
            return name;
        return combine(path[0 .. strlen(path)], name[0 .. strlen(name)]).ptr;
    }

    extern(D) static const(char)[] combine(const(char)[] path, const(char)[] name)
    {
        if (!path.length)
            return name;

        char* f = cast(char*)mem.xmalloc(path.length + 1 + name.length + 1);
        memcpy(f, path.ptr, path.length);
        bool trailingSlash = false;
        version (Posix)
        {
            if (path[$ - 1] != '/')
            {
                f[path.length] = '/';
                trailingSlash = true;
            }
        }
        else version (Windows)
        {
            if (path[$ - 1] != '\\' && path[$ - 1] != '/' && path[$ - 1] != ':')
            {
                f[path.length] = '\\';
                trailingSlash = true;
            }
        }
        else
        {
            assert(0);
        }
        const len = path.length + (trailingSlash ? 1 : 0);
        memcpy(f + len, name.ptr, name.length);
        // Note: At the moment `const(char)*` are being transitioned to
        // `const(char)[]`. To avoid bugs crippling in, we `\0` terminate
        // slices, but don't include it in the slice so `.ptr` can be used.
        f[len + name.length] = '\0';
        return f[0 .. len + name.length];
    }

    static const(char)* buildPath(const(char)* path, const(char)*[] names...)
    {
        foreach (const(char)* name; names)
            path = combine(path, name);
        return path;
    }

    // Split a path into an Array of paths
    extern (C++) static Strings* splitPath(const(char)* path)
    {
        char c = 0; // unnecessary initializer is for VC /W4
        const(char)* p;
        OutBuffer buf;
        Strings* array;
        array = new Strings();
        if (path)
        {
            p = path;
            do
            {
                char instring = 0;
                while (isspace(cast(char)*p)) // skip leading whitespace
                    p++;
                buf.reserve(strlen(p) + 1); // guess size of path
                for (;; p++)
                {
                    c = *p;
                    switch (c)
                    {
                    case '"':
                        instring ^= 1; // toggle inside/outside of string
                        continue;
                        version (OSX)
                        {
                        case ',':
                        }
                        version (Windows)
                        {
                        case ';':
                        }
                        version (Posix)
                        {
                        case ':':
                        }
                        p++;
                        break;
                        // note that ; cannot appear as part
                        // of a path, quotes won't protect it
                    case 0x1A:
                        // ^Z means end of file
                    case 0:
                        break;
                    case '\r':
                        continue;
                        // ignore carriage returns
                        version (Posix)
                        {
                        case '~':
                            {
                                char* home = getenv("HOME");
                                if (home)
                                    buf.writestring(home);
                                else
                                    buf.writestring("~");
                                continue;
                            }
                        }
                        version (none)
                        {
                        case ' ':
                        case '\t':
                            // tabs in filenames?
                            if (!instring) // if not in string
                                break;
                            // treat as end of path
                        }
                    default:
                        buf.writeByte(c);
                        continue;
                    }
                    break;
                }
                if (buf.offset) // if path is not empty
                {
                    array.push(buf.extractString());
                }
            }
            while (c);
        }
        return array;
    }

    /***************************
     * Free returned value with FileName::free()
     */
    extern (C++) static const(char)* defaultExt(const(char)* name, const(char)* ext)
    {
        return defaultExt(name[0 .. strlen(name)], ext[0 .. strlen(ext)]).ptr;
    }

    /// Ditto
    extern (D) static const(char)[] defaultExt(const(char)[] name, const(char)[] ext)
    {
        auto e = FileName.ext(name);
        if (e.length) // it already has an extension
            return mem.xstrdup(name.ptr)[0 .. name.length];
        const s_length = name.length + 1 + ext.length + 1;
        auto s = cast(char*)mem.xmalloc(s_length);
        memcpy(s, name.ptr, name.length);
        s[name.length] = '.';
        memcpy(s + name.length + 1, ext.ptr, ext.length);
        s[s_length - 1] = '\0';
        return s[0 .. s_length];
    }

    /***************************
     * Free returned value with FileName::free()
     */
    extern (C++) static const(char)* forceExt(const(char)* name, const(char)* ext)
    {
        const(char)* e = FileName.ext(name);
        if (e) // if already has an extension
        {
            size_t len = e - name;
            size_t extlen = strlen(ext);
            char* s = cast(char*)mem.xmalloc(len + extlen + 1);
            memcpy(s, name, len);
            memcpy(s + len, ext, extlen + 1);
            return s;
        }
        else
            return defaultExt(name, ext); // doesn't have one
    }

    extern (C++) static bool equalsExt(const(char)* name, const(char)* ext) pure
    {
        const(char)* e = FileName.ext(name);
        if (!e && !ext)
            return true;
        if (!e || !ext)
            return false;
        return FileName.compare(e, ext) == 0;
    }

    /******************************
     * Return !=0 if extensions match.
     */
    extern (C++) bool equalsExt(const(char)* ext) const pure
    {
        return equalsExt(str, ext);
    }

    /*************************************
     * Search Path for file.
     * Input:
     *      cwd     if true, search current directory before searching path
     */
    extern (C++) static const(char)* searchPath(Strings* path, const(char)* name, bool cwd)
    {
        if (absolute(name))
        {
            return exists(name) ? name : null;
        }
        if (cwd)
        {
            if (exists(name))
                return name;
        }
        if (path)
        {
            foreach (p; *path)
            {
                auto n = combine(p, name);
                if (exists(n))
                    return n;
            }
        }
        return null;
    }

    /*************************************
     * Search Path for file in a safe manner.
     *
     * Be wary of CWE-22: Improper Limitation of a Pathname to a Restricted Directory
     * ('Path Traversal') attacks.
     *      http://cwe.mitre.org/data/definitions/22.html
     * More info:
     *      https://www.securecoding.cert.org/confluence/display/c/FIO02-C.+Canonicalize+path+names+originating+from+tainted+sources
     * Returns:
     *      NULL    file not found
     *      !=NULL  mem.xmalloc'd file name
     */
    extern (C++) static const(char)* safeSearchPath(Strings* path, const(char)* name)
    {
        version (Windows)
        {
            // don't allow leading / because it might be an absolute
            // path or UNC path or something we'd prefer to just not deal with
            if (*name == '/')
            {
                return null;
            }
            /* Disallow % \ : and .. in name characters
             * We allow / for compatibility with subdirectories which is allowed
             * on dmd/posix. With the leading / blocked above and the rest of these
             * conservative restrictions, we should be OK.
             */
            for (const(char)* p = name; *p; p++)
            {
                char c = *p;
                if (c == '\\' || c == ':' || c == '%' || (c == '.' && p[1] == '.') || (c == '/' && p[1] == '/'))
                {
                    return null;
                }
            }
            return FileName.searchPath(path, name, false);
        }
        else version (Posix)
        {
            /* Even with realpath(), we must check for // and disallow it
             */
            for (const(char)* p = name; *p; p++)
            {
                char c = *p;
                if (c == '/' && p[1] == '/')
                {
                    return null;
                }
            }
            if (path)
            {
                /* Each path is converted to a cannonical name and then a check is done to see
                 * that the searched name is really a child one of the the paths searched.
                 */
                for (size_t i = 0; i < path.dim; i++)
                {
                    const(char)* cname = null;
                    const(char)* cpath = canonicalName((*path)[i]);
                    //printf("FileName::safeSearchPath(): name=%s; path=%s; cpath=%s\n",
                    //      name, (char *)path.data[i], cpath);
                    if (cpath is null)
                        goto cont;
                    cname = canonicalName(combine(cpath, name));
                    //printf("FileName::safeSearchPath(): cname=%s\n", cname);
                    if (cname is null)
                        goto cont;
                    //printf("FileName::safeSearchPath(): exists=%i "
                    //      "strncmp(cpath, cname, %i)=%i\n", exists(cname),
                    //      strlen(cpath), strncmp(cpath, cname, strlen(cpath)));
                    // exists and name is *really* a "child" of path
                    if (exists(cname) && strncmp(cpath, cname, strlen(cpath)) == 0)
                    {
                        .free(cast(void*)cpath);
                        const(char)* p = mem.xstrdup(cname);
                        .free(cast(void*)cname);
                        return p;
                    }
                cont:
                    if (cpath)
                        .free(cast(void*)cpath);
                    if (cname)
                        .free(cast(void*)cname);
                }
            }
            return null;
        }
        else
        {
            assert(0);
        }
    }

    /**
       Check if the file the `path` points to exists

       Returns:
         0 if it does not exists
         1 if it exists and is not a directory
         2 if it exists and is a directory
     */
    extern (C++) static int exists(const(char)* name)
    {
        return exists(name.toDString);
    }

    /// Ditto
    extern (D) static int exists(const(char)[] name)
    {
        version (Posix)
        {
            stat_t st;
            if (name.toCStringThen!((v) => stat(v.ptr, &st)) < 0)
                return 0;
            if (S_ISDIR(st.st_mode))
                return 2;
            return 1;
        }
        else version (Windows)
        {
            return name.toWStringzThen!((wname)
            {
                const dw = GetFileAttributesW(&wname[0]);
                if (dw == -1)
                    return 0;
                else if (dw & FILE_ATTRIBUTE_DIRECTORY)
                    return 2;
                else
                    return 1;
            });
        }
        else
        {
            assert(0);
        }
    }

    extern (C++) static bool ensurePathExists(const(char)* path)
    {
        //printf("FileName::ensurePathExists(%s)\n", path ? path : "");
        if (path && *path)
        {
            if (!exists(path))
            {
                const(char)* p = FileName.path(path);
                if (*p)
                {
                    version (Windows)
                    {
                        size_t len = strlen(path);
                        if ((len > 2 && p[-1] == ':' && strcmp(path + 2, p) == 0) || len == strlen(p))
                        {
                            mem.xfree(cast(void*)p);
                            return 0;
                        }
                    }
                    bool r = ensurePathExists(p);
                    mem.xfree(cast(void*)p);

                    if (r)
                        return r;
                }
                version (Windows)
                {
                    char sep = '\\';
                }
                else version (Posix)
                {
                    char sep = '/';
                }
                if (path[strlen(path) - 1] != sep)
                {
                    version (Windows)
                    {
                        int r = _mkdir(path.toDString);
                    }
                    version (Posix)
                    {
                        int r = mkdir(path, (7 << 6) | (7 << 3) | 7);
                    }
                    if (r)
                    {
                        /* Don't error out if another instance of dmd just created
                         * this directory
                         */
                        version (Windows)
                        {
                            // see core.sys.windows.winerror - the reason it's not imported here is because
                            // the autotester's dmd is too old and doesn't have that module
                            enum ERROR_ALREADY_EXISTS = 183;

                            if (GetLastError() != ERROR_ALREADY_EXISTS)
                                return true;
                        }
                        version (Posix)
                        {
                            if (errno != EEXIST)
                                return true;
                        }
                    }
                }
            }
        }

        return false;
    }

    /******************************************
     * Return canonical version of name in a malloc'd buffer.
     * This code is high risk.
     */
    extern (C++) static const(char)* canonicalName(const(char)* name)
    {
        version (Posix)
        {
            // NULL destination buffer is allowed and preferred
            return realpath(name, null);
        }
        else version (Windows)
        {
            // Convert to wstring first since otherwise the Win32 APIs have a character limit
            return name.toDString.toWStringzThen!((wname)
            {
                /* Apparently, there is no good way to do this on Windows.
                 * GetFullPathName isn't it, but use it anyway.
                 */
                // First find out how long the buffer has to be.
                auto fullPathLength = GetFullPathNameW(&wname[0], 0, null, null);
                if (!fullPathLength) return null;
                auto fullPath = new wchar[fullPathLength];

                // Actually get the full path name
                const fullPathLengthNoTerminator = GetFullPathNameW(
                    &wname[0], cast(uint)fullPath.length, &fullPath[0], null /*filePart*/);
                // Unfortunately, when the buffer is large enough the return value is the number of characters
                // _not_ counting the null terminator, so fullPathLengthNoTerminator should be smaller
                assert(fullPathLength > fullPathLengthNoTerminator);

                // Find out size of the converted string
                const retLength = WideCharToMultiByte(
                    0 /*codepage*/, 0 /*flags*/, &fullPath[0], fullPathLength, null, 0, null, null);
                auto ret = new char[retLength];

                // Actually convert to char
                const retLength2 = WideCharToMultiByte(
                    0 /*codepage*/, 0 /*flags*/, &fullPath[0], fullPath.length, &ret[0], cast(int)ret.length, null, null);
                assert(retLength == retLength2);

                return &ret[0];
            });
        }
        else
        {
            assert(0);
        }
    }

    /********************************
     * Free memory allocated by FileName routines
     */
    extern (C++) static void free(const(char)* str)
    {
        if (str)
        {
            assert(str[0] != cast(char)0xAB);
            memset(cast(void*)str, 0xAB, strlen(str) + 1); // stomp
        }
        mem.xfree(cast(void*)str);
    }

    extern (C++) const(char)* toChars() const pure nothrow @safe
    {
        return str;
    }

    const(char)[] toString() const pure nothrow @trusted
    {
        return str ? str[0 .. strlen(str)] : null;
    }
}

version(Windows)
{
    /****************************************************************
     * The code before used the POSIX function `mkdir` on Windows. That
     * function is now deprecated and fails with long paths, so instead
     * we use the newer `CreateDirectoryW`.
     *
     * `CreateDirectoryW` is the unicode version of the generic macro
     * `CreateDirectory`.  `CreateDirectoryA` has a file path
     *  limitation of 248 characters, `mkdir` fails with less and might
     *  fail due to the number of consecutive `..`s in the
     *  path. `CreateDirectoryW` also normally has a 248 character
     * limit, unless the path is absolute and starts with `\\?\`. Note
     * that this is different from starting with the almost identical
     * `\\?`.
     *
     * Params:
     *  path = The path to create.
     *
     * Returns:
     *  0 on success, 1 on failure.
     *
     * References:
     *  https://msdn.microsoft.com/en-us/library/windows/desktop/aa363855(v=vs.85).aspx
     */
    private int _mkdir(const(char)[] path) nothrow
    {
        const createRet = path.extendedPathThen!(
            p => CreateDirectoryW(&p[0], null /*securityAttributes*/));
        // different conventions for CreateDirectory and mkdir
        return createRet == 0 ? 1 : 0;
    }

    /**************************************
     * Converts a path to one suitable to be passed to Win32 API
     * functions that can deal with paths longer than 248
     * characters then calls the supplied function on it.
     *
     * Params:
     *  path = The Path to call F on.
     *
     * Returns:
     *  The result of calling F on path.
     *
     * References:
     *  https://msdn.microsoft.com/en-us/library/windows/desktop/aa365247(v=vs.85).aspx
     */
    package auto extendedPathThen(alias F)(const(char)[] path)
    {
        return path.toDString.toWStringzThen!((wpath)
        {
            // GetFullPathNameW expects a sized buffer to store the result in. Since we don't
            // know how large it has to be, we pass in null and get the needed buffer length
            // as the return code.
            const pathLength = GetFullPathNameW(&wpath[0],
                                                0 /*length8*/,
                                                null /*output buffer*/,
                                                null /*filePartBuffer*/);
            if (pathLength == 0)
            {
                return F(""w.ptr);
            }

            // wpath is the UTF16 version of path, but to be able to use
            // extended paths, we need to prefix with `\\?\` and the absolute
            // path.
            static immutable prefix = `\\?\`w;

            // +1 for the null terminator
            const bufferLength = pathLength + prefix.length + 1;

            wchar[1024] absBuf;
            auto absPath = bufferLength > absBuf.length ? new wchar[bufferLength] : absBuf[];

            absPath[0 .. prefix.length] = prefix[];

            const absPathRet = GetFullPathNameW(wpath,
                                                cast(uint)(absPath.length - prefix.length),
                                                &absPath[prefix.length],
                                                null /*filePartBuffer*/);

            if (absPathRet == 0 || absPathRet > absPath.length - prefix.length)
            {
                return F(""w.ptr);
            }

            return F(absPath);

        });
    }

    /**********************************
     * Converts a slice of UTF-8 characters to an array of wchar that's null
     * terminated so it can be passed to Win32 APIs then calls the supplied
     * function on it.
     *
     * Params:
     *  str = The string to convert.
     *
     * Returns:
     *  The result of calling F on the UTF16 version of str.
     */
    private auto toWStringzThen(alias F)(const(char)[] str) nothrow
    {
        import core.stdc.stdlib: malloc, free;

        wchar[1024] buf;
        // first find out how long the buffer must be to store the result
        const length = MultiByteToWideChar(0 /*codepage*/, 0 /*flags*/, &str[0], str.length, null, 0);
        if (!length) return F(""w.ptr);

        auto ret = length >= buf.length
            ? (cast(wchar*)malloc(length * wchar.sizeof))[0 .. length + 1]
            : buf;
        scope (exit)
        {
            if (&ret[0] != &buf[0])
                free(&ret[0]);
        }
        // actually do the conversion
        const length2 = MultiByteToWideChar(
            0 /*codepage*/, 0 /*flags*/, &str[0], str.length, &ret[0], cast(int)length);
        assert(str.length == length2); // should always be true according to the API
        // Add terminating `\0`
        ret[$ - 1] = '\0';

        return F(ret);
    }
}
