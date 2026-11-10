#ifndef CINTERP_CALLBACKS_H
#define CINTERP_CALLBACKS_H
typedef void (*ci_callback_fn)(void);
ci_callback_fn __ci_callback_acquire(ci_callback_fn fn);
int __ci_callback_release(ci_callback_fn fn);
#define ci_callback_acquire(fn) ((__typeof__(fn))__ci_callback_acquire((ci_callback_fn)(fn)))
#define ci_callback_release(fn) __ci_callback_release((ci_callback_fn)(fn))

/*
 * Declare a function-pointer signature as callable through a dynamically
 * resolved native address (for example dlsym).  Use at file scope with a
 * typedef name:
 *
 *   typedef void (*fn_t)(int);
 *   CI_NATIVE_PLAN(fn_t);
 *   fn_t f = (fn_t)dlsym(handle, "f");
 *   f(1);
 *
 * The declaration creates a CIPL plan with the native-call flag; ordinary
 * function-pointer calls then accept any non-null native target.  The VM is
 * intentionally not a sandbox: an invalid pointer may fault the host.
 */
#define CI_NATIVE_PLAN(T) \
    extern __typeof__(*(T)0) __ci_native_plan_##T; \
    static void *__ci_native_plan_ref_##T __attribute__((used)) = (void *)__ci_native_plan_##T
#endif
