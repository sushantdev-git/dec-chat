import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var blePlatformChannel: BlePlatformChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if blePlatformChannel == nil, let controller = window?.rootViewController as? FlutterViewController {
      blePlatformChannel = BlePlatformChannel(messenger: controller.binaryMessenger)
    }
    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if blePlatformChannel == nil {
      blePlatformChannel = BlePlatformChannel(messenger: engineBridge.applicationRegistrar.messenger())
    }
  }
}
