#include "CWhiskerTestSupport.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

#if defined(__APPLE__)
#include <util.h>
#else
#include <pty.h>
#endif

int whisker_test_spawn_pty(
    const char *executable,
    const char *mode,
    pid_t *pid,
    int *master_fd,
    int *slave_fd
) {
    if (openpty(master_fd, slave_fd, NULL, NULL, NULL) == -1) {
        return errno;
    }

    pid_t child = fork();
    if (child == -1) {
        int result = errno;
        close(*master_fd);
        close(*slave_fd);
        return result;
    }

    if (child == 0) {
        close(*master_fd);
        (void)setsid();
#ifdef TIOCSCTTY
        (void)ioctl(*slave_fd, TIOCSCTTY, 0);
#endif
        if (dup2(*slave_fd, STDIN_FILENO) == -1 ||
            dup2(*slave_fd, STDOUT_FILENO) == -1 ||
            dup2(*slave_fd, STDERR_FILENO) == -1) {
            _exit(126);
        }
        if (*slave_fd > STDERR_FILENO) {
            close(*slave_fd);
        }
        execl(executable, executable, mode, NULL);
        _exit(127);
    }

    *pid = child;
    int flags = fcntl(*master_fd, F_GETFL);
    if (flags == -1 || fcntl(*master_fd, F_SETFL, flags | O_NONBLOCK) == -1) {
        return errno;
    }
    return 0;
}

int whisker_test_wait_for_stop(pid_t pid, int expected_signal) {
    int status = 0;
    for (int attempt = 0; attempt < 500; attempt++) {
        pid_t result = waitpid(pid, &status, WUNTRACED | WNOHANG);
        if (result == pid) {
            return WIFSTOPPED(status) && WSTOPSIG(status) == expected_signal ? 0 : ECHILD;
        }
        if (result == -1) {
            return errno;
        }
        usleep(10000);
    }
    return ETIMEDOUT;
}

int whisker_test_wait_for_signal_exit(pid_t pid, int expected_signal) {
    int status = 0;
    for (int attempt = 0; attempt < 500; attempt++) {
        pid_t result = waitpid(pid, &status, WNOHANG);
        if (result == pid) {
            return WIFSIGNALED(status) && WTERMSIG(status) == expected_signal ? 0 : ECHILD;
        }
        if (result == -1) {
            return errno;
        }
        usleep(10000);
    }
    return ETIMEDOUT;
}
