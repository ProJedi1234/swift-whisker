#ifndef C_WHISKER_SIGNALS_H
#define C_WHISKER_SIGNALS_H

#include <stddef.h>

/// Installs Whisker's signal handlers and returns the self-pipe's read descriptor.
/// Returns zero on success or an errno value on failure.
int whisker_signals_install(int *read_fd);

/// Restores the dispositions that were active before installation and closes the pipe.
int whisker_signals_uninstall(void);

/// Drains pending signals into `signals`, returning an errno value on failure.
int whisker_signals_drain(int *signals, size_t capacity, size_t *count);

/// Temporarily restores the default disposition for a handled signal.
int whisker_signals_use_default(int signal_number);

/// Reinstalls Whisker's handler after a temporarily defaulted signal resumes.
int whisker_signals_rearm(int signal_number);

/// Resets, unblocks, and re-raises a terminating signal. This function does not return.
void whisker_signals_reraise(int signal_number) __attribute__((noreturn));

#endif
