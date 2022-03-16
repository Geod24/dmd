/**
 * Read a file from disk and store it in memory.
 *
 * Copyright: Copyright (C) 1999-2022 by The D Language Foundation, All Rights Reserved
 * License:   $(LINK2 https://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Source:    $(LINK2 https://github.com/dlang/dmd/blob/master/src/dmd/file_manager.d, _file_manager.d)
 * Documentation:  https://dlang.org/phobos/dmd_file_manager.html
 * Coverage:    https://codecov.io/gh/dlang/dmd/src/master/src/dmd/file_manager.d
 */

module dmd.file_manager;

import dmd.common.outbuffer;
import dmd.root.stringtable : StringTable;
import dmd.root.file : File, FileBuffer;
import dmd.root.filename : FileName;
import dmd.root.port;
import dmd.root.string : toDString;
import dmd.errors;
import dmd.globals;
import dmd.identifier;

enum package_d  = "package." ~ mars_ext;
enum package_di = "package." ~ hdr_ext;

extern(C++) struct FileManager
{
    private StringTable!(FileBuffer*) files;
    private __gshared bool initialized = false;

nothrow:
    /********************************************
    * Look for the source file if it's different from filename.
    * Look for .di, .d, directory, and along global.path.
    * Does not open the file.
    * Params:
    *      filename = as supplied by the user
    *      path = path to look for filename
    * Returns:
    *      the found file name or
    *      `null` if it is not different from filename.
    */
    extern(D) static const(char)[] lookForSourceFile(const char[] filename, const char*[] path)
    {
        //printf("lookForSourceFile(`%.*s`)\n", cast(int)filename.length, filename.ptr);
        /* Search along path[] for .di file, then .d file, then .i file, then .c file.
        */
        const sdi = FileName.forceExt(filename, hdr_ext);
        if (FileName.exists(sdi) == 1)
            return sdi;
        scope(exit) FileName.free(sdi.ptr);

        const sd = FileName.forceExt(filename, mars_ext);
        // Special file name representing `stdin`, always assume its presence
        if (sd == "__stdin.d")
            return sd;
        if (FileName.exists(sd) == 1)
            return sd;
        scope(exit) FileName.free(sd.ptr);

        const si = FileName.forceExt(filename, i_ext);
        if (FileName.exists(si) == 1)
            return si;
        scope(exit) FileName.free(si.ptr);

        const sc = FileName.forceExt(filename, c_ext);
        if (FileName.exists(sc) == 1)
            return sc;
        scope(exit) FileName.free(sc.ptr);

        if (FileName.exists(filename) == 2)
        {
            /* The filename exists and it's a directory.
            * Therefore, the result should be: filename/package.d
            * iff filename/package.d is a file
            */
            const ni = FileName.combine(filename, package_di);
            if (FileName.exists(ni) == 1)
                return ni;
            FileName.free(ni.ptr);

            const n = FileName.combine(filename, package_d);
            if (FileName.exists(n) == 1)
                return n;
            FileName.free(n.ptr);
        }
        if (FileName.absolute(filename))
            return null;
        if (!path.length)
            return null;
        foreach (entry; path)
        {
            const p = entry.toDString();

            const(char)[] n = FileName.combine(p, sdi);
            if (FileName.exists(n) == 1) {
                return n;
            }
            FileName.free(n.ptr);

            n = FileName.combine(p, sd);
            if (FileName.exists(n) == 1) {
                return n;
            }
            FileName.free(n.ptr);

            n = FileName.combine(p, si);
            if (FileName.exists(n) == 1) {
                return n;
            }
            FileName.free(n.ptr);

            n = FileName.combine(p, sc);
            if (FileName.exists(n) == 1) {
                return n;
            }
            FileName.free(n.ptr);

            const b = FileName.removeExt(filename);
            n = FileName.combine(p, b);
            FileName.free(b.ptr);
            if (FileName.exists(n) == 2)
            {
                const n2i = FileName.combine(n, package_di);
                if (FileName.exists(n2i) == 1)
                    return n2i;
                FileName.free(n2i.ptr);
                const n2 = FileName.combine(n, package_d);
                if (FileName.exists(n2) == 1) {
                    return n2;
                }
                FileName.free(n2.ptr);
            }
            FileName.free(n.ptr);
        }
        return null;
    }

    /**
     * Looks up the given filename from the internal file buffer table.
     * If the file does not already exist within the table, it will be read from the filesystem.
     * If it has been read before,
     *
     * Returns: the loaded source file if it was found in memory,
     *      otherwise `null`
     */
    extern(D) const(FileBuffer)* lookup(FileName filename)
    {
        if (!initialized)
            FileManager._init();

        const name = filename.toString;
        if (auto val = files.lookup(name))
            return val.value;

        if (name == "__stdin.d")
        {
            auto buffer = new FileBuffer(readFromStdin().extractSlice());
            if (this.files.insert(name, buffer))
                assert(0, "stdin: Insert after lookup failure should never return `null`");
            return buffer;
        }

        if (FileName.exists(name) != 1)
            return null;

        auto readResult = File.read(name);
        if (!readResult.success)
            return null;

        FileBuffer* fb = new FileBuffer(readResult.extractSlice());
        if (files.insert(name, fb) is null)
            assert(0, "Insert after lookup failure should never return `null`");

        return fb;
    }

    extern(C++) const(FileBuffer)* lookup(const(char)* filename)
    {
        return lookup(FileName(filename.toDString));
    }

    /**
     * Looks up the given filename from the internal file buffer table, and returns the lines within the file.
     * If the file does not already exist within the table, it will be read from the filesystem.
     * If it has been read before,
     *
     * Returns: the loaded source file if it was found in memory,
     *      otherwise `null`
     */
    extern(D) const(char)[][] getLines(FileName file)
    {
        if (!initialized)
            FileManager._init();

        const(char)[][] lines;
        if (const buffer = lookup(file))
        {
            const slice = buffer.data[0 .. buffer.data.length];
            size_t start, end;
            ubyte c;
            for (auto i = 0; i < slice.length; i++)
            {
                c = slice[i];
                if (c == '\n' || c == '\r')
                {
                    if (i != 0)
                    {
                        end = i;
                        lines ~= cast(const(char)[])slice[start .. end];
                    }
                    // Check for Windows-style CRLF newlines
                    if (c == '\r')
                    {
                        if (slice.length > i + 1 && slice[i + 1] == '\n')
                        {
                            // This is a CRLF sequence, skip over two characters
                            start = i + 2;
                            i++;
                        }
                        else
                        {
                            // Just a CR sequence
                            start = i + 1;
                        }
                    }
                    else
                    {
                        // The next line should start after the LF sequence
                        start = i + 1;
                    }
                }
            }

            if (slice[$ - 1] != '\r' && slice[$ - 1] != '\n')
            {
                end = slice.length;
                lines ~= cast(const(char)[])slice[start .. end];
            }
        }

        return lines;
    }

    /**
     * Adds a FileBuffer to the table.
     *
     * Returns: The FileBuffer added, or null
     */
    extern(D) FileBuffer* add(FileName filename, FileBuffer* filebuffer)
    {
        if (!initialized)
            FileManager._init();

        auto val = files.insert(filename.toString, filebuffer);
        return val == null ? null : val.value;
    }

    extern(C++) FileBuffer* add(const(char)* filename, FileBuffer* filebuffer)
    {
        if (!initialized)
            FileManager._init();

        auto val = files.insert(filename.toDString, filebuffer);
        return val == null ? null : val.value;
    }

    __gshared fileManager = FileManager();

    // Initialize the global FileManager singleton
    extern(C++) static __gshared void _init()
    {
        if (!initialized)
        {
            fileManager.initialize();
            initialized = true;
        }
    }

    void initialize()
    {
        files._init();
    }
}

private FileBuffer readFromStdin() nothrow
{
    import core.stdc.stdio;
    import dmd.errors;
    import dmd.root.rmem;

    enum bufIncrement = 128 * 1024;
    size_t pos = 0;
    size_t sz = bufIncrement;

    ubyte* buffer = null;
    for (;;)
    {
        buffer = cast(ubyte*)mem.xrealloc(buffer, sz + 4); // +2 for sentinel and +2 for lexer

        // Fill up buffer
        do
        {
            assert(sz > pos);
            size_t rlen = fread(buffer + pos, 1, sz - pos, stdin);
            pos += rlen;
            if (ferror(stdin))
            {
                import core.stdc.errno;
                error(Loc.initial, "cannot read from stdin, errno = %d", errno);
                fatal();
            }
            if (feof(stdin))
            {
                // We're done
                assert(pos < sz + 2);
                buffer[pos .. pos + 4] = '\0';
                return FileBuffer(buffer[0 .. pos]);
            }
        } while (pos < sz);

        // Buffer full, expand
        sz += bufIncrement;
    }

    assert(0);
}

///
private enum Endian { little, big, }

/**
 * Convert a buffer from UTF32 to UTF8
 * Params:
 *    Endian = is the buffer big/little endian
 *    buf = buffer of UTF32 data
 *    fname = Contains the file path from where `buf` originated
 * Returns:
 *    input buffer reencoded as UTF8
 */
private char[] UTF32ToUTF8(Endian endian)(const(char)[] buf, const ref Loc fname)
{
    static if (endian == Endian.little)
        alias readNext = Port.readlongLE;
    else
        alias readNext = Port.readlongBE;

    if (buf.length & 3)
    {
        error(fname, "odd length of UTF-32 char source %llu", cast(ulong) buf.length);
        return null;
    }

    const(uint)[] eBuf = cast(const(uint)[])buf;

    OutBuffer dbuf;
    dbuf.reserve(eBuf.length);

    foreach (i; 0 .. eBuf.length)
    {
        const u = readNext(&eBuf[i]);
        if (u & ~0x7F)
        {
            if (u > 0x10FFFF)
            {
                error(fname, "UTF-32 value %08x greater than 0x10FFFF", u);
                return null;
            }
            dbuf.writeUTF8(u);
        }
        else
            dbuf.writeByte(u);
    }
    dbuf.writeByte(0); //add null terminator
    return dbuf.extractSlice();
}

/**
 * Convert a buffer from UTF16 to UTF8
 * Params:
 *    Endian = is the buffer big/little endian
 *    buf = buffer of UTF16 data
 *    fname = Contains the file path from where `buf` originated
 * Returns:
 *    input buffer reencoded as UTF8
 */
private char[] UTF16ToUTF8(Endian endian)(const(char)[] buf, const ref Loc fname)
{
    static if (endian == Endian.little)
        alias readNext = Port.readwordLE;
    else
        alias readNext = Port.readwordBE;

    if (buf.length & 1)
    {
        error(fname, "odd length of UTF-16 char source %llu", cast(ulong) buf.length);
        return null;
    }

    const(ushort)[] eBuf = cast(const(ushort)[])buf;

    OutBuffer dbuf;
    dbuf.reserve(eBuf.length);

    //i will be incremented in the loop for high codepoints
    foreach (ref i; 0 .. eBuf.length)
    {
        uint u = readNext(&eBuf[i]);
        if (u & ~0x7F)
        {
            if (0xD800 <= u && u < 0xDC00)
            {
                i++;
                if (i >= eBuf.length)
                {
                    error(fname, "surrogate UTF-16 high value %04x at end of file", u);
                    return null;
                }
                const u2 = readNext(&eBuf[i]);
                if (u2 < 0xDC00 || 0xE000 <= u2)
                {
                    error(fname, "surrogate UTF-16 low value %04x out of range", u2);
                    return null;
                }
                u = (u - 0xD7C0) << 10;
                u |= (u2 - 0xDC00);
            }
            else if (u >= 0xDC00 && u <= 0xDFFF)
            {
                error(fname, "unpaired surrogate UTF-16 value %04x", u);
                return null;
            }
            else if (u == 0xFFFE || u == 0xFFFF)
            {
                error(fname, "illegal UTF-16 value %04x", u);
                return null;
            }
            dbuf.writeUTF8(u);
        }
        else
            dbuf.writeByte(u);
    }
    dbuf.writeByte(0); //add a terminating null byte
    return dbuf.extractSlice();
}

/**
 * Process the content of a source file, attempting to find which encoding
 * it is using, if it has BOM, etc...
 */
public const(char)[] processSource (const(ubyte)[] src, const Loc fname)
{
    enum SourceEncoding { utf16, utf32, }

    bool needsReencoding = true;
    bool hasBOM = true; //assume there's a BOM
    Endian endian;
    SourceEncoding sourceEncoding;

    const(char)[] buf = cast(const(char)[]) src;

    if (buf.length >= 2)
    {
        /* Convert all non-UTF-8 formats to UTF-8.
         * BOM : https://www.unicode.org/faq/utf_bom.html
         * 00 00 FE FF  UTF-32BE, big-endian
         * FF FE 00 00  UTF-32LE, little-endian
         * FE FF        UTF-16BE, big-endian
         * FF FE        UTF-16LE, little-endian
         * EF BB BF     UTF-8
         */
        if (buf[0] == 0xFF && buf[1] == 0xFE)
        {
            endian = Endian.little;

            sourceEncoding = buf.length >= 4 && buf[2] == 0 && buf[3] == 0
                             ? SourceEncoding.utf32
                             : SourceEncoding.utf16;
        }
        else if (buf[0] == 0xFE && buf[1] == 0xFF)
        {
            endian = Endian.big;
            sourceEncoding = SourceEncoding.utf16;
        }
        else if (buf.length >= 4 && buf[0] == 0 && buf[1] == 0 && buf[2] == 0xFE && buf[3] == 0xFF)
        {
            endian = Endian.big;
            sourceEncoding = SourceEncoding.utf32;
        }
        else if (buf.length >= 3 && buf[0] == 0xEF && buf[1] == 0xBB && buf[2] == 0xBF)
        {
            needsReencoding = false;//utf8 with BOM
        }
        else
        {
            /* There is no BOM. Make use of Arcane Jill's insight that
             * the first char of D source must be ASCII to
             * figure out the encoding.
             */
            hasBOM = false;
            if (buf.length >= 4 && buf[1] == 0 && buf[2] == 0 && buf[3] == 0)
            {
                endian = Endian.little;
                sourceEncoding = SourceEncoding.utf32;
            }
            else if (buf.length >= 4 && buf[0] == 0 && buf[1] == 0 && buf[2] == 0)
            {
                endian = Endian.big;
                sourceEncoding = SourceEncoding.utf32;
            }
            else if (buf.length >= 2 && buf[1] == 0) //try to check for UTF-16
            {
                endian = Endian.little;
                sourceEncoding = SourceEncoding.utf16;
            }
            else if (buf[0] == 0)
            {
                endian = Endian.big;
                sourceEncoding = SourceEncoding.utf16;
            }
            else {
                // It's UTF-8
                needsReencoding = false;
                if (buf[0] >= 0x80)
                {
                    error(fname, "source file must start with BOM or ASCII character, not \\x%02X", buf[0]);
                    return null;
                }
            }
        }
        //throw away BOM
        if (hasBOM)
        {
            if (!needsReencoding) buf = buf[3..$];// utf-8 already
            else if (sourceEncoding == SourceEncoding.utf32) buf = buf[4..$];
            else buf = buf[2..$]; //utf 16
        }
    }
    // Assume the buffer is from memory and has not be read from disk. Assume UTF-8.
    else if (buf.length >= 1 && (buf[0] == '\0' || buf[0] == 0x1A))
        needsReencoding = false;
    //printf("%s, %d, %d, %d\n", srcfile.name.toChars(), needsReencoding, endian == Endian.little, sourceEncoding == SourceEncoding.utf16);
    if (needsReencoding)
    {
        if (sourceEncoding == SourceEncoding.utf16)
        {
            buf = endian == Endian.little
                  ? UTF16ToUTF8!(Endian.little)(buf, fname)
                  : UTF16ToUTF8!(Endian.big)(buf, fname);
        }
        else
        {
            buf = endian == Endian.little
                  ? UTF32ToUTF8!(Endian.little)(buf, fname)
                  : UTF32ToUTF8!(Endian.big)(buf, fname);
        }
     }
    return buf;
}
