/*
 * glibc C23 compatibility shim for leanc linking.
 *
 * When compiled with system clang++ against glibc >= 2.38, _GNU_SOURCE causes
 * strtoull/strtoll to redirect to __isoc23_strtoull/__isoc23_strtoll (C23
 * variants). But leanc's bundled older glibc lacks these symbols.
 *
 * This shim provides the missing symbols by forwarding to the regular versions
 * available in leanc's glibc. No headers needed - just forward declarations.
 */

/* Forward declarations matching libc signatures */
extern unsigned long long strtoull(const char *, char **, int);
extern long long strtoll(const char *, char **, int);
extern unsigned long strtoul(const char *, char **, int);
extern long strtol(const char *, char **, int);

unsigned long long __isoc23_strtoull(const char *nptr, char **endptr, int base) {
    return strtoull(nptr, endptr, base);
}

long long __isoc23_strtoll(const char *nptr, char **endptr, int base) {
    return strtoll(nptr, endptr, base);
}

unsigned long __isoc23_strtoul(const char *nptr, char **endptr, int base) {
    return strtoul(nptr, endptr, base);
}

long __isoc23_strtol(const char *nptr, char **endptr, int base) {
    return strtol(nptr, endptr, base);
}
