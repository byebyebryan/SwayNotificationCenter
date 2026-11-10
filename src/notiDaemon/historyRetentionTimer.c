#define _GNU_SOURCE

#include "historyRetentionTimer.h"

#include <errno.h>
#include <stdint.h>
#include <time.h>
#include <sys/timerfd.h>
#include <unistd.h>

gboolean swaync_history_retention_boottime_now (gint64 *now_usec,
                                                gint *error_number) {
    struct timespec now;

#ifdef CLOCK_BOOTTIME
    if (clock_gettime (CLOCK_BOOTTIME, &now) < 0) {
        *error_number = errno;
        return FALSE;
    }
#else
    *error_number = ENOSYS;
    return FALSE;
#endif

    if (now.tv_sec < 0
        || (guint64) now.tv_sec
            > ((guint64) G_MAXINT64 - (guint64) now.tv_nsec / 1000)
                / G_USEC_PER_SEC) {
        *error_number = EOVERFLOW;
        return FALSE;
    }

    *now_usec = (gint64) now.tv_sec * G_USEC_PER_SEC + now.tv_nsec / 1000;
    *error_number = 0;
    return TRUE;
}

gint swaync_history_retention_timer_new (gint *error_number) {
    gint fd = timerfd_create (CLOCK_BOOTTIME, TFD_CLOEXEC | TFD_NONBLOCK);

    if (fd < 0) {
        *error_number = errno;
        return -1;
    }

    *error_number = 0;
    return fd;
}

gboolean swaync_history_retention_timer_arm (gint fd,
                                             gint64 deadline_usec,
                                             gint *error_number) {
    struct itimerspec timer = { 0 };

    if (deadline_usec < 0) {
        *error_number = EINVAL;
        return FALSE;
    }

    timer.it_value.tv_sec = deadline_usec / G_USEC_PER_SEC;
    timer.it_value.tv_nsec = (deadline_usec % G_USEC_PER_SEC) * 1000;
    if (timer.it_value.tv_sec == 0 && timer.it_value.tv_nsec == 0) {
        timer.it_value.tv_nsec = 1;
    }

    if (timerfd_settime (fd, TFD_TIMER_ABSTIME, &timer, NULL) < 0) {
        *error_number = errno;
        return FALSE;
    }

    *error_number = 0;
    return TRUE;
}

gboolean swaync_history_retention_timer_disarm (gint fd,
                                                gint *error_number) {
    struct itimerspec timer = { 0 };

    if (timerfd_settime (fd, 0, &timer, NULL) < 0) {
        *error_number = errno;
        return FALSE;
    }

    *error_number = 0;
    return TRUE;
}

gboolean swaync_history_retention_timer_read (gint fd,
                                              gboolean *consumed,
                                              gint *error_number) {
    guint64 expirations;
    ssize_t result;

    do {
        result = read (fd, &expirations, sizeof (expirations));
    } while (result < 0 && errno == EINTR);

    if (result < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
        *consumed = FALSE;
        *error_number = 0;
        return TRUE;
    }

    if (result != sizeof (expirations)) {
        *error_number = result < 0 ? errno : EIO;
        return FALSE;
    }

    *consumed = TRUE;
    *error_number = 0;
    return TRUE;
}

void swaync_history_retention_timer_close (gint fd) {
    if (fd >= 0) {
        close (fd);
    }
}
