"""Dump index-store occurrences (symbol, roles, containedBy) via libIndexStore C API."""
import ctypes as C, os, subprocess, sys
lib = C.CDLL(os.path.join(os.path.dirname(subprocess.check_output(["xcrun","--find","swiftc"]).decode().strip()), "../lib/libIndexStore.dylib"))
class SR(C.Structure): _fields_=[("data",C.c_char_p),("length",C.c_size_t)]
def s(sr): return C.string_at(sr.data, sr.length).decode() if sr.data else ""
P=C.c_void_p
lib.indexstore_store_create.restype=P; lib.indexstore_store_create.argtypes=[C.c_char_p,C.POINTER(P)]
lib.indexstore_record_reader_create.restype=P; lib.indexstore_record_reader_create.argtypes=[P,C.c_char_p,C.POINTER(P)]
OCC=C.CFUNCTYPE(C.c_bool,P,P); REL=C.CFUNCTYPE(C.c_bool,P,P)
lib.indexstore_record_reader_occurrences_apply_f.argtypes=[P,P,OCC]
lib.indexstore_occurrence_get_symbol.restype=P; lib.indexstore_occurrence_get_symbol.argtypes=[P]
lib.indexstore_occurrence_get_roles.restype=C.c_uint64; lib.indexstore_occurrence_get_roles.argtypes=[P]
lib.indexstore_occurrence_get_line_col.argtypes=[P,C.POINTER(C.c_uint),C.POINTER(C.c_uint)]
lib.indexstore_occurrence_relations_apply_f.argtypes=[P,P,REL]
lib.indexstore_symbol_relation_get_symbol.restype=P; lib.indexstore_symbol_relation_get_symbol.argtypes=[P]
lib.indexstore_symbol_relation_get_roles.restype=C.c_uint64; lib.indexstore_symbol_relation_get_roles.argtypes=[P]
lib.indexstore_symbol_get_name.restype=SR; lib.indexstore_symbol_get_name.argtypes=[P]
lib.indexstore_symbol_get_usr.restype=SR; lib.indexstore_symbol_get_usr.argtypes=[P]
store=sys.argv[1]; err=P()
st=lib.indexstore_store_create(store.encode(),C.byref(err))
CONTAINED=(1<<16)|(1<<13)  # REL_CONTAINEDBY, REL_CALLEDBY
for root,_,fs in os.walk(os.path.join(store,"v5","records")):
    for f in fs:
        rd=lib.indexstore_record_reader_create(st,f.encode(),C.byref(err))
        print("##",f)
        def occ(ctx,o):
            sym=lib.indexstore_occurrence_get_symbol(o); roles=lib.indexstore_occurrence_get_roles(o)
            l=C.c_uint(); c=C.c_uint(); lib.indexstore_occurrence_get_line_col(o,C.byref(l),C.byref(c))
            if not roles & ((1<<2)|(1<<5)): return True  # reference or call
            cont=[]
            def rel(ctx,r):
                if lib.indexstore_symbol_relation_get_roles(r) & CONTAINED:
                    cont.append(s(lib.indexstore_symbol_get_name(lib.indexstore_symbol_relation_get_symbol(r))))
                return True
            lib.indexstore_occurrence_relations_apply_f(o,None,REL(rel))
            print(f"  {l.value}:{c.value} {s(lib.indexstore_symbol_get_name(sym))} [{s(lib.indexstore_symbol_get_usr(sym))}] in {cont}")
            return True
        lib.indexstore_record_reader_occurrences_apply_f(rd,None,OCC(occ))
