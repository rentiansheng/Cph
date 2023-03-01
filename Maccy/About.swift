import Cocoa

class About {
  private let familyCredits = NSAttributedString(
    string: "Special thank you to Cph(clipboard history)! ❤️",
    attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor]
  )

  private var kossCredits: NSMutableAttributedString {
    let string = NSMutableAttributedString(string: "document! 🏂",
                                              attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor])
       string.addAttribute(.link, value: "https://ireage.com/cph.html", range: NSRange(location: 0, length: 10))
    return string
  }

  private var links: NSMutableAttributedString {
    let string = NSMutableAttributedString(string: "Website│use GitHub│Support",
                                               attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor])
        string.addAttribute(.link, value: "https://ireage.com", range: NSRange(location: 0, length: 7))
        string.addAttribute(.link, value: "https://github.com/rentiansheng/Cph", range: NSRange(location: 8, length: 10))
        string.addAttribute(.link, value: "mailto:reage521@gmail.com", range: NSRange(location: 19, length: 7))
    return string
  }

  private var credits: NSMutableAttributedString {
    let credits = NSMutableAttributedString(string: "",
                                            attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor])
    credits.append(links)
    credits.append(NSAttributedString(string: "\n\n"))
    credits.append(kossCredits)
    credits.append(NSAttributedString(string: "\n"))
    credits.append(familyCredits)
    credits.setAlignment(.center, range: NSRange(location: 0, length: credits.length))
    return credits
  }

  @objc
  func openAbout(_ sender: NSMenuItem) {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [NSApplication.AboutPanelOptionKey.credits: credits])
  }
}
