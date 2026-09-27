// -----------------------------------------------------------------------------
// UVM DPI support for Verilator
//
// Compiles the simulator-independent parts of the Accellera UVM DPI library
// (command-line access for +UVM_TESTNAME / +UVM_VERBOSITY / ..., and regular
// expressions for config_db / factory lookups). The HDL backdoor (uvm_hdl_*)
// has no Verilator backend in UVM 2020.3.1, so the SV side is compiled with
// +define+UVM_HDL_NO_DPI and this file does not include uvm_hdl.c.
// Build with: -CFLAGS -I$(UVM_HOME)/src/dpi
// -----------------------------------------------------------------------------
#ifdef __cplusplus
extern "C" {
#endif

#include <stdlib.h>
#include "uvm_dpi.h"

void push_data(int lvl, char* entry, int cmd);
void walk_level(int lvl, int argc, char** argv, int cmd);
const char* uvm_dpi_get_next_arg_c(int init);
extern char* uvm_dpi_get_tool_name_c();
extern char* uvm_dpi_get_tool_version_c();
extern char* uvm_re_buffer();
extern const char* uvm_re_deglobbed(const char* glob, unsigned char with_brackets);
extern void uvm_re_free(regex_t* handle);
extern regex_t* uvm_re_comp(const char* re, unsigned char deglob);
extern int uvm_re_exec(regex_t* rexp, const char* str);
extern regex_t* uvm_re_compexec(const char* re, const char* str, unsigned char deglob, int* exec_ret);

#include "uvm_common.c"
#include "uvm_regex.cc"
#include "uvm_svcmd_dpi.c"

#ifdef __cplusplus
}
#endif
