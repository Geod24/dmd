
/* Compiler implementation of the D programming language
 * Copyright (C) 1999-2018 by The D Language Foundation, All Rights Reserved
 * written by Walter Bright
 * http://www.digitalmars.com
 * Distributed under the Boost Software License, Version 1.0.
 * http://www.boost.org/LICENSE_1_0.txt
 * https://github.com/dlang/dmd/blob/master/src/declaration.h
 */

#ifndef DMD_DECLARATION_H
#define DMD_DECLARATION_H

#ifdef __DMC__
#pragma once
#endif /* __DMC__ */

#include "dsymbol.h"
#include "mtype.h"
#include "objc.h"

class Expression;
class Statement;
class LabelDsymbol;
class Initializer;
class Module;
class ForeachStatement;
class FuncDeclaration;
class ExpInitializer;
class StructDeclaration;
struct CompiledCtfeFunction;
struct ObjcSelector;

enum LINK;
enum TOK;
enum MATCH;
enum PURE;
enum PINLINE;

#define STCundefined    0LL
#define STCstatic       1LL
#define STCextern       2LL
#define STCconst        4LL
#define STCfinal        8LL
#define STCabstract     0x10LL
#define STCparameter    0x20LL
#define STCfield        0x40LL
#define STCoverride     0x80LL
#define STCauto         0x100LL
#define STCsynchronized 0x200LL
#define STCdeprecated   0x400LL
#define STCin           0x800LL         // in parameter
#define STCout          0x1000LL        // out parameter
#define STClazy         0x2000LL        // lazy parameter
#define STCforeach      0x4000LL        // variable for foreach loop
#define STCvariadic     0x10000LL       // the 'variadic' parameter in: T foo(T a, U b, V variadic...)
#define STCctorinit     0x20000LL       // can only be set inside constructor
#define STCtemplateparameter  0x40000LL // template parameter
#define STCscope        0x80000LL
#define STCimmutable    0x100000LL
#define STCref          0x200000LL
#define STCinit         0x400000LL      // has explicit initializer
#define STCmanifest     0x800000LL      // manifest constant
#define STCnodtor       0x1000000LL     // don't run destructor
#define STCnothrow      0x2000000LL     // never throws exceptions
#define STCpure         0x4000000LL     // pure function
#define STCtls          0x8000000LL     // thread local
#define STCalias        0x10000000LL    // alias parameter
#define STCshared       0x20000000LL    // accessible from multiple threads
// accessible from multiple threads
// but not typed as "shared"
#define STCgshared      0x40000000LL
#define STCwild         0x80000000LL    // for "wild" type constructor
#define STC_TYPECTOR    (STCconst | STCimmutable | STCshared | STCwild)
#define STC_FUNCATTR    (STCref | STCnothrow | STCnogc | STCpure | STCproperty | STCsafe | STCtrusted | STCsystem)

#define STCproperty      0x100000000LL
#define STCsafe          0x200000000LL
#define STCtrusted       0x400000000LL
#define STCsystem        0x800000000LL
#define STCctfe          0x1000000000LL  // can be used in CTFE, even if it is static
#define STCdisable       0x2000000000LL  // for functions that are not callable
#define STCresult        0x4000000000LL  // for result variables passed to out contracts
#define STCnodefaultctor 0x8000000000LL  // must be set inside constructor
#define STCtemp          0x10000000000LL // temporary variable
#define STCrvalue        0x20000000000LL // force rvalue for variables
#define STCnogc          0x40000000000LL // @nogc
#define STCvolatile      0x80000000000LL // destined for volatile in the back end
#define STCreturn        0x100000000000LL // 'return ref' or 'return scope' for function parameters
#define STCautoref       0x200000000000LL // Mark for the already deduced 'auto ref' parameter
#define STCinference     0x400000000000LL // do attribute inference
#define STCexptemp       0x800000000000LL // temporary variable that has lifetime restricted to an expression
#define STCmaybescope    0x1000000000000LL // parameter might be 'scope'
#define STCscopeinferred 0x2000000000000LL // 'scope' has been inferred and should not be part of mangling
#define STCfuture        0x4000000000000LL // introducing new base class function
#define STClocal         0x8000000000000LL // do not forward (see dmd.dsymbol.ForwardingScopeDsymbol).

const StorageClass STCStorageClass = (STCauto | STCscope | STCstatic | STCextern | STCconst | STCfinal |
    STCabstract | STCsynchronized | STCdeprecated | STCfuture | STCoverride | STClazy | STCalias |
    STCout | STCin |
    STCmanifest | STCimmutable | STCshared | STCwild | STCnothrow | STCnogc | STCpure | STCref | STCreturn | STCtls |
    STCgshared | STCproperty | STCsafe | STCtrusted | STCsystem | STCdisable | STClocal);

struct Match
{
    int count;                  // number of matches found
    MATCH last;                 // match level of lastf
    FuncDeclaration *lastf;     // last matching function we found
    FuncDeclaration *nextf;     // current matching function
    FuncDeclaration *anyf;      // pick a func, any func, to use for error recovery
};

void functionResolve(Match *m, Dsymbol *fd, Loc loc, Scope *sc, Objects *tiargs, Type *tthis, Expressions *fargs, size_t *failedInde = NULL);
int overloadApply(Dsymbol *fstart, void *param, int (*fp)(void *, Dsymbol *));

void ObjectNotFound(Identifier *id);

/**************************************************************/

class Declaration : public Dsymbol
{
public:
    Type *type;
    Type *originalType;         // before semantic analysis
    StorageClass storage_class;
    Prot protection;
    LINK linkage;
    int inuse;                  // used to detect cycles
    const char *mangleOverride;      // overridden symbol with pragma(mangle, "...")

    const char *kind() const;
    d_uns64 size(const Loc &loc);
    bool checkDisabled(Loc loc, Scope* sc, bool isAliasedDeclaration = false);
    int checkModify(Loc loc, Scope *sc, Expression *e1, int flag);

    Dsymbol *search(Loc loc, Identifier *ident, int flags = SearchLocalsOnly);

    bool isStatic() const { return (storage_class & STCstatic) != 0; }
    virtual bool isDelete();
    virtual bool isDataseg();
    virtual bool isThreadlocal();
    virtual bool isCodeseg();
    bool isCtorinit() const     { return (storage_class & STCctorinit) != 0; }
    bool isFinal() const        { return (storage_class & STCfinal) != 0; }
    virtual bool isAbstract()   { return (storage_class & STCabstract) != 0; }
    bool isConst() const        { return (storage_class & STCconst) != 0; }
    bool isImmutable() const    { return (storage_class & STCimmutable) != 0; }
    bool isWild() const         { return (storage_class & STCwild) != 0; }
    bool isAuto() const         { return (storage_class & STCauto) != 0; }
    bool isScope() const        { return (storage_class & STCscope) != 0; }
    bool isSynchronized() const { return (storage_class & STCsynchronized) != 0; }
    bool isParameter() const    { return (storage_class & STCparameter) != 0; }
    bool isDeprecated()         { return (storage_class & STCdeprecated) != 0; }
    bool isOverride() const     { return (storage_class & STCoverride) != 0; }
    bool isResult() const       { return (storage_class & STCresult) != 0; }
    bool isField() const        { return (storage_class & STCfield) != 0; }

    bool isIn()  const  { return (storage_class & STCin) != 0; }
    bool isOut() const  { return (storage_class & STCout) != 0; }
    bool isRef() const  { return (storage_class & STCref) != 0; }

    bool isFuture() const { return (storage_class & STCfuture) != 0; }

    Prot prot();

    Declaration *isDeclaration() { return this; }
    void accept(Visitor *v) { v->visit(this); }
};

/**************************************************************/

class TupleDeclaration : public Declaration
{
public:
    Objects *objects;
    bool isexp;                 // true: expression tuple

    TypeTuple *tupletype;       // !=NULL if this is a type tuple

    Dsymbol *syntaxCopy(Dsymbol *);
    const char *kind() const;
    Type *getType();
    Dsymbol *toAlias2();
    bool needThis();

    TupleDeclaration *isTupleDeclaration() { return this; }
    void accept(Visitor *v) { v->visit(this); }
};

/**************************************************************/

class AliasDeclaration : public Declaration
{
public:
    Dsymbol *aliassym;
    Dsymbol *overnext;          // next in overload list
    Dsymbol *_import;           // !=NULL if unresolved internal alias for selective import

    static AliasDeclaration *create(Loc loc, Identifier *id, Type *type);
    Dsymbol *syntaxCopy(Dsymbol *);
    bool overloadInsert(Dsymbol *s);
    const char *kind() const;
    Type *getType();
    Dsymbol *toAlias();
    Dsymbol *toAlias2();
    bool isOverloadable();

    AliasDeclaration *isAliasDeclaration() { return this; }
    void accept(Visitor *v) { v->visit(this); }
};

/**************************************************************/

class OverDeclaration : public Declaration
{
public:
    Dsymbol *overnext;          // next in overload list
    Dsymbol *aliassym;
    bool hasOverloads;

    const char *kind() const;
    bool equals(RootObject *o);
    bool overloadInsert(Dsymbol *s);

    Dsymbol *toAlias();
    Dsymbol *isUnique();
    bool isOverloadable();

    OverDeclaration *isOverDeclaration() { return this; }
    void accept(Visitor *v) { v->visit(this); }
};

/**************************************************************/

class VarDeclaration : public Declaration
{
public:
    Initializer *_init;
    unsigned offset;
    unsigned sequenceNumber;     // order the variables are declared
    FuncDeclarations nestedrefs; // referenced by these lexically nested functions
    structalign_t alignment;
    bool isargptr;              // if parameter that _argptr points to
    bool ctorinit;              // it has been initialized in a ctor
    bool iscatchvar;            // this is the exception object variable in catch() clause
    bool onstack;               // it is a class that was allocated on the stack
    bool mynew;                 // it is a class new'd with custom operator new
    int canassign;              // it can be assigned to
    bool overlapped;            // if it is a field and has overlapping
    bool overlapUnsafe;         // if it is an overlapping field and the overlaps are unsafe
    bool doNotInferScope;       // do not infer 'scope' for this variable
    unsigned char isdataseg;    // private data for isDataseg
    Dsymbol *aliassym;          // if redone as alias to another symbol
    VarDeclaration *lastVar;    // Linked list of variables for goto-skips-init detection
    unsigned endlinnum;         // line number of end of scope that this var lives in

    // When interpreting, these point to the value (NULL if value not determinable)
    // The index of this variable on the CTFE stack, -1 if not allocated
    int ctfeAdrOnStack;
    Expression *edtor;          // if !=NULL, does the destruction of the variable
    IntRange *range;            // if !NULL, the variable is known to be within the range

    Dsymbol *syntaxCopy(Dsymbol *);
    void setFieldOffset(AggregateDeclaration *ad, unsigned *poffset, bool isunion);
    const char *kind() const;
    AggregateDeclaration *isThis();
    bool needThis();
    bool isExport();
    bool isImportedSymbol();
    bool isDataseg();
    bool isThreadlocal();
    bool isCTFE();
    bool isOverlappedWith(VarDeclaration *v);
    bool hasPointers();
    bool canTakeAddressOf();
    bool needsScopeDtor();
    bool enclosesLifetimeOf(VarDeclaration *v) const;
    Expression *callScopeDtor(Scope *sc);
    Expression *getConstInitializer(bool needFullType = true);
    Expression *expandInitializer(Loc loc);
    void checkCtorConstInit();
    bool checkNestedReference(Scope *sc, Loc loc);
    Dsymbol *toAlias();
    // Eliminate need for dynamic_cast
    VarDeclaration *isVarDeclaration() { return (VarDeclaration *)this; }
    void accept(Visitor *v) { v->visit(this); }
};

/**************************************************************/

// This is a shell around a back end symbol

class SymbolDeclaration : public Declaration
{
public:
    StructDeclaration *dsym;

    // Eliminate need for dynamic_cast
    SymbolDeclaration *isSymbolDeclaration() { return (SymbolDeclaration *)this; }
    void accept(Visitor *v) { v->visit(this); }
};

class TypeInfoDeclaration : public VarDeclaration
{
public:
    Type *tinfo;

    static TypeInfoDeclaration *create(Type *tinfo);
    Dsymbol *syntaxCopy(Dsymbol *);
    const char *toChars();

    TypeInfoDeclaration *isTypeInfoDeclaration() { return this; }
    void accept(Visitor *v) { v->visit(this); }
};

class TypeInfoStructDeclaration : public TypeInfoDeclaration
{
public:
    static TypeInfoStructDeclaration *create(Type *tinfo);

    void accept(Visitor *v) { v->visit(this); }
};

class TypeInfoClassDeclaration : public TypeInfoDeclaration
{
public:
    static TypeInfoClassDeclaration *create(Type *tinfo);

    void accept(Visitor *v) { v->visit(this); }
};

class TypeInfoInterfaceDeclaration : public TypeInfoDeclaration
{
public:
    static TypeInfoInterfaceDeclaration *create(Type *tinfo);

    void accept(Visitor *v) { v->visit(this); }
};

class TypeInfoPointerDeclaration : public TypeInfoDeclaration
{
public:
    static TypeInfoPointerDeclaration *create(Type *tinfo);

    void accept(Visitor *v) { v->visit(this); }
};

class TypeInfoArrayDeclaration : public TypeInfoDeclaration
{
public:
    static TypeInfoArrayDeclaration *create(Type *tinfo);

    void accept(Visitor *v) { v->visit(this); }
};

class TypeInfoStaticArrayDeclaration : public TypeInfoDeclaration
{
public:
    static TypeInfoStaticArrayDeclaration *create(Type *tinfo);

    void accept(Visitor *v) { v->visit(this); }
};

class TypeInfoAssociativeArrayDeclaration : public TypeInfoDeclaration
{
public:
    static TypeInfoAssociativeArrayDeclaration *create(Type *tinfo);

    void accept(Visitor *v) { v->visit(this); }
};

class TypeInfoEnumDeclaration : public TypeInfoDeclaration
{
public:
    static TypeInfoEnumDeclaration *create(Type *tinfo);

    void accept(Visitor *v) { v->visit(this); }
};

class TypeInfoFunctionDeclaration : public TypeInfoDeclaration
{
public:
    static TypeInfoFunctionDeclaration *create(Type *tinfo);

    void accept(Visitor *v) { v->visit(this); }
};

class TypeInfoDelegateDeclaration : public TypeInfoDeclaration
{
public:
    static TypeInfoDelegateDeclaration *create(Type *tinfo);

    void accept(Visitor *v) { v->visit(this); }
};

class TypeInfoTupleDeclaration : public TypeInfoDeclaration
{
public:
    static TypeInfoTupleDeclaration *create(Type *tinfo);

    void accept(Visitor *v) { v->visit(this); }
};

class TypeInfoConstDeclaration : public TypeInfoDeclaration
{
public:
    static TypeInfoConstDeclaration *create(Type *tinfo);

    void accept(Visitor *v) { v->visit(this); }
};

class TypeInfoInvariantDeclaration : public TypeInfoDeclaration
{
public:
    static TypeInfoInvariantDeclaration *create(Type *tinfo);

    void accept(Visitor *v) { v->visit(this); }
};

class TypeInfoSharedDeclaration : public TypeInfoDeclaration
{
public:
    static TypeInfoSharedDeclaration *create(Type *tinfo);

    void accept(Visitor *v) { v->visit(this); }
};

class TypeInfoWildDeclaration : public TypeInfoDeclaration
{
public:
    static TypeInfoWildDeclaration *create(Type *tinfo);

    void accept(Visitor *v) { v->visit(this); }
};

class TypeInfoVectorDeclaration : public TypeInfoDeclaration
{
public:
    static TypeInfoVectorDeclaration *create(Type *tinfo);

    void accept(Visitor *v) { v->visit(this); }
};

/**************************************************************/

class ThisDeclaration : public VarDeclaration
{
public:
    Dsymbol *syntaxCopy(Dsymbol *);
    ThisDeclaration *isThisDeclaration() { return this; }
    void accept(Visitor *v) { v->visit(this); }
};

enum ILS
{
    ILSuninitialized,   // not computed yet
    ILSno,              // cannot inline
    ILSyes,             // can inline
};

/**************************************************************/

enum BUILTIN
{
    BUILTINunknown = -1,        // not known if this is a builtin
    BUILTINno,                  // this is not a builtin
    BUILTINyes,                 // this is a builtin
};

Expression *eval_builtin(Loc loc, FuncDeclaration *fd, Expressions *arguments);
BUILTIN isBuiltin(FuncDeclaration *fd);

typedef Expression *(*builtin_fp)(Loc loc, FuncDeclaration *fd, Expressions *arguments);
void add_builtin(const char *mangle, builtin_fp fp);
void builtin_init();

#define FUNCFLAGpurityInprocess    1    // working on determining purity
#define FUNCFLAGsafetyInprocess    2    // working on determining safety
#define FUNCFLAGnothrowInprocess   4    // working on determining nothrow
#define FUNCFLAGnogcInprocess      8    // working on determining @nogc
#define FUNCFLAGreturnInprocess 0x10    // working on inferring 'return' for parameters
#define FUNCFLAGinlineScanned   0x20    // function has been scanned for inline possibilities
#define FUNCFLAGinferScope      0x40    // infer 'scope' for parameters
#define FUNCFLAGhasCatches      0x80    // function has try-catch statements

class FuncDeclaration : public Declaration
{
public:
    Types *fthrows;                     // Array of Type's of exceptions (not used)
    Statement *frequire;
    Statement *fensure;
    Statement *fbody;

    FuncDeclarations foverrides;        // functions this function overrides
    FuncDeclaration *fdrequire;         // function that does the in contract
    FuncDeclaration *fdensure;          // function that does the out contract

    const char *mangleString;           // mangled symbol created from mangleExact()

    Identifier *outId;                  // identifier for out statement
    VarDeclaration *vresult;            // variable corresponding to outId
    LabelDsymbol *returnLabel;          // where the return goes

    // used to prevent symbols in different
    // scopes from having the same name
    DsymbolTable *localsymtab;
    VarDeclaration *vthis;              // 'this' parameter (member and nested)
    VarDeclaration *v_arguments;        // '_arguments' parameter
    ObjcSelector* selector;             // Objective-C method selector (member function only)
    VarDeclaration *v_argptr;           // '_argptr' variable
    VarDeclarations *parameters;        // Array of VarDeclaration's for parameters
    DsymbolTable *labtab;               // statement label symbol table
    Dsymbol *overnext;                  // next in overload list
    FuncDeclaration *overnext0;         // next in overload list (only used during IFTI)
    Loc endloc;                         // location of closing curly bracket
    int vtblIndex;                      // for member functions, index into vtbl[]
    bool naked;                         // true if naked
    bool generated;                     // true if function was generated by the compiler rather than
                                        // supplied by the user
    ILS inlineStatusStmt;
    ILS inlineStatusExp;
    PINLINE inlining;

    CompiledCtfeFunction *ctfeCode;     // Compiled code for interpreter
    int inlineNest;                     // !=0 if nested inline
    bool isArrayOp;                     // true if array operation
    bool eh_none;                       /// true if no exception unwinding is needed

    // true if errors in semantic3 this function's frame ptr
    bool semantic3Errors;
    ForeachStatement *fes;              // if foreach body, this is the foreach
    BaseClass* interfaceVirtual;        // if virtual, but only appears in interface vtbl[]
    bool introducing;                   // true if 'introducing' function
    // if !=NULL, then this is the type
    // of the 'introducing' function
    // this one is overriding
    Type *tintro;
    bool inferRetType;                  // true if return type is to be inferred
    StorageClass storage_class2;        // storage class for template onemember's

    // Things that should really go into Scope

    // 1 if there's a return exp; statement
    // 2 if there's a throw statement
    // 4 if there's an assert(0)
    // 8 if there's inline asm
    // 16 if there are multiple return statements
    int hasReturnExp;

    // Support for NRVO (named return value optimization)
    bool nrvo_can;                      // true means we can do it
    VarDeclaration *nrvo_var;           // variable to replace with shidden
    Symbol *shidden;                    // hidden pointer passed to function

    ReturnStatements *returns;

    GotoStatements *gotos;              // Gotos with forward references

    // set if this is a known, builtin function we can evaluate at compile time
    BUILTIN builtin;

    // set if someone took the address of this function
    int tookAddressOf;
    bool requiresClosure;               // this function needs a closure

    // local variables in this function which are referenced by nested functions
    VarDeclarations closureVars;
    // Sibling nested functions which called this one
    FuncDeclarations siblingCallers;

    FuncDeclarations *inlinedNestedCallees;

    unsigned flags;                     // FUNCFLAGxxxxx

    static FuncDeclaration *create(const Loc &loc, const Loc &endloc, Identifier *id, StorageClass storage_class, Type *type);
    Dsymbol *syntaxCopy(Dsymbol *);
    bool functionSemantic();
    bool functionSemantic3();
    bool checkForwardRef(const Loc &loc);
    // called from semantic3
    VarDeclaration *declareThis(Scope *sc, AggregateDeclaration *ad);
    bool equals(RootObject *o);

    int overrides(FuncDeclaration *fd);
    int findVtblIndex(Dsymbols *vtbl, int dim, bool fix17349 = true);
    BaseClass *overrideInterface();
    bool overloadInsert(Dsymbol *s);
    FuncDeclaration *overloadExactMatch(Type *t);
    FuncDeclaration *overloadModMatch(const Loc &loc, Type *tthis, bool &hasOverloads);
    TemplateDeclaration *findTemplateDeclRoot();
    bool inUnittest();
    MATCH leastAsSpecialized(FuncDeclaration *g);
    LabelDsymbol *searchLabel(Identifier *ident);
    int getLevel(const Loc &loc, Scope *sc, FuncDeclaration *fd); // lexical nesting level difference
    const char *toPrettyChars(bool QualifyTypes = false);
    const char *toFullSignature();  // for diagnostics, e.g. 'int foo(int x, int y) pure'
    bool isMain() const;
    bool isCMain() const;
    bool isWinMain() const;
    bool isDllMain() const;
    bool isExport() const;
    bool isImportedSymbol() const;
    bool isCodeseg() const;
    bool isOverloadable();
    bool isAbstract();
    PURE isPure();
    PURE isPureBypassingInference();
    bool setImpure();
    bool isSafe();
    bool isSafeBypassingInference();
    bool isTrusted();
    bool setUnsafe();

    bool isNogc();
    bool isNogcBypassingInference();
    bool setGC();

    void printGCUsage(const Loc &loc, const char *warn);
    bool isolateReturn();
    bool parametersIntersect(Type *t);
    virtual bool isNested();
    AggregateDeclaration *isThis();
    bool needThis();
    bool isVirtualMethod();
    virtual bool isVirtual() const;
    bool isFinalFunc() const;
    virtual bool addPreInvariant();
    virtual bool addPostInvariant();
    const char *kind() const;
    FuncDeclaration *isUnique();
    bool checkNestedReference(Scope *sc, Loc loc);
    bool needsClosure();
    bool checkClosure();
    bool hasNestedFrameRefs();
    void buildResultVar(Scope *sc, Type *tret);
    Statement *mergeFrequire(Statement *);
    Statement *mergeFensure(Statement *, Identifier *oid);
    Parameters *getParameters(int *pvarargs);

    static FuncDeclaration *genCfunc(Parameters *args, Type *treturn, const char *name, StorageClass stc=0);
    static FuncDeclaration *genCfunc(Parameters *args, Type *treturn, Identifier *id, StorageClass stc=0);
    void checkDmain();

    FuncDeclaration *isFuncDeclaration() { return this; }

    virtual FuncDeclaration *toAliasFunc() { return this; }
    void accept(Visitor *v) { v->visit(this); }
};

FuncDeclaration *resolveFuncCall(const Loc &loc, Scope *sc, Dsymbol *s,
        Objects *tiargs,
        Type *tthis,
        Expressions *arguments,
        int flags = 0);

class FuncAliasDeclaration : public FuncDeclaration
{
public:
    FuncDeclaration *funcalias;
    bool hasOverloads;

    FuncAliasDeclaration *isFuncAliasDeclaration() { return this; }
    const char *kind() const;

    FuncDeclaration *toAliasFunc();
    void accept(Visitor *v) { v->visit(this); }
};

class FuncLiteralDeclaration : public FuncDeclaration
{
public:
    TOK tok;                       // TOKfunction or TOKdelegate
    Type *treq;                         // target of return type inference

    // backend
    bool deferToObj;

    Dsymbol *syntaxCopy(Dsymbol *);
    bool isNested();
    AggregateDeclaration *isThis();
    bool isVirtual() const;
    bool addPreInvariant();
    bool addPostInvariant();

    void modifyReturns(Scope *sc, Type *tret);

    FuncLiteralDeclaration *isFuncLiteralDeclaration() { return this; }
    const char *kind() const;
    const char *toPrettyChars(bool QualifyTypes = false);
    void accept(Visitor *v) { v->visit(this); }
};

class CtorDeclaration : public FuncDeclaration
{
public:
    Dsymbol *syntaxCopy(Dsymbol *);
    const char *kind() const;
    const char *toChars();
    bool isVirtual() const;
    bool addPreInvariant();
    bool addPostInvariant();

    CtorDeclaration *isCtorDeclaration() { return this; }
    void accept(Visitor *v) { v->visit(this); }
};

class PostBlitDeclaration : public FuncDeclaration
{
public:
    Dsymbol *syntaxCopy(Dsymbol *);
    bool isVirtual() const;
    bool addPreInvariant();
    bool addPostInvariant();
    bool overloadInsert(Dsymbol *s);

    PostBlitDeclaration *isPostBlitDeclaration() { return this; }
    void accept(Visitor *v) { v->visit(this); }
};

class DtorDeclaration : public FuncDeclaration
{
public:
    Dsymbol *syntaxCopy(Dsymbol *);
    const char *kind() const;
    const char *toChars();
    bool isVirtual() const;
    bool addPreInvariant();
    bool addPostInvariant();
    bool overloadInsert(Dsymbol *s);

    DtorDeclaration *isDtorDeclaration() { return this; }
    void accept(Visitor *v) { v->visit(this); }
};

class StaticCtorDeclaration : public FuncDeclaration
{
public:
    Dsymbol *syntaxCopy(Dsymbol *);
    AggregateDeclaration *isThis();
    bool isVirtual() const;
    bool addPreInvariant();
    bool addPostInvariant();
    bool hasStaticCtorOrDtor();

    StaticCtorDeclaration *isStaticCtorDeclaration() { return this; }
    void accept(Visitor *v) { v->visit(this); }
};

class SharedStaticCtorDeclaration : public StaticCtorDeclaration
{
public:
    Dsymbol *syntaxCopy(Dsymbol *);

    SharedStaticCtorDeclaration *isSharedStaticCtorDeclaration() { return this; }
    void accept(Visitor *v) { v->visit(this); }
};

class StaticDtorDeclaration : public FuncDeclaration
{
public:
    VarDeclaration *vgate;      // 'gate' variable

    Dsymbol *syntaxCopy(Dsymbol *);
    AggregateDeclaration *isThis();
    bool isVirtual() const;
    bool hasStaticCtorOrDtor();
    bool addPreInvariant();
    bool addPostInvariant();

    StaticDtorDeclaration *isStaticDtorDeclaration() { return this; }
    void accept(Visitor *v) { v->visit(this); }
};

class SharedStaticDtorDeclaration : public StaticDtorDeclaration
{
public:
    Dsymbol *syntaxCopy(Dsymbol *);

    SharedStaticDtorDeclaration *isSharedStaticDtorDeclaration() { return this; }
    void accept(Visitor *v) { v->visit(this); }
};

class InvariantDeclaration : public FuncDeclaration
{
public:
    Dsymbol *syntaxCopy(Dsymbol *);
    bool isVirtual() const;
    bool addPreInvariant();
    bool addPostInvariant();

    InvariantDeclaration *isInvariantDeclaration() { return this; }
    void accept(Visitor *v) { v->visit(this); }
};

class UnitTestDeclaration : public FuncDeclaration
{
public:
    char *codedoc; /** For documented unittest. */

    // toObjFile() these nested functions after this one
    FuncDeclarations deferredNested;

    Dsymbol *syntaxCopy(Dsymbol *);
    AggregateDeclaration *isThis();
    bool isVirtual() const;
    bool addPreInvariant();
    bool addPostInvariant();

    UnitTestDeclaration *isUnitTestDeclaration() { return this; }
    void accept(Visitor *v) { v->visit(this); }
};

class NewDeclaration : public FuncDeclaration
{
public:
    Parameters *parameters;
    int varargs;

    Dsymbol *syntaxCopy(Dsymbol *);
    const char *kind() const;
    bool isVirtual() const;
    bool addPreInvariant();
    bool addPostInvariant();

    NewDeclaration *isNewDeclaration() { return this; }
    void accept(Visitor *v) { v->visit(this); }
};


class DeleteDeclaration : public FuncDeclaration
{
public:
    Parameters *parameters;

    Dsymbol *syntaxCopy(Dsymbol *);
    const char *kind() const;
    bool isDelete();
    bool isVirtual() const;
    bool addPreInvariant();
    bool addPostInvariant();

    DeleteDeclaration *isDeleteDeclaration() { return this; }
    void accept(Visitor *v) { v->visit(this); }
};

#endif /* DMD_DECLARATION_H */
