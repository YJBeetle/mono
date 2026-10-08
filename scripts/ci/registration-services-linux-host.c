/* Build only this launcher; load the existing native Linux Mono engine. */
#include <mono/jit/jit.h>
#include <mono/metadata/mono-config.h>
#include <mono/metadata/assembly.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv)
{
    char libraries[4096], config[4096];
    int first = 2, result;
    MonoDomain *domain;
    MonoAssembly *assembly;
    if (argc < 3) return 1;
    if (snprintf(libraries, sizeof(libraries), "%s/lib", argv[1]) >= sizeof(libraries) ||
        snprintf(config, sizeof(config), "%s/etc", argv[1]) >= sizeof(config)) return 1;
    mono_set_dirs(libraries, config);
    mono_config_parse(NULL);
    if (!strcmp(argv[first], "--runtime=v4.0")) ++first;
    if (first >= argc) return 1;
    /* mono_main re-discovers Ubuntu's prefix from its shared library location.
       Initialize directly so mono_set_dirs remains authoritative for corlib. */
    domain = mono_jit_init_version(argv[first], "v4.0.30319");
    if (!domain) return 1;
    assembly = mono_domain_assembly_open(domain, argv[first]);
    if (!assembly) return 1;
    result = mono_jit_exec(domain, assembly, argc - first, argv + first);
    mono_jit_cleanup(domain);
    return result;
}
