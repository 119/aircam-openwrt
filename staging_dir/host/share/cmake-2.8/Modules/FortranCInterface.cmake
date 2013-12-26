# - Fortran/C Interface Detection
# This module automatically detects the API by which C and Fortran
# languages interact.  Variables indicate if the mangling is found:
#   FortranCInterface_GLOBAL_FOUND = Global subroutines and functions
#   FortranCInterface_MODULE_FOUND = Module subroutines and functions
#                                    (declared by "MODULE PROCEDURE")
# A function is provided to generate a C header file containing macros
# to mangle symbol names:
#   FortranCInterface_HEADER(<file>
#                            [MACRO_NAMESPACE <macro-ns>]
#                            [SYMBOL_NAMESPACE <ns>]
#                            [SYMBOLS [<module>:]<function> ...])
# It generates in <file> definitions of the following macros:
#   #define FortranCInterface_GLOBAL (name,NAME) ...
#   #define FortranCInterface_GLOBAL_(name,NAME) ...
#   #define FortranCInterface_MODULE (mod,name, MOD,NAME) ...
#   #define FortranCInterface_MODULE_(mod,name, MOD,NAME) ...
# These macros mangle four categories of Fortran symbols,
# respectively:
#   - Global symbols without '_': call mysub()
#   - Global symbols with '_'   : call my_sub()
#   - Module symbols without '_': use mymod; call mysub()
#   - Module symbols with '_'   : use mymod; call my_sub()
# If mangling for a category is not known, its macro is left undefined.
# All macros require raw names in both lower case and upper case.
# The MACRO_NAMESPACE option replaces the default "FortranCInterface_"
# prefix with a given namespace "<macro-ns>".
#
# The SYMBOLS option lists symbols to mangle automatically with C
# preprocessor definitions:
#   <function>          ==> #define <ns><function> ...
#   <module>:<function> ==> #define <ns><module>_<function> ...
# If the mangling for some symbol is not known then no preprocessor
# definition is created, and a warning is displayed.
# The SYMBOL_NAMESPACE option prefixes all preprocessor definitions
# generated by the SYMBOLS option with a given namespace "<ns>".
#
# Example usage:
#   include(FortranCInterface)
#   FortranCInterface_HEADER(FC.h MACRO_NAMESPACE "FC_")
# This creates a "FC.h" header that defines mangling macros
# FC_GLOBAL(), FC_GLOBAL_(), FC_MODULE(), and FC_MODULE_().
#
# Example usage:
#   include(FortranCInterface)
#   FortranCInterface_HEADER(FCMangle.h
#                            MACRO_NAMESPACE "FC_"
#                            SYMBOL_NAMESPACE "FC_"
#                            SYMBOLS mysub mymod:my_sub)
# This creates a "FCMangle.h" header that defines the same FC_*()
# mangling macros as the previous example plus preprocessor symbols
# FC_mysub and FC_mymod_my_sub.
#
# Another function is provided to verify that the Fortran and C/C++
# compilers work together:
#   FortranCInterface_VERIFY([CXX] [QUIET])
# It tests whether a simple test executable using Fortran and C (and
# C++ when the CXX option is given) compiles and links successfully.
# The result is stored in the cache entry FortranCInterface_VERIFIED_C
# (or FortranCInterface_VERIFIED_CXX if CXX is given) as a boolean.
# If the check fails and QUIET is not given the function terminates
# with a FATAL_ERROR message describing the problem.  The purpose of
# this check is to stop a build early for incompatible compiler
# combinations.
#
# FortranCInterface is aware of possible GLOBAL and MODULE manglings
# for many Fortran compilers, but it also provides an interface to
# specify new possible manglings.  Set the variables
#   FortranCInterface_GLOBAL_SYMBOLS
#   FortranCInterface_MODULE_SYMBOLS
# before including FortranCInterface to specify manglings of the
# symbols "MySub", "My_Sub", "MyModule:MySub", and "My_Module:My_Sub".
# For example, the code:
#   set(FortranCInterface_GLOBAL_SYMBOLS mysub_ my_sub__ MYSUB_)
#     #                                  ^^^^^  ^^^^^^   ^^^^^
#   set(FortranCInterface_MODULE_SYMBOLS
#       __mymodule_MOD_mysub __my_module_MOD_my_sub)
#     #   ^^^^^^^^     ^^^^^   ^^^^^^^^^     ^^^^^^
#   include(FortranCInterface)
# tells FortranCInterface to try given GLOBAL and MODULE manglings.
# (The carets point at raw symbol names for clarity in this example
# but are not needed.)

#=============================================================================
# Copyright 2008-2009 Kitware, Inc.
#
# Distributed under the OSI-approved BSD License (the "License");
# see accompanying file Copyright.txt for details.
#
# This software is distributed WITHOUT ANY WARRANTY; without even the
# implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the License for more information.
#=============================================================================
# (To distribute this file outside of CMake, substitute the full
#  License text for the above reference.)

#-----------------------------------------------------------------------------
# Execute at most once in a project.
if(FortranCInterface_SOURCE_DIR)
  return()
endif()

# Use CMake 2.8.0 behavior for this module regardless of including context.
cmake_policy(PUSH)
cmake_policy(VERSION 2.8.0)

#-----------------------------------------------------------------------------
# Verify that C and Fortran are available.
foreach(lang C Fortran)
  if(NOT CMAKE_${lang}_COMPILER_LOADED)
    message(FATAL_ERROR
      "FortranCInterface requires the ${lang} language to be enabled.")
  endif()
endforeach()

#-----------------------------------------------------------------------------
set(FortranCInterface_SOURCE_DIR ${CMAKE_ROOT}/Modules/FortranCInterface)

# Create the interface detection project if it does not exist.
if(NOT FortranCInterface_BINARY_DIR)
  set(FortranCInterface_BINARY_DIR ${CMAKE_BINARY_DIR}/CMakeFiles/FortranCInterface)
  include(${FortranCInterface_SOURCE_DIR}/Detect.cmake)
endif()

# Load the detection results.
include(${FortranCInterface_BINARY_DIR}/Output.cmake)

#-----------------------------------------------------------------------------
function(FortranCInterface_HEADER file)
  # Parse arguments.
  if(IS_ABSOLUTE "${file}")
    set(FILE "${file}")
  else()
    set(FILE "${CMAKE_CURRENT_BINARY_DIR}/${file}")
  endif()
  set(MACRO_NAMESPACE "FortranCInterface_")
  set(SYMBOL_NAMESPACE)
  set(SYMBOLS)
  set(doing)
  foreach(arg ${ARGN})
    if("x${arg}" MATCHES "^x(SYMBOLS|SYMBOL_NAMESPACE|MACRO_NAMESPACE)$")
      set(doing "${arg}")
    elseif("x${doing}" MATCHES "^x(SYMBOLS)$")
      list(APPEND "${doing}" "${arg}")
    elseif("x${doing}" MATCHES "^x(SYMBOL_NAMESPACE|MACRO_NAMESPACE)$")
      set("${doing}" "${arg}")
      set(doing)
    else()
      message(AUTHOR_WARNING "Unknown argument: \"${arg}\"")
    endif()
  endforeach()

  # Generate macro definitions.
  set(HEADER_CONTENT)
  set(_desc_GLOBAL  "/* Mangling for Fortran global symbols without underscores. */")
  set(_desc_GLOBAL_ "/* Mangling for Fortran global symbols with underscores. */")
  set(_desc_MODULE  "/* Mangling for Fortran module symbols without underscores. */")
  set(_desc_MODULE_ "/* Mangling for Fortran module symbols with underscores. */")
  foreach(macro GLOBAL GLOBAL_ MODULE MODULE_)
    if(FortranCInterface_${macro}_MACRO)
      set(HEADER_CONTENT "${HEADER_CONTENT}
${_desc_${macro}}
#define ${MACRO_NAMESPACE}${macro}${FortranCInterface_${macro}_MACRO}
")
    endif()
  endforeach()

  # Generate symbol mangling definitions.
  if(SYMBOLS)
    set(HEADER_CONTENT "${HEADER_CONTENT}
/*--------------------------------------------------------------------------*/
/* Mangle some symbols automatically.                                       */
")
  endif()
  foreach(f ${SYMBOLS})
    if("${f}" MATCHES ":")
      # Module symbol name.  Parse "<module>:<function>" syntax.
      string(REPLACE ":" ";" pieces "${f}")
      list(GET pieces 0 module)
      list(GET pieces 1 function)
      string(TOUPPER "${module}" m_upper)
      string(TOLOWER "${module}" m_lower)
      string(TOUPPER "${function}" f_upper)
      string(TOLOWER "${function}" f_lower)
      if("${function}" MATCHES "_")
        set(form "_")
      else()
        set(form "")
      endif()
      if(FortranCInterface_MODULE${form}_MACRO)
        set(HEADER_CONTENT "${HEADER_CONTENT}#define ${SYMBOL_NAMESPACE}${module}_${function} ${MACRO_NAMESPACE}MODULE${form}(${m_lower},${f_lower}, ${m_upper},${f_upper})\n")
      else()
        message(AUTHOR_WARNING "No FortranCInterface mangling known for ${f}")
      endif()
    else()
      # Global symbol name.
      if("${f}" MATCHES "_")
        set(form "_")
      else()
        set(form "")
      endif()
      string(TOUPPER "${f}" f_upper)
      string(TOLOWER "${f}" f_lower)
      if(FortranCInterface_GLOBAL${form}_MACRO)
        set(HEADER_CONTENT "${HEADER_CONTENT}#define ${SYMBOL_NAMESPACE}${f} ${MACRO_NAMESPACE}GLOBAL${form}(${f_lower}, ${f_upper})\n")
      else()
        message(AUTHOR_WARNING "No FortranCInterface mangling known for ${f}")
      endif()
    endif()
  endforeach(f)

  # Store the content.
  configure_file(${FortranCInterface_SOURCE_DIR}/Macro.h.in ${FILE} @ONLY)
endfunction()

function(FortranCInterface_VERIFY)
  # Check arguments.

  set(lang C)
  set(quiet 0)
  set(verify_cxx 0)
  foreach(arg ${ARGN})
    if("${arg}" STREQUAL "QUIET")
      set(quiet 1)
    elseif("${arg}" STREQUAL "CXX")
      set(lang CXX)
      set(verify_cxx 1)
    else()
      message(FATAL_ERROR
        "FortranCInterface_VERIFY - called with unknown argument:\n  ${arg}")
    endif()
  endforeach()

  if(NOT CMAKE_${lang}_COMPILER_LOADED)
    message(FATAL_ERROR
      "FortranCInterface_VERIFY(${lang}) requires ${lang} to be enabled.")
  endif()

  # Build the verification project if not yet built.
  if(NOT DEFINED FortranCInterface_VERIFIED_${lang})
    set(_desc "Verifying Fortran/${lang} Compiler Compatibility")
    message(STATUS "${_desc}")

    # Build a sample project which reports symbols.
    try_compile(FortranCInterface_VERIFY_${lang}_COMPILED
      ${FortranCInterface_BINARY_DIR}/Verify${lang}
      ${FortranCInterface_SOURCE_DIR}/Verify
      VerifyFortranC
      CMAKE_FLAGS -DVERIFY_CXX=${verify_cxx}
                  -DCMAKE_VERBOSE_MAKEFILE=ON
                 "-DCMAKE_C_FLAGS:STRING=${CMAKE_C_FLAGS}"
                 "-DCMAKE_CXX_FLAGS:STRING=${CMAKE_CXX_FLAGS}"
                 "-DCMAKE_Fortran_FLAGS:STRING=${CMAKE_Fortran_FLAGS}"
      OUTPUT_VARIABLE _output)
    file(WRITE "${FortranCInterface_BINARY_DIR}/Verify${lang}/output.txt" "${_output}")

    # Report results.
    if(FortranCInterface_VERIFY_${lang}_COMPILED)
      message(STATUS "${_desc} - Success")
      file(APPEND ${CMAKE_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/CMakeOutput.log
        "${_desc} passed with the following output:\n${_output}\n\n")
      set(FortranCInterface_VERIFIED_${lang} 1 CACHE INTERNAL "Fortran/${lang} compatibility")
    else()
      message(STATUS "${_desc} - Failed")
      file(APPEND ${CMAKE_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/CMakeError.log
        "${_desc} failed with the following output:\n${_output}\n\n")
      set(FortranCInterface_VERIFIED_${lang} 0 CACHE INTERNAL "Fortran/${lang} compatibility")
    endif()
    unset(FortranCInterface_VERIFY_${lang}_COMPILED CACHE)
  endif()

  # Error if compilers are incompatible.
  if(NOT FortranCInterface_VERIFIED_${lang} AND NOT quiet)
    file(READ "${FortranCInterface_BINARY_DIR}/Verify${lang}/output.txt" _output)
    string(REGEX REPLACE "\n" "\n  " _output "${_output}")
    message(FATAL_ERROR
      "The Fortran compiler:\n  ${CMAKE_Fortran_COMPILER}\n"
      "and the ${lang} compiler:\n  ${CMAKE_${lang}_COMPILER}\n"
      "failed to compile a simple test project using both languages.  "
      "The output was:\n  ${_output}")
  endif()
endfunction()

# Restore including context policies.
cmake_policy(POP)