
import UIKit
import WebKit
import CoreLocation

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = ViewController()
        window?.makeKeyAndVisible()
        return true
    }
}

class ViewController: UIViewController,
                      CLLocationManagerDelegate,
                      WKNavigationDelegate {

    private var webView: WKWebView!
    private let locationManager = CLLocationManager()

    private var latestLocation: CLLocation?
    private var isLocationUpdating = false
    private var webPageLoaded = false

    private let weatherURL = "https://navigatorcad.github.io/Carplay-weather/"

    override func viewDidLoad() {
        super.viewDidLoad()

        setupWebView()
        setupLocationManager()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        webView = WKWebView(
            frame: view.bounds,
            configuration: config
        )

        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.navigationDelegate = self

        view.addSubview(webView)

        if let url = URL(string: weatherURL) {
            var request = URLRequest(url: url)
            request.cachePolicy = .useProtocolCachePolicy
            request.timeoutInterval = 30
            webView.load(request)
        }
    }

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 100
        locationManager.activityType = .automotiveNavigation
        locationManager.pausesLocationUpdatesAutomatically = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startLocationServices()
    }

    @objc private func applicationDidBecomeActive() {
        startLocationServices()
        sendLatestLocationToWebView()
    }

    private func startLocationServices() {
        guard CLLocationManager.locationServicesEnabled() else {
            print("[WeatherGPS] Location Services disabled")
            return
        }

        switch locationManager.authorizationStatus {

        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()

        case .authorizedWhenInUse, .authorizedAlways:
            if !isLocationUpdating {
                locationManager.startUpdatingLocation()
                isLocationUpdating = true
            }

        case .denied, .restricted:
            print("[WeatherGPS] Location permission denied")

        @unknown default:
            print("[WeatherGPS] Unknown authorization status")
        }
    }

    func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        startLocationServices()
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else {
            return
        }

        // Bỏ qua tọa độ có độ chính xác không hợp lệ.
        guard location.horizontalAccuracy >= 0 else {
            return
        }

        // Không sử dụng tọa độ quá cũ.
        let age = Date().timeIntervalSince(location.timestamp)

        guard age >= -10 && age <= 120 else {
            return
        }

        latestLocation = location

        print(
            "[WeatherGPS] Location:",
            location.coordinate.latitude,
            location.coordinate.longitude,
            "Accuracy:",
            location.horizontalAccuracy
        )

        sendLatestLocationToWebView()
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        print("[WeatherGPS] Error:", error.localizedDescription)
    }

    // MARK: - WebView JavaScript Bridge

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        webPageLoaded = true
        print("[WeatherWebView] Page loaded")

        sendLatestLocationToWebView()
    }

    func webView(
        _ webView: WKWebView,
        didStartProvisionalNavigation navigation: WKNavigation!
    ) {
        webPageLoaded = false
    }

    private func sendLatestLocationToWebView() {
        guard webPageLoaded,
              let location = latestLocation else {
            return
        }

        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude

        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  self.webPageLoaded else {
                return
            }

            let js = String(
                format: "if (typeof window.setCarPlayLocation === 'function') { window.setCarPlayLocation(%.7f, %.7f); }",
                locale: Locale(identifier: "en_US_POSIX"),
                latitude,
                longitude
            )

            self.webView.evaluateJavaScript(js) { _, error in
                if let error = error {
                    print(
                        "[WeatherBridge] JavaScript error:",
                        error.localizedDescription
                    )
                } else {
                    print("[WeatherBridge] GPS sent to HTML")
                }
            }
        }
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }
}
