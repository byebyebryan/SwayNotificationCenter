#pragma once

#include <glib.h>

gboolean swaync_history_retention_boottime_now (gint64 *now_usec,
                                                gint *error_number);
gint swaync_history_retention_timer_new (gint *error_number);
gboolean swaync_history_retention_timer_arm (gint fd,
                                             gint64 deadline_usec,
                                             gint *error_number);
gboolean swaync_history_retention_timer_disarm (gint fd,
                                                gint *error_number);
gboolean swaync_history_retention_timer_read (gint fd,
                                              gboolean *consumed,
                                              gint *error_number);
void swaync_history_retention_timer_close (gint fd);
