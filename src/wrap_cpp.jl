module wrap_cpp

using Clang.cindex

export @vcall, @scall, @mcall

function method_vt_index(cursor::cindex.CXCursor)
  ccall( ("wci_getCXXMethodVTableIndex", :libwrapclang), Int32, (Ptr{Uint8},), cursor.data)
end

function method_mangled_name(cursor::cindex.CXCursor)
  bufr = zeros(Uint8, 1024)
  ccall( ("wci_getCXXMethodMangledName", :libwrapclang), Int32, (Ptr{Uint8},Ptr{Uint8}), cursor.data, bufr)
  bytestring(convert(Ptr{Uint8},bufr))
end

# Get function pointer from vtable at given offset
vtblfunc(p::Ptr{Void}, offset) = pointer(Void, unsafe_ref(pointer(Uint64, unsafe_ref(pointer(Uint64,p))))+offset )

#derefptr(p::Ptr{Void}, offset) = convert( Ptr{Void}, pointer_to_array(convert(Ptr{Uint64}, p+offset), (1,) )[1] )
derefptr(thisptr, vtidx) = pointer(Void, unsafe_ref(pointer(Uint64, unsafe_ref(pointer(Uint64,thisptr)))+vtidx*8) )

# Static method call
macro scall(ret_type, func, arg_types, sym, lib)
  local _args_in = Any[ symbol(string('a',x)) for x in 1:length(arg_types.args) ]
  hdl = dlopen(string(lib))
  fptr = dlsym_e(hdl, sym)
  if (fptr==C_NULL) return end
  quote
    function $(esc(func))($(_args_in...))
      ccall( $(esc(fptr)), $ret_type, $arg_types, $(_args_in...) )
    end
  end
end

# Member function call (takes this* but is not virtual)
macro mcall(ret_type, func, arg_types, sym, lib)
  local _args_in = Any[ symbol(string('a',x)) for x in 1:length(arg_types.args) ]
  larg_types = :((Ptr{Void}, $(arg_types.args...)))
  hdl = dlopen(string(lib))
  fptr = dlsym_e(hdl,sym)
  quote
    function $(esc(func))(thisptr, $(_args_in...))
      ccall( $(fptr), thiscall, $(esc(ret_type)), $(larg_types), thisptr, $(_args_in...) )
    end
  end
end

# Virtual table call
macro vcall(vtidx, ret_type, func, arg_types)
  local _args_in = Any[ symbol(string('a',x)) for x in 1:length(arg_types.args) ]
  larg_types = :((Ptr{Void}, $(arg_types.args...)))
  quote
    function $(esc(func))(thisptr, $(_args_in...))
      local fptr = derefptr(thisptr, $(vtidx) )
      println("fptr: ", fptr, "\n")
      ccall( fptr, thiscall, $(esc(ret_type)), $(larg_types), thisptr, $(_args_in...) )
    end
  end
end

function find_sym(name,liblist)
  libs = {dlopen(l)=>l for l in liblist}
  found = false
  dl = C_NULL
  for dl in keys(libs)
    try
      dlsym_e(dl, name)
    catch
      continue
    end
    found = true
  end
  if found
    println("symbol $name found in ", libs[dl])
    return splitdir(libs[dl])[end]
  else
    return None
    println("NOT FOUND")
  end
end

end # module wrap_cpp