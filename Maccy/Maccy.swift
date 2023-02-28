import Cocoa
import KeyboardShortcuts
import Preferences

// swiftlint:disable type_body_length
class Maccy: NSObject {
  static public var returnFocusToPreviousApp = true

  @objc public let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let statusItemTitleMaxLength = 10

  private let about = About()
  private let clipboard = Clipboard()
  private let history = History()
  // 在屏幕中展示
  private var cphHistoyMenu: Menu!
  // 程序菜但是用，
  private var menuBar: Menu!
  private var menuLoader: MenuLoader!
  private var window: NSWindow!

  private let carbonMenuWindowClass = "NSStatusBarWindow"
  private var clearAlert: NSAlert {
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("clear_alert_message", comment: "")
    alert.informativeText = NSLocalizedString("clear_alert_comment", comment: "")
    alert.addButton(withTitle: NSLocalizedString("clear_alert_confirm", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("clear_alert_cancel", comment: ""))
    alert.showsSuppressionButton = true
    return alert
  }
  private var extraVisibleWindows: [NSWindow] {
    return NSApp.windows.filter({ $0.isVisible && String(describing: type(of: $0)) != carbonMenuWindowClass })
  }
    


  private lazy var preferencesWindowController = PreferencesWindowController(
    preferencePanes: [
      GeneralPreferenceViewController(),
      StoragePreferenceViewController(),
      AppearancePreferenceViewController(),
      PinsPreferenceViewController(),
      IgnorePreferenceViewController(),
      AdvancedPreferenceViewController()
    ]
  )

  private var filterMenuRect: NSRect {
    return NSRect(x: 0, y: 0, width: cphHistoyMenu.menuWidth, height: UserDefaults.standard.hideSearch ? 1 : 15)
  }

  private var enabledPasteboardTypesObserver: NSKeyValueObservation?
  private var ignoreEventsObserver: NSKeyValueObservation?
  private var imageHeightObserver: NSKeyValueObservation?
  private var hideFooterObserver: NSKeyValueObservation?
  private var hideSearchObserver: NSKeyValueObservation?
  private var hideTitleObserver: NSKeyValueObservation?
  private var pasteByDefaultObserver: NSKeyValueObservation?
  private var pinToObserver: NSKeyValueObservation?
  private var removeFormattingByDefaultObserver: NSKeyValueObservation?
  private var sortByObserver: NSKeyValueObservation?
  private var showRecentCopyInMenuBarObserver: NSKeyValueObservation?
  private var statusItemConfigurationObserver: NSKeyValueObservation?
  private var statusItemVisibilityObserver: NSKeyValueObservation?

  override init() {
    UserDefaults.standard.register(defaults: [UserDefaults.Keys.showInStatusBar: UserDefaults.Values.showInStatusBar])
    super.init()
    initializeObservers()

    cphHistoyMenu = Menu(history: history, clipboard: clipboard)
    menuBar = Menu(history: history, clipboard: clipboard)
    menuLoader = MenuLoader(performStatusItemClick)
    start()
  }

  deinit {
    enabledPasteboardTypesObserver?.invalidate()
    ignoreEventsObserver?.invalidate()
    hideFooterObserver?.invalidate()
    hideSearchObserver?.invalidate()
    hideTitleObserver?.invalidate()
    pasteByDefaultObserver?.invalidate()
    pinToObserver?.invalidate()
    removeFormattingByDefaultObserver?.invalidate()
    sortByObserver?.invalidate()
    showRecentCopyInMenuBarObserver?.invalidate()
    statusItemConfigurationObserver?.invalidate()
    statusItemVisibilityObserver?.invalidate()
  }

  func popUp() {
    withFocus {
       switch UserDefaults.standard.popupPosition {
      case "center":
        if let screen = NSScreen.main {
          let topLeftX = (screen.frame.width - self.cphHistoyMenu.size.width) / 2 + screen.frame.origin.x
          var topLeftY = (screen.frame.height + self.cphHistoyMenu.size.height) / 2 - screen.frame.origin.y
          if screen.frame.height < self.cphHistoyMenu.size.height {
            topLeftY = screen.frame.origin.y
          }
          self.linkingMenuToStatusItem {
            self.cphHistoyMenu.popUp(positioning: nil, at: NSPoint(x: topLeftX + 1.0, y: topLeftY + 1.0), in: nil)
          }
        }
      case "statusItem":
        self.simulateStatusItemClick()
      default:
        self.linkingMenuToStatusItem {
          self.cphHistoyMenu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
      }
    }
  }

  @objc
  func performStatusItemClick(_ event: NSEvent?) {
      //  菜单栏展示
    if let event = event {
      if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option {
        UserDefaults.standard.ignoreEvents = !UserDefaults.standard.ignoreEvents
        return
      }
    }

    withFocus {
      self.simulateStatusItemClick()
    }
  }

  private func start() {
    statusItem.behavior = .removalAllowed
    statusItem.isVisible = UserDefaults.standard.showInStatusBar
    statusItem.menu = menuLoader

    if let button = statusItem.button {
      button.image = NSImage(named: "StatusBarMenuImage")
      button.imagePosition = .imageRight
      (button.cell as? NSButtonCell)?.highlightsBy = []
    }

    clipboard.onNewCopy(history.add)
    clipboard.onNewCopy(cphHistoyMenu.add)
    clipboard.onNewCopy(updateMenuTitle)
    clipboard.startListening()

    populateHeader()
    populateItems()
    populateFooter()

    updateStatusItemEnabledness()
  }

  private func populateHeader() {
    let headerItemView = FilterMenuItemView(frame: filterMenuRect)
    // search textFile label name
    headerItemView.title = ""

    let headerItem = NSMenuItem()
    headerItem.title = ""
    headerItem.view = headerItemView
    headerItem.isEnabled = false

    cphHistoyMenu.addItem(headerItem)
  }

  private func populateItems() {
    cphHistoyMenu.buildItems()
    updateMenuTitle()
  }

  private func populateFooter() {
    MenuFooter.allCases.map({ $0.menuItem }).forEach({ item in
      item.action = #selector(menuItemAction)
      item.target = self
      menuBar.addItem(item)
    })


  }

  @objc
  func menuItemAction(_ sender: NSMenuItem) {
    if let tag = MenuFooter(rawValue: sender.tag) {
      switch tag {
      case .about:
        Maccy.returnFocusToPreviousApp = false
        about.openAbout(sender)
      case .clear:
        clearUnpinned()
      case .clearAll:
        clearAll()
      case .quit:
        NSApp.terminate(sender)
      case .preferences:
        Maccy.returnFocusToPreviousApp = false
        preferencesWindowController.show()
      default:
        break
      }
    }
  }

  func clearUnpinned(suppressClearAlert: Bool = false) {
    withClearAlert(suppressClearAlert: suppressClearAlert) {
      self.history.clearUnpinned()
      self.cphHistoyMenu.clearUnpinned()
    }
  }

  private func clearAll(suppressClearAlert: Bool = false) {
    withClearAlert(suppressClearAlert: suppressClearAlert) {
      self.history.clear()
      self.cphHistoyMenu.clearAll()
    }
  }

  private func withClearAlert(suppressClearAlert: Bool, _ closure: @escaping () -> Void) {
    if suppressClearAlert || UserDefaults.standard.supressClearAlert {
      closure()
    } else {
      let alert = clearAlert
      if alert.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn {
        if alert.suppressionButton?.state == .on {
          UserDefaults.standard.supressClearAlert = true
        }
        closure()
      }
    }
  }

  private func rebuild() {
    cphHistoyMenu.clearAll()
    cphHistoyMenu.removeAllItems()

    populateHeader()
    populateItems()
    //populateFooter()
  }

  private func updateMenuTitle(_ item: HistoryItem? = nil) {
    guard UserDefaults.standard.showRecentCopyInMenuBar else {
      statusItem.button?.title = ""
      return
    }

    var title = ""
    if let item = item {
      title = HistoryMenuItem(item: item, clipboard: clipboard).title
    } else if let item = cphHistoyMenu.firstUnpinnedHistoryMenuItem {
      title = item.title
    }

    statusItem.button?.title = String(title.prefix(statusItemTitleMaxLength))
  }

  private func simulateStatusItemClick() {
    if let buttonCell = statusItem.button?.cell as? NSButtonCell {
      withMenuButtonHighlighted(buttonCell) {
        self.linkingMenuToStatusItem {
          self.statusItem.button?.performClick(self)
        }
      }
    }
  }

  private func withMenuButtonHighlighted(_ buttonCell: NSButtonCell, _ closure: @escaping () -> Void) {
    if #available(OSX 10.11, *) {
      // Big Sur doesn't need to highlight manually
      closure()
    } else {
      buttonCell.highlightsBy = [.changeGrayCellMask, .contentsCellMask, .pushInCellMask]
      closure()
      buttonCell.highlightsBy = []
    }
  }

  private func linkingMenuToStatusItem(_ closure: @escaping () -> Void) {
    statusItem.menu = menuBar
    closure()
    statusItem.menu = menuLoader

  }

  // Executes closure with application focus (pun intended).
  //
  // Beware of hacks. This code is so fragile that you should
  // avoid touching it unless you really know what you do.
  // The code is based on hours of googling, trial-and-error
  // and testing sessions. Apologies to any future me.
  //
  // Once we scheduled menu popup, we need to activate
  // the application to let search text field become first
  // responder and start receiving key events.
  // Without forced activation, agent application
  // (LSUIElement) doesn't receive the focus.
  // Once activated, we need to run the closure asynchronously
  // (and with slight delay) because NSMenu.popUp() is blocking
  // execution until menu is closed (https://stackoverflow.com/q/1857603).
  // Annoying side-effect of running NSMenu.popUp() asynchronously
  // is global hotkey being immediately enabled so we no longer
  // can close menu by pressing the hotkey again. To workaround
  // this problem, lifecycle of global hotkey should live here.
  // 40ms delay was chosen by trial-and-error. It's the smallest value
  // not causing menu to close on the first time it is opened after
  // the application launch.
  //
  // Once we are done working with menu, we need to return
  // focus to previous application. However, if our selection
  // triggered new windows (Preferences, About, Accessibility),
  // we should preserve focus. Additionally, we should not
  // hide an application if there are additional visible windows
  // opened before.
  //
  // It's also possible to complete skip this activation
  // and fallback to default NSMenu behavior by enabling
  // UserDefaults.standard.avoidTakingFocus.
  private func withFocus(_ closure: @escaping () -> Void) {
    Maccy.returnFocusToPreviousApp = extraVisibleWindows.count == 0
    KeyboardShortcuts.disable(.popup)

    if UserDefaults.standard.avoidTakingFocus {
      closure()
      KeyboardShortcuts.enable(.popup)
    } else {
      NSApp.activate(ignoringOtherApps: true)
      Timer.scheduledTimer(withTimeInterval: 0.04, repeats: false) { _ in
        closure()
        KeyboardShortcuts.enable(.popup)
        if Maccy.returnFocusToPreviousApp {
          NSApp.hide(self)
        }
      }
    }
  }

  private func updateStatusItemEnabledness() {
    statusItem.button?.appearsDisabled = UserDefaults.standard.ignoreEvents ||
      UserDefaults.standard.enabledPasteboardTypes.isEmpty
  }

  private func initializeObservers() {
    enabledPasteboardTypesObserver = UserDefaults.standard.observe(\.enabledPasteboardTypes, options: .new) { _, _ in
      self.updateStatusItemEnabledness()
    }
    ignoreEventsObserver = UserDefaults.standard.observe(\.ignoreEvents, options: .new) { _, _ in
      self.updateStatusItemEnabledness()
    }
    imageHeightObserver = UserDefaults.standard.observe(\.imageMaxHeight, options: .new) { _, _ in
      self.cphHistoyMenu.resizeImageMenuItems()
    }
    hideFooterObserver = UserDefaults.standard.observe(\.hideFooter, options: .new) { _, _ in
      self.rebuild()
    }
    hideSearchObserver = UserDefaults.standard.observe(\.hideSearch, options: .new) { _, _ in
      self.rebuild()
    }
    hideTitleObserver = UserDefaults.standard.observe(\.hideTitle, options: .new) { _, _ in
      self.rebuild()
    }
    pasteByDefaultObserver = UserDefaults.standard.observe(\.pasteByDefault, options: .new) { _, _ in
      self.rebuild()
    }
    pinToObserver = UserDefaults.standard.observe(\.pinTo, options: .new) { _, _ in
      self.rebuild()
    }
    removeFormattingByDefaultObserver = UserDefaults.standard.observe(\.removeFormattingByDefault,
                                                                      options: .new) { _, _ in
      self.rebuild()
    }
    sortByObserver = UserDefaults.standard.observe(\.sortBy, options: .new) { _, _ in
      self.rebuild()
    }
    showRecentCopyInMenuBarObserver = UserDefaults.standard.observe(\.showRecentCopyInMenuBar,
                                                                    options: .new) { _, _ in
      self.updateMenuTitle()
    }
    statusItemConfigurationObserver = UserDefaults.standard.observe(\.showInStatusBar,
                                                                    options: .new) { _, change in
      if self.statusItem.isVisible != change.newValue! {
        self.statusItem.isVisible = change.newValue!
      }
    }
    statusItemVisibilityObserver = observe(\.statusItem.isVisible, options: .new) { _, change in
      if UserDefaults.standard.showInStatusBar != change.newValue! {
        UserDefaults.standard.showInStatusBar = change.newValue!
      }
    }
  }
}
// swiftlint:enable type_body_length
