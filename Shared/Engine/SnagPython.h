// A tiny C interface to the embedded CPython used on iOS. Kept free of
// Python types so it can be the Swift bridging header on every platform.

#ifndef SnagPython_h
#define SnagPython_h

#include <stddef.h>

/// Starts the interpreter once. `home` is the bundled stdlib prefix,
/// `executable` the app's binary (compiled modules are found next to it, which
/// matters in the share extension) and `paths` the module search path.
/// Returns 0 on success, otherwise writes a message to `error`.
int snag_python_start(const char *home, const char *executable, const char *const *paths, int path_count, char *error, size_t error_size);

/// Calls `snag_bridge.extract_json(url, cookies)`. `cookies` may be NULL.
/// Returns a malloc'd UTF-8 string the caller must free: the bridge's JSON,
/// or, if `failed` is set to 1, a Python error message.
char *snag_python_extract(const char *url, const char *cookies, int *failed);

#endif
