// tray_macos.m — macOS system tray (NSStatusItem) for TeSmart UI
#import <Cocoa/Cocoa.h>

typedef void (*tray_callback_fn)(int menu_id);

// Menu IDs:  1–16 = switch port,  100 = buzzer,  200 = show window,  201 = quit

static tray_callback_fn g_callback = NULL;
static NSStatusItem    *g_statusItem = nil;

static NSImage *loadTrayImage(const char *icon_path) {
    if (!icon_path || icon_path[0] == '\0') return nil;

    NSString *path = [NSString stringWithUTF8String:icon_path];
    NSImage *img = [[NSImage alloc] initWithContentsOfFile:path];
    if (!img) return nil;

    CGFloat side = [NSStatusBar systemStatusBar].thickness - 4.0;
    if (side < 16.0) side = 16.0;

    [img setSize:NSMakeSize(side, side)];
    [img setScalesWhenResized:YES];
    [img setTemplate:NO];
    return img;
}

@interface TrayDelegate : NSObject
- (void)menuItemClicked:(id)sender;
@end

@implementation TrayDelegate
- (void)menuItemClicked:(id)sender {
    if (g_callback) g_callback((int)[sender tag]);
}
@end

static TrayDelegate *g_delegate = nil;

void tray_init(tray_callback_fn callback, int active_port, int buzzer_on, const char *const names[16], const int visible[16], const char *icon_path) {
    g_callback = callback;
    g_delegate = [[TrayDelegate alloc] init];

    g_statusItem = [[NSStatusBar systemStatusBar]
        statusItemWithLength:NSSquareStatusItemLength];
    NSImage *img = loadTrayImage(icon_path);
    if (img) {
        g_statusItem.button.image = img;
        g_statusItem.button.imageScaling = NSImageScaleProportionallyUpOrDown;
        g_statusItem.button.title = @"";
    } else {
        g_statusItem.button.title = @"KVM";
        g_statusItem.length = NSVariableStatusItemLength;
    }

    // Build initial menu via tray_update
    extern void tray_update(int, int, const char *const[16], const int[16]);
    tray_update(active_port, buzzer_on, names, visible);
}

void tray_update(int active_port, int buzzer_on, const char *const names[16], const int visible[16]) {
    if (!g_statusItem) return;

    NSMenu *m = [[NSMenu alloc] init];

    for (int i = 1; i <= 16; i++) {
        if (!visible[i - 1]) continue;
        const char *name = names[i - 1];
        NSString *title;
        if (name && name[0] != '\0' && !(name[0] == '?' && name[1] == '\0')) {
            title = [NSString stringWithFormat:@"%d: %s", i,  name];
        } else {
            title = [NSString stringWithFormat:@"Port %d", i];
        }
        NSMenuItem *item = [[NSMenuItem alloc]
            initWithTitle:title
                   action:@selector(menuItemClicked:)
            keyEquivalent:@""];
        item.target = g_delegate;
        item.tag    = i;
        if (i == active_port) item.state = NSControlStateValueOn;
        [m addItem:item];
    }

    [m addItem:[NSMenuItem separatorItem]];

    {
        NSMenuItem *bz = [[NSMenuItem alloc]
            initWithTitle:@"Buzzer"
                   action:@selector(menuItemClicked:)
            keyEquivalent:@""];
        bz.target = g_delegate;
        bz.tag    = 100;
        if (buzzer_on) bz.state = NSControlStateValueOn;
        [m addItem:bz];
    }

    [m addItem:[NSMenuItem separatorItem]];

    {
        NSMenuItem *show = [[NSMenuItem alloc]
            initWithTitle:@"Show Window"
                   action:@selector(menuItemClicked:)
            keyEquivalent:@""];
        show.target = g_delegate;
        show.tag    = 200;
        [m addItem:show];
    }

    {
        NSMenuItem *quit = [[NSMenuItem alloc]
            initWithTitle:@"Quit"
                   action:@selector(menuItemClicked:)
            keyEquivalent:@"q"];
        quit.target = g_delegate;
        quit.tag    = 201;
        [m addItem:quit];
    }

    g_statusItem.menu = m;
}

void tray_cleanup(void) {
    if (g_statusItem) {
        [[NSStatusBar systemStatusBar] removeStatusItem:g_statusItem];
        g_statusItem = nil;
    }
    g_delegate = nil;
    g_callback = NULL;
}
