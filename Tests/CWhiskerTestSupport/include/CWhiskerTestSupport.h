#ifndef C_WHISKER_TEST_SUPPORT_H
#define C_WHISKER_TEST_SUPPORT_H

#include <sys/types.h>

int whisker_test_spawn_pty(
    const char *executable,
    const char *mode,
    pid_t *pid,
    int *master_fd,
    int *slave_fd
);

int whisker_test_wait_for_stop(pid_t pid, int expected_signal);
int whisker_test_wait_for_signal_exit(pid_t pid, int expected_signal);

#endif
