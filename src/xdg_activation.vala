using SwayNotificationCenter;

public class XdgActivationHelper : Object {
    public string ?get_token (Gtk.Widget widget) {
        try {
            // GDK includes the seat's last input serial. A surface-only token
            // is urgency-only in Niri and cannot focus the originating app.
            GLib.AppInfo info = GLib.AppInfo.create_from_commandline (
                "swaync", "SwayNotificationCenter",
                GLib.AppInfoCreateFlags.SUPPORTS_STARTUP_NOTIFICATION);
            Gdk.AppLaunchContext context = widget.get_display ().get_app_launch_context ();
            return context.get_startup_notify_id (info, null);
        } catch (GLib.Error error) {
            warning ("Could not obtain notification activation token: %s", error.message);
            return null;
        }
    }
}
