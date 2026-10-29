import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let configuredKey = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_MAPS_API_KEY") as? String
    let unresolvedPlaceholder = "$(GOOGLE_MAPS_API_KEY)"

    guard let mapsApiKey = configuredKey,
          !mapsApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          mapsApiKey != unresolvedPlaceholder else {
      fatalError(
        "Google Maps for iOS is not configured. Set GOOGLE_MAPS_API_KEY in ios/Flutter/Maps.xcconfig."
      )
    }

    GMSServices.provideAPIKey(mapsApiKey)
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
