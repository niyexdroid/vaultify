import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    PrivacyCover.install()
    NoICloudBackup.apply()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

/// No iCloud backup: keeps the vault on this iPhone only (matches Android's
/// allowBackup=false). Marks the whole Application Support folder, where
/// path_provider's support directory puts vault.vfy and settings.json, as
/// excluded from iCloud and computer backups. The folder is flagged rather
/// than each file because saves rename a temp file over the vault, which
/// would drop a per-file flag. Runs before Flutter starts, on every launch.
enum NoICloudBackup {
  static func apply() {
    let fileManager = FileManager.default
    guard
      var folder = fileManager.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first
    else { return }
    do {
      try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try folder.setResourceValues(values)
    } catch {
      // Not fatal: the vault still works; it just isn't kept out of backup.
      NSLog("Vaultify: could not exclude app data from backup")
    }
  }
}

/// iOS privacy cover: a plain Vaultify screen laid over the app whenever it
/// stops being active (app switcher, Control Center, going to the
/// background), so the app-switcher preview never shows passwords. Removed
/// as soon as the app is active again.
enum PrivacyCover {
  private static let coverTag = 0x5641_554C  // "VAUL"

  static func install() {
    let center = NotificationCenter.default
    center.addObserver(
      forName: UIScene.willDeactivateNotification, object: nil, queue: .main
    ) { note in
      guard let scene = note.object as? UIWindowScene else { return }
      scene.windows.forEach(show(in:))
    }
    center.addObserver(
      forName: UIScene.didActivateNotification, object: nil, queue: .main
    ) { note in
      guard let scene = note.object as? UIWindowScene else { return }
      scene.windows.forEach(hide(in:))
    }
  }

  private static func show(in window: UIWindow) {
    guard window.viewWithTag(coverTag) == nil else { return }
    let cover = UIView(frame: window.bounds)
    cover.tag = coverTag
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    cover.backgroundColor = UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor(red: 0x11 / 255, green: 0x13 / 255, blue: 0x15 / 255, alpha: 1)
        : .white
    }

    // Shield icon in brand green above the app name.
    let green = UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor(red: 0x3D / 255, green: 0xBE / 255, blue: 0x7A / 255, alpha: 1)
        : UIColor(red: 0x1A / 255, green: 0x9E / 255, blue: 0x5B / 255, alpha: 1)
    }
    let icon = UIImageView(image: UIImage(systemName: "lock.shield"))
    icon.tintColor = green
    icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 48)
    let name = UILabel()
    name.text = "Vaultify"
    name.font = .systemFont(ofSize: 18, weight: .medium)
    name.textColor = .label

    let stack = UIStackView(arrangedSubviews: [icon, name])
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    cover.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
    ])
    window.addSubview(cover)
  }

  private static func hide(in window: UIWindow) {
    window.viewWithTag(coverTag)?.removeFromSuperview()
  }
}
