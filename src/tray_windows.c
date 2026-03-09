// tray_windows.c — Windows system tray (Shell_NotifyIcon) for TeSmart UI
//
// Uses the Win32 notification area API.
// Menu IDs:  1–16 = switch port,  100 = buzzer,  200 = show window,  201 = quit

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <windows.h>
#include <shellapi.h>
#include <string.h>
#include <stdio.h>

typedef void (*tray_callback_fn)(int menu_id);

#define WM_TRAY_ICON    (WM_USER + 1)
#define IDI_TRAY        1

static tray_callback_fn g_callback = NULL;
static HWND             g_hwnd = NULL;
static NOTIFYICONDATAW  g_nid;
static HMENU            g_menu = NULL;
static HANDLE           g_thread = NULL;
static volatile int     g_running = 0;

// Current state for menu rebuild
static int              g_active_port = 0;
static int              g_buzzer_on = 0;
static char             g_names[16][65];
static int              g_visible[16] = {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1};

static void rebuild_menu(void) {
    if (g_menu) DestroyMenu(g_menu);
    g_menu = CreatePopupMenu();

    for (int i = 1; i <= 16; i++) {
        if (!g_visible[i - 1]) continue;
        wchar_t label[128];
        const char *name = g_names[i - 1];
        if (name[0] != '\0' && !(name[0] == '?' && name[1] == '\0')) {
            wchar_t wname[65];
            MultiByteToWideChar(CP_UTF8, 0, name, -1, wname, 65);
            swprintf(label, 128, L"%d: %s", i, wname);
        } else {
            swprintf(label, 128, L"Port %d", i);
        }

        UINT flags = MF_STRING;
        if (i == g_active_port) flags |= MF_CHECKED;
        AppendMenuW(g_menu, flags, (UINT_PTR)i, label);
    }

    AppendMenuW(g_menu, MF_SEPARATOR, 0, NULL);

    {
        UINT flags = MF_STRING;
        if (g_buzzer_on) flags |= MF_CHECKED;
        AppendMenuW(g_menu, flags, 100, L"Buzzer");
    }

    AppendMenuW(g_menu, MF_SEPARATOR, 0, NULL);
    AppendMenuW(g_menu, MF_STRING, 200, L"Show Window");
    AppendMenuW(g_menu, MF_STRING, 201, L"Quit");
}

static LRESULT CALLBACK tray_wndproc(HWND hwnd, UINT msg,
                                      WPARAM wParam, LPARAM lParam) {
    switch (msg) {
    case WM_TRAY_ICON:
        if (LOWORD(lParam) == WM_RBUTTONUP || LOWORD(lParam) == WM_LBUTTONUP) {
            POINT pt;
            GetCursorPos(&pt);
            SetForegroundWindow(hwnd);
            rebuild_menu();
            int cmd = (int)TrackPopupMenu(g_menu,
                TPM_RETURNCMD | TPM_NONOTIFY,
                pt.x, pt.y, 0, hwnd, NULL);
            PostMessage(hwnd, WM_NULL, 0, 0);
            if (cmd > 0 && g_callback) {
                g_callback(cmd);
            }
        }
        return 0;

    case WM_DESTROY:
        Shell_NotifyIconW(NIM_DELETE, &g_nid);
        PostQuitMessage(0);
        return 0;
    }

    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

static DWORD WINAPI tray_thread_proc(LPVOID param) {
    (void)param;

    // Register window class
    WNDCLASSW wc = {0};
    wc.lpfnWndProc = tray_wndproc;
    wc.hInstance = GetModuleHandle(NULL);
    wc.lpszClassName = L"TesmartTrayClass";
    RegisterClassW(&wc);

    // Create message-only window
    g_hwnd = CreateWindowExW(0, L"TesmartTrayClass", L"TesmartTray",
        0, 0, 0, 0, 0, HWND_MESSAGE, NULL, wc.hInstance, NULL);

    // Set up notification icon
    ZeroMemory(&g_nid, sizeof(g_nid));
    g_nid.cbSize = sizeof(g_nid);
    g_nid.hWnd = g_hwnd;
    g_nid.uID = IDI_TRAY;
    g_nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    g_nid.uCallbackMessage = WM_TRAY_ICON;
    g_nid.hIcon = LoadIcon(NULL, IDI_APPLICATION);
    wcscpy(g_nid.szTip, L"TeSmart KVM");

    Shell_NotifyIconW(NIM_ADD, &g_nid);

    // Message loop
    MSG msg;
    while (g_running && GetMessage(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }

    Shell_NotifyIconW(NIM_DELETE, &g_nid);
    DestroyWindow(g_hwnd);
    g_hwnd = NULL;
    return 0;
}

void tray_init(tray_callback_fn callback, int active_port, int buzzer_on,
               const char *const names[16], const int visible[16]) {
    g_callback = callback;
    g_active_port = active_port;
    g_buzzer_on = buzzer_on;

    for (int i = 0; i < 16; i++) {
        strncpy(g_names[i], names[i], 64);
        g_names[i][64] = '\0';
        g_visible[i] = visible[i];
    }

    g_running = 1;
    g_thread = CreateThread(NULL, 0, tray_thread_proc, NULL, 0, NULL);
}

void tray_update(int active_port, int buzzer_on,
                 const char *const names[16], const int visible[16]) {
    g_active_port = active_port;
    g_buzzer_on = buzzer_on;

    for (int i = 0; i < 16; i++) {
        strncpy(g_names[i], names[i], 64);
        g_names[i][64] = '\0';
        g_visible[i] = visible[i];
    }
    // Menu is rebuilt on-demand when user clicks the tray icon
}

void tray_cleanup(void) {
    g_running = 0;
    if (g_hwnd) {
        PostMessage(g_hwnd, WM_DESTROY, 0, 0);
    }
    if (g_thread) {
        WaitForSingleObject(g_thread, 2000);
        CloseHandle(g_thread);
        g_thread = NULL;
    }
    if (g_menu) {
        DestroyMenu(g_menu);
        g_menu = NULL;
    }
    g_callback = NULL;
}
