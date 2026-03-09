// tray_linux.c — Linux system tray (AppIndicator3) for TeSmart UI
//
// Uses libayatana-appindicator3 (or libappindicator3) + GTK 3.
// Menu IDs:  1–16 = switch port,  100 = buzzer,  200 = show window,  201 = quit

#include <gtk/gtk.h>
#include <libayatana-appindicator/app-indicator.h>
#include <string.h>

typedef void (*tray_callback_fn)(int menu_id);

static tray_callback_fn g_callback = NULL;
static AppIndicator    *g_indicator = NULL;
static GtkWidget       *g_menu = NULL;
static int              g_gtk_inited = 0;

// GTK menu item activation handler
static void on_menu_activate(GtkMenuItem *item, gpointer user_data) {
    int menu_id = (int)(intptr_t)user_data;
    if (g_callback) g_callback(menu_id);
}

static GtkWidget *build_menu(int active_port, int buzzer_on,
                              const char *const names[16],
                              const int visible[16]) {
    GtkWidget *menu = gtk_menu_new();

    for (int i = 1; i <= 16; i++) {
        if (!visible[i - 1]) continue;
        const char *name = names[i - 1];
        char label[128];
        if (name && name[0] != '\0' && !(name[0] == '?' && name[1] == '\0')) {
            snprintf(label, sizeof(label), "%d: %s", i, name);
        } else {
            snprintf(label, sizeof(label), "Port %d", i);
        }

        GtkWidget *item;
        if (i == active_port) {
            // Use a check menu item to show the active port
            item = gtk_check_menu_item_new_with_label(label);
            gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(item), TRUE);
        } else {
            item = gtk_menu_item_new_with_label(label);
        }
        g_signal_connect(item, "activate",
                         G_CALLBACK(on_menu_activate),
                         (gpointer)(intptr_t)i);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), item);
    }

    // Separator
    gtk_menu_shell_append(GTK_MENU_SHELL(menu),
                          gtk_separator_menu_item_new());

    // Buzzer toggle
    {
        GtkWidget *bz = gtk_check_menu_item_new_with_label("Buzzer");
        gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(bz), buzzer_on);
        g_signal_connect(bz, "activate",
                         G_CALLBACK(on_menu_activate),
                         (gpointer)(intptr_t)100);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), bz);
    }

    // Separator
    gtk_menu_shell_append(GTK_MENU_SHELL(menu),
                          gtk_separator_menu_item_new());

    // Show Window
    {
        GtkWidget *show = gtk_menu_item_new_with_label("Show Window");
        g_signal_connect(show, "activate",
                         G_CALLBACK(on_menu_activate),
                         (gpointer)(intptr_t)200);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), show);
    }

    // Quit
    {
        GtkWidget *quit = gtk_menu_item_new_with_label("Quit");
        g_signal_connect(quit, "activate",
                         G_CALLBACK(on_menu_activate),
                         (gpointer)(intptr_t)201);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), quit);
    }

    gtk_widget_show_all(menu);
    return menu;
}

void tray_init(tray_callback_fn callback, int active_port, int buzzer_on,
               const char *const names[16], const int visible[16]) {
    g_callback = callback;

    if (!g_gtk_inited) {
        gtk_init(NULL, NULL);
        g_gtk_inited = 1;
    }

    g_indicator = app_indicator_new(
        "tesmart-ui",
        "preferences-desktop-keyboard",  // widely available in most icon themes
        APP_INDICATOR_CATEGORY_HARDWARE);

    app_indicator_set_status(g_indicator, APP_INDICATOR_STATUS_ACTIVE);
    // Try multiple icon names for compatibility (KDE, GNOME, etc.)
    // preferences-desktop-keyboard is in breeze, adwaita, hicolor
    app_indicator_set_icon(g_indicator, "preferences-desktop-keyboard");
    app_indicator_set_label(g_indicator, "KVM", "KVM");

    g_menu = build_menu(active_port, buzzer_on, names, visible);
    app_indicator_set_menu(g_indicator, GTK_MENU(g_menu));
}

void tray_update(int active_port, int buzzer_on,
                 const char *const names[16], const int visible[16]) {
    if (!g_indicator) return;

    // Rebuild menu — app_indicator_set_menu takes a ref on the new menu
    // and unrefs the old one, so we don't destroy g_menu ourselves.
    g_menu = build_menu(active_port, buzzer_on, names, visible);
    app_indicator_set_menu(g_indicator, GTK_MENU(g_menu));

    while (gtk_events_pending()) gtk_main_iteration_do(FALSE);
}

// Must be called every frame to keep the tray responsive
void tray_poll_events(void) {
    if (!g_gtk_inited) return;
    while (gtk_events_pending()) gtk_main_iteration_do(FALSE);
}

void tray_cleanup(void) {
    if (g_indicator) {
        g_object_unref(g_indicator);
        g_indicator = NULL;
    }
    // g_menu is owned by the indicator — don't destroy it separately
    g_menu = NULL;
    g_callback = NULL;
}
