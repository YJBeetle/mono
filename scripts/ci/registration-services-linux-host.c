/* Build only this launcher; load the existing native Linux Mono engine. */
#include <mono/jit/jit.h>
#include <mono/metadata/mono-config.h>
#include <stdio.h>

int main(int argc, char **argv)
{
    char libraries[4096], config[4096];
    if (argc < 3) return 1;
    if (snprintf(libraries, sizeof(libraries), "%s/lib", argv[1]) >= sizeof(libraries) ||
        snprintf(config, sizeof(config), "%s/etc", argv[1]) >= sizeof(config)) return 1;
    mono_set_dirs(libraries, config);
    mono_config_parse(NULL);
    argv[1] = argv[0];
    return mono_main(argc - 1, argv + 1);
}
