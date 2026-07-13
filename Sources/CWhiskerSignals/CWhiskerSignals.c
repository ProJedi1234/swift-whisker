#include "CWhiskerSignals.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>

static const int handled_signals[] = {SIGINT, SIGTERM, SIGHUP, SIGTSTP};
static const size_t handled_signal_count = sizeof(handled_signals) / sizeof(handled_signals[0]);

static int pipe_fds[2] = {-1, -1};
static struct sigaction previous_actions[4];
static sigset_t previous_signal_mask;
static volatile sig_atomic_t pending_signals[4];
static int installed = 0;

static int signal_index(int signal_number) {
    for (size_t index = 0; index < handled_signal_count; index++) {
        if (handled_signals[index] == signal_number) {
            return (int)index;
        }
    }
    return -1;
}

static void whisker_signal_handler(int signal_number) {
    int saved_errno = errno;
    int index = signal_index(signal_number);
    if (index >= 0) {
        pending_signals[index] = 1;
    }

    if (pipe_fds[1] >= 0) {
        uint8_t wake = 1;
        (void)write(pipe_fds[1], &wake, sizeof(wake));
    }
    errno = saved_errno;
}

static int configure_pipe_fd(int fd) {
    int flags = fcntl(fd, F_GETFL);
    if (flags == -1 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) == -1) {
        return errno;
    }

    int descriptor_flags = fcntl(fd, F_GETFD);
    if (descriptor_flags == -1 || fcntl(fd, F_SETFD, descriptor_flags | FD_CLOEXEC) == -1) {
        return errno;
    }
    return 0;
}

static int install_handler(int signal_number) {
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = whisker_signal_handler;
    sigemptyset(&action.sa_mask);
    action.sa_flags = 0;
    if (sigaction(signal_number, &action, NULL) == -1) {
        return errno;
    }
    return 0;
}

int whisker_signals_install(int *read_fd) {
    if (installed || read_fd == NULL) {
        return EBUSY;
    }

    if (pipe(pipe_fds) == -1) {
        return errno;
    }

    int result = configure_pipe_fd(pipe_fds[0]);
    if (result == 0) {
        result = configure_pipe_fd(pipe_fds[1]);
    }
    if (result != 0) {
        close(pipe_fds[0]);
        close(pipe_fds[1]);
        pipe_fds[0] = -1;
        pipe_fds[1] = -1;
        return result;
    }

    sigset_t handled_set;
    sigemptyset(&handled_set);
    for (size_t index = 0; index < handled_signal_count; index++) {
        sigaddset(&handled_set, handled_signals[index]);
    }
    if (sigprocmask(SIG_UNBLOCK, &handled_set, &previous_signal_mask) == -1) {
        result = errno;
        close(pipe_fds[0]);
        close(pipe_fds[1]);
        pipe_fds[0] = -1;
        pipe_fds[1] = -1;
        return result;
    }

    for (size_t index = 0; index < handled_signal_count; index++) {
        pending_signals[index] = 0;
    }

    size_t installed_count = 0;
    for (size_t index = 0; index < handled_signal_count; index++) {
        if (sigaction(handled_signals[index], NULL, &previous_actions[index]) == -1) {
            result = errno;
            break;
        }
        result = install_handler(handled_signals[index]);
        if (result != 0) {
            break;
        }
        installed_count++;
    }

    if (result != 0) {
        for (size_t index = 0; index < installed_count; index++) {
            (void)sigaction(handled_signals[index], &previous_actions[index], NULL);
        }
        close(pipe_fds[0]);
        close(pipe_fds[1]);
        pipe_fds[0] = -1;
        pipe_fds[1] = -1;
        (void)sigprocmask(SIG_SETMASK, &previous_signal_mask, NULL);
        return result;
    }

    installed = 1;
    *read_fd = pipe_fds[0];
    return 0;
}

int whisker_signals_uninstall(void) {
    if (!installed) {
        return 0;
    }

    int first_error = 0;
    for (size_t index = 0; index < handled_signal_count; index++) {
        if (sigaction(handled_signals[index], &previous_actions[index], NULL) == -1 && first_error == 0) {
            first_error = errno;
        }
    }
    if (sigprocmask(SIG_SETMASK, &previous_signal_mask, NULL) == -1 && first_error == 0) {
        first_error = errno;
    }

    installed = 0;
    int read_fd = pipe_fds[0];
    int write_fd = pipe_fds[1];
    pipe_fds[0] = -1;
    pipe_fds[1] = -1;
    if (read_fd >= 0 && close(read_fd) == -1 && first_error == 0) {
        first_error = errno;
    }
    if (write_fd >= 0 && close(write_fd) == -1 && first_error == 0) {
        first_error = errno;
    }
    return first_error;
}

int whisker_signals_drain(int *signals, size_t capacity, size_t *count) {
    if (!installed || signals == NULL || count == NULL) {
        return EINVAL;
    }

    uint8_t buffer[64];
    while (read(pipe_fds[0], buffer, sizeof(buffer)) > 0) {}
    if (errno != EAGAIN && errno != EWOULDBLOCK) {
        return errno;
    }

    sigset_t block_set;
    sigset_t previous_set;
    sigemptyset(&block_set);
    for (size_t index = 0; index < handled_signal_count; index++) {
        sigaddset(&block_set, handled_signals[index]);
    }
    if (sigprocmask(SIG_BLOCK, &block_set, &previous_set) == -1) {
        return errno;
    }

    size_t written = 0;
    for (size_t index = 0; index < handled_signal_count; index++) {
        if (pending_signals[index]) {
            pending_signals[index] = 0;
            if (written < capacity) {
                signals[written++] = handled_signals[index];
            }
        }
    }

    int result = 0;
    if (sigprocmask(SIG_SETMASK, &previous_set, NULL) == -1) {
        result = errno;
    }
    *count = written;
    return result;
}

int whisker_signals_use_default(int signal_number) {
    if (signal_index(signal_number) < 0) {
        return EINVAL;
    }
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = SIG_DFL;
    sigemptyset(&action.sa_mask);
    if (sigaction(signal_number, &action, NULL) == -1) {
        return errno;
    }
    return 0;
}

int whisker_signals_rearm(int signal_number) {
    if (!installed || signal_index(signal_number) < 0) {
        return EINVAL;
    }
    return install_handler(signal_number);
}

void whisker_signals_reraise(int signal_number) {
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = SIG_DFL;
    sigemptyset(&action.sa_mask);
    (void)sigaction(signal_number, &action, NULL);

    sigset_t unblocked;
    sigemptyset(&unblocked);
    sigaddset(&unblocked, signal_number);
    (void)sigprocmask(SIG_UNBLOCK, &unblocked, NULL);

    (void)kill(getpid(), signal_number);
    _exit(128 + signal_number);
}
