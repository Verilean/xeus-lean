/*
 * mock_extra_hello.c — implementation of MockExtra.mockHello.
 *
 * Returns a fresh `lean_string_object` whose payload is the literal
 * "hello from mock-extra".  The Lean call convention for an
 * `@[extern "mock_extra_hello"] opaque mockHello : Unit -> String`
 * declaration is:
 *
 *   lean_object* mock_extra_hello(lean_object* unit);
 *
 * The argument is owned by the caller and must be `lean_dec`'d once
 * we're done with it.  The return value is owned by the caller.
 */
#include <lean/lean.h>

static const char kGreeting[] = "hello from mock-extra";

LEAN_EXPORT lean_object* mock_extra_hello(lean_object* unit_obj) {
    /* Release the unit argument: the Lean -> C extern ABI hands us
       ownership of every argument even when the value is uninteresting.
       Forgetting this leaks one reference per call. */
    lean_dec(unit_obj);
    return lean_mk_string(kGreeting);
}
