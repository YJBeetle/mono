/* Small native host for the existing Wine Mono DLLs. No managed runtime fallback. */
#include <windows.h>
#include <stdio.h>

typedef void (__cdecl *set_dirs_fn)(const char *, const char *);
typedef void (__cdecl *config_parse_fn)(const char *);
typedef int (__cdecl *main_fn)(int, char **);

int main(int argc, char **argv)
{
    char dll[MAX_PATH], assemblies[MAX_PATH], config[MAX_PATH];
    HMODULE runtime;
    set_dirs_fn set_dirs;
    config_parse_fn config_parse;
    main_fn mono_main;
    if (argc < 3) {
        fprintf(stderr, "Usage: mono-host.exe <runtime-root> <managed-exe> [arguments]\n");
        return 1;
    }
#ifdef _WIN64
    const char *engine = "libmono-2.0-x86_64.dll";
#else
    const char *engine = "libmono-2.0-x86.dll";
#endif
    if (snprintf(dll, sizeof(dll), "%s\\bin\\%s", argv[1], engine) >= sizeof(dll) ||
        snprintf(assemblies, sizeof(assemblies), "%s\\lib", argv[1]) >= sizeof(assemblies) ||
        snprintf(config, sizeof(config), "%s\\etc", argv[1]) >= sizeof(config)) {
        fprintf(stderr, "Runtime path exceeds MAX_PATH\n");
        return 1;
    }
    runtime = LoadLibraryA(dll);
    if (!runtime) {
        fprintf(stderr, "LoadLibrary(%s) failed: %lu\n", dll, GetLastError());
        return 1;
    }
    set_dirs = (set_dirs_fn)GetProcAddress(runtime, "mono_set_dirs");
    config_parse = (config_parse_fn)GetProcAddress(runtime, "mono_config_parse");
    mono_main = (main_fn)GetProcAddress(runtime, "mono_main");
    if (!set_dirs || !config_parse || !mono_main) {
        fprintf(stderr, "Required Mono embedding entry point missing\n");
        return 1;
    }
    printf("Mono engine: %s\n", dll);
    fflush(stdout);
    set_dirs(assemblies, config);
    config_parse(NULL);
    argv[1] = argv[0];
    return mono_main(argc - 1, argv + 1);
}
