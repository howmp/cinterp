#ifndef CINTERP_CALLBACKS_H
#define CINTERP_CALLBACKS_H
typedef void (*ci_callback_fn)(void);
ci_callback_fn __ci_callback_acquire(ci_callback_fn fn);
int __ci_callback_release(ci_callback_fn fn);
#define ci_callback_acquire(fn) ((__typeof__(fn))__ci_callback_acquire((ci_callback_fn)(fn)))
#define ci_callback_release(fn) __ci_callback_release((ci_callback_fn)(fn))
#endif
