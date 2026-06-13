#!/bin/bash
# Apply Dobby compilation fixes for NDK r27 + Clang 18
# Dobby master branch (commit 5dfc854) has several internal inconsistencies

set -e
DOBBY_DIR="${1:-Dobby}"
cd "$DOBBY_DIR"

echo "[*] Applying patches to Dobby in: $DOBBY_DIR"

python3 << 'PYTHON_SCRIPT'
import os

# Fix 1: os_arch_features.h - circular include + OSMemory usage
path = 'common/os_arch_features.h'
with open(path, 'r') as f:
    content = f.read()

content = content.replace(
    '#include "PlatformUnifiedInterface/platform.h"\n',
    '#include <sys/mman.h>\n#include <unistd.h>\n'
)

content = content.replace(
    '  auto page = (void *)ALIGN_FLOOR(address, OSMemory::PageSize());\n  if (!OSMemory::SetPermission(page, OSMemory::PageSize(), kReadExecute)) {\n    return;\n  }',
    '  long page_size = sysconf(_SC_PAGESIZE);\n  auto page = (void *)ALIGN_FLOOR(address, page_size);\n  mprotect(page, page_size, PROT_READ | PROT_EXEC);'
)

with open(path, 'w') as f:
    f.write(content)
print('[+] Patched common/os_arch_features.h')

# Fix 2: closure_bridge_arm64.asm - replace ADRP/PAGE with LDR
path = 'source/TrampolineBridge/ClosureTrampolineBridge/arm64/closure_bridge_arm64.asm'
with open(path, 'r') as f:
    content = f.read()

content = content.replace(
    'adrp TMP_REG_0, cdecl(common_closure_bridge_handler)@PAGE\nadd TMP_REG_0, TMP_REG_0, cdecl(common_closure_bridge_handler)@PAGEOFF',
    'ldr TMP_REG_0, common_closure_bridge_handler_addr'
)

with open(path, 'w') as f:
    f.write(content)
print('[+] Patched closure_bridge_arm64.asm')

# Fix 3: Linux ProcessRuntime.cc - load_address -> base, start -> start()
path = 'source/Backend/UserMode/PlatformUtil/Linux/ProcessRuntime.cc'
with open(path, 'r') as f:
    content = f.read()

content = content.replace('module.load_address', 'module.base')
content = content.replace('a.start < b.start', 'a.start() < b.start()')

with open(path, 'w') as f:
    f.write(content)
print('[+] Patched Linux ProcessRuntime.cc')

# Fix 4: dobby_symbol_resolver.cc - load_address -> base
path = 'builtin-plugin/SymbolResolver/elf/dobby_symbol_resolver.cc'
with open(path, 'r') as f:
    content = f.read()

content = content.replace('module.load_address', 'module.base')

with open(path, 'w') as f:
    f.write(content)
print('[+] Patched dobby_symbol_resolver.cc')

# Fix 5: Create missing Cpu.h stub (was renamed to CpuRegister.h)
cpu_h_path = 'source/core/arch/Cpu.h'
if not os.path.exists(cpu_h_path):
    with open(cpu_h_path, 'w') as f:
        f.write('#pragma once\n')
        f.write('#include "core/arch/CpuRegister.h"\n')
    print('[+] Created missing Cpu.h stub')

# Fix 6: ProcessRuntime.cc and dobby_symbol_resolver.cc need inttypes.h for PRIxPTR
for p in ['source/Backend/UserMode/PlatformUtil/Linux/ProcessRuntime.cc']:
    with open(p, 'r') as f:
        content = f.read()
    if '#include <inttypes.h>' not in content and '#include <cinttypes>' not in content:
        # Add after the existing includes
        content = content.replace(
            '#include <sys/mman.h>',
            '#include <sys/mman.h>\n#include <inttypes.h>'
        )
        with open(p, 'w') as f:
            f.write(content)
        print(f'[+] Added inttypes.h include to {p}')

# Fix 7: code-patch-tool-posix.cc - needs ALIGN_FLOOR macro
path = 'source/Backend/UserMode/ExecMemory/code-patch-tool-posix.cc'
with open(path, 'r') as f:
    content = f.read()
if '#include "common/linear_allocator.h"' not in content:
    content = content.replace(
        '#include <string.h>',
        '#include <string.h>\n#include "common/linear_allocator.h"'
    )
    with open(path, 'w') as f:
        f.write(content)
    print('[+] Added linear_allocator.h include to code-patch-tool-posix.cc')

print()
print("[*] All patches applied successfully")
PYTHON_SCRIPT
