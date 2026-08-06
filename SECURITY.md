# Security and BattlEye boundary

War Thunder Triple Screen is intentionally an external Windows wrapper.

It uses only:

- the normal War Thunder `config.blk` display entries;
- the official launcher and normal BattlEye startup flow;
- documented top-level Windows display and window-management APIs.

It does not inject DLLs, hook DirectX, access game memory, patch executables,
alter gameplay, bypass BattlEye, install a driver/service, hide itself, or use
obfuscation.

No independent project can promise an anti-cheat outcome. Review the plain-text
source before use. Gaijin's current BattlEye troubleshooting guidance is linked
from the README.

To report a security concern, open a GitHub issue without including passwords,
tokens, personal data, or complete logs containing sensitive information.

