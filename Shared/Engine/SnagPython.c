#include "SnagPython.h"
#include <TargetConditionals.h>

#if TARGET_OS_IOS
#include <Python/Python.h>
#include <stdio.h>
#include <string.h>

static int started = 0;

int snag_python_start(const char *home, const char *executable, const char *const *paths, int path_count, char *error, size_t error_size) {
    if (started) return 0;

    PyConfig config;
    PyConfig_InitIsolatedConfig(&config);
    config.install_signal_handlers = 0;
    config.write_bytecode = 0;   // the app bundle is read-only
    config.buffered_stdio = 0;

    PyStatus status = PyConfig_SetBytesString(&config, &config.home, home);
    if (PyStatus_Exception(status)) goto fail;
    // Extension modules live in the app's Frameworks folder, found relative
    // to sys.executable.
    status = PyConfig_SetBytesString(&config, &config.executable, executable);
    if (PyStatus_Exception(status)) goto fail;

    config.module_search_paths_set = 1;
    for (int i = 0; i < path_count; i++) {
        wchar_t *path = Py_DecodeLocale(paths[i], NULL);
        status = PyWideStringList_Append(&config.module_search_paths, path);
        PyMem_RawFree(path);
        if (PyStatus_Exception(status)) goto fail;
    }

    status = Py_InitializeFromConfig(&config);
    if (PyStatus_Exception(status)) goto fail;
    PyConfig_Clear(&config);

    // Release the GIL; each call takes it back with PyGILState_Ensure.
    PyEval_SaveThread();
    started = 1;
    return 0;

fail:
    snprintf(error, error_size, "%s", status.err_msg ? status.err_msg : "Python failed to start");
    PyConfig_Clear(&config);
    return -1;
}

static char *copy_exception(void) {
    PyObject *exception = PyErr_GetRaisedException();
    PyObject *text = exception ? PyObject_Str(exception) : NULL;
    const char *utf8 = text ? PyUnicode_AsUTF8(text) : NULL;
    char *result = strdup(utf8 ? utf8 : "Unknown Python error");
    Py_XDECREF(text);
    Py_XDECREF(exception);
    PyErr_Clear();
    return result;
}

char *snag_python_extract(const char *url, const char *cookies, int *failed) {
    PyGILState_STATE gil = PyGILState_Ensure();
    char *result = NULL;
    *failed = 0;

    PyObject *module = PyImport_ImportModule("snag_bridge");
    PyObject *function = module ? PyObject_GetAttrString(module, "extract_json") : NULL;
    PyObject *value = NULL;
    if (function) {
        value = cookies
            ? PyObject_CallFunction(function, "ss", url, cookies)
            : PyObject_CallFunction(function, "sO", url, Py_None);
    }
    const char *json = value ? PyUnicode_AsUTF8(value) : NULL;

    if (json) {
        result = strdup(json);
    } else {
        *failed = 1;
        result = copy_exception();
    }

    Py_XDECREF(value);
    Py_XDECREF(function);
    Py_XDECREF(module);
    PyGILState_Release(gil);
    return result;
}
#endif
