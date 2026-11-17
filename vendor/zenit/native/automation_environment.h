#ifndef ZENIT_AUTOMATION_ENVIRONMENT_H
#define ZENIT_AUTOMATION_ENVIRONMENT_H
#include <stdlib.h>
/* Native diagnostic/test overrides read from the process environment.
 * Consumer App builds (attach/addNativeLibs and macosNativeFlags) always
 * define ZENIT_AUTOMATION_ENVIRONMENT explicitly from build.zig's
 * automationBuild(): formal Release Apps compile it to 0 and never accept
 * process overrides. Zenit's own probes and contract tools compile these
 * sources directly and keep the diagnostics when it is left undefined. */
#ifndef ZENIT_AUTOMATION_ENVIRONMENT
#define ZENIT_AUTOMATION_ENVIRONMENT 1
#endif
static inline const char *zenitAutomationEnvironment(const char *name) {
#if ZENIT_AUTOMATION_ENVIRONMENT
    return getenv(name);
#else
    (void)name;
    return NULL;
#endif
}
#ifdef _WIN32
/* Win32 forms of the boundary. Macros so this header needs no <windows.h>;
 * callers already include it before use. A disabled boundary reports an
 * unset variable (0), matching GetEnvironmentVariable's own contract. */
#define zenitAutomationEnvironmentA(name, buffer, size) \
    (ZENIT_AUTOMATION_ENVIRONMENT ? GetEnvironmentVariableA((name), (buffer), (size)) : 0)
#define zenitAutomationEnvironmentW(name, buffer, size) \
    (ZENIT_AUTOMATION_ENVIRONMENT ? GetEnvironmentVariableW((name), (buffer), (size)) : 0)
#endif
#endif
