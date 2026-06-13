#!/bin/bash
# Apply Dobby compilation fixes

set -e
DOBBY_DIR="${1:-Dobby}"

echo "[*] Applying patches to Dobby in: $DOBBY_DIR"

# Fix 1: os_arch_features.h - remove circular include
# platform.h includes common.h -> os_arch_features.h, but os_arch_features.h
# includes platform.h, creating a cycle. Replace OSMemory usage with direct APIs.
cd "$DOBBY_DIR"

# Remove the circular include
# The problematic lines in make_memory_readable:
#   auto page = (void *)ALIGN_FLOOR(address, OSMemory::PageSize());
#   if (!OSMemory::SetPermission(page, OSMemory::PageSize(), kReadExecute)) {
#     return;
#   }
# Replace with:
#   long page_size = sysconf(_SC_PAGESIZE);
#   auto page = (void *)ALIGN_FLOOR(address, page_size);
#   mprotect(page, page_size, PROT_READ | PROT_EXEC);

python3 -c "
import sys

with open('common/os_arch_features.h', 'r') as f:
    content = f.read()

# Remove circular include
content = content.replace('#include \"PlatformUnifiedInterface/platform.h\"\n', '#include <sys/mman.h>\n#include <unistd.h>\n')

# Fix the make_memory_readable function body
old_block = '''  auto page = (void *)ALIGN_FLOOR(address, OSMemory::PageSize());
  if (!OSMemory::SetPermission(page, OSMemory::PageSize(), kReadExecute)) {
    return;
  }'''

new_block = '''  long page_size = sysconf(_SC_PAGESIZE);
  auto page = (void *)ALIGN_FLOOR(address, page_size);
  mprotect(page, page_size, PROT_READ | PROT_EXEC);'''

content = content.replace(old_block, new_block)

with open('common/os_arch_features.h', 'w') as f:
    f.write(content)

print('[+] Patched common/os_arch_features.h')
"

# Fix 2: closure_bridge_arm64.asm - replace ADRP with LDR
# Clang 18 integrated assembler doesn't support @PAGE/@PAGEOFF relocations
# for external symbols. Load from the data section instead.

python3 -c "
with open('source/TrampolineBridge/ClosureTrampolineBridge/arm64/closure_bridge_arm64.asm', 'r') as f:
    content = f.read()

content = content.replace(
    'adrp TMP_REG_0, cdecl(common_closure_bridge_handler)@PAGE\nadd TMP_REG_0, TMP_REG_0, cdecl(common_closure_bridge_handler)@PAGEOFF',
    'ldr TMP_REG_0, common_closure_bridge_handler_addr'
)

with open('source/TrampolineBridge/ClosureTrampolineBridge/arm64/closure_bridge_arm64.asm', 'w') as f:
    f.write(content)

print('[+] Patched source/TrampolineBridge/ClosureTrampolineBridge/arm64/closure_bridge_arm64.asm')
"

echo "[*] Patches applied successfully"
