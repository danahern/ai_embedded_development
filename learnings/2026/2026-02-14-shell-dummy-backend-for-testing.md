---
title: Shell dummy backend for testing
date: 2026-02-14
author: danahern
tags: [testing, shell, zephyr]
---

`CONFIG_SHELL_BACKEND_DUMMY=y` works well for testing shell commands without hardware. Pattern:
```c
const struct shell *sh = shell_backend_dummy_get_ptr();
shell_execute_cmd(sh, "board info");
const char *output = shell_backend_dummy_get_output(sh, &size);
zassert_not_null(strstr(output, "Board:"), "expected Board: in output");
```
