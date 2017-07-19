//
//  SeekerViewController.swift
//  Timed N Seek
//
//  Created by Patrick Ridd on 5/31/17.
//  Copyright © 2017 PatrickRidd. All rights reserved.
//

import UIKit
import CoreLocation
import CoreBluetooth
import AudioToolbox

class SeekerViewController: UIViewController, CLLocationManagerDelegate, CBPeripheralManagerDelegate {

    @IBOutlet weak var statusLabel:UILabel!
    @IBOutlet weak var seekButton:UIButton!
    @IBOutlet weak var instructionsLabel: UILabel!
    @IBOutlet weak var backButton: UIButton!
    @IBOutlet weak var letHiderHideLabel: UILabel!
    
    var uuid: String?
    var hiderBeacon: CLBeaconRegion!
    var seekerBeacon: CLBeaconRegion!
    var locationManager: CLLocationManager!
    var peripheralManager: CBPeripheralManager!
    
    
    let seekerMajorMinor = "456"
    let seekerMajorMinorWin = "777"
    let seekerMajorMinorLoss = "666"
    
    
    
    let readyOrNot = ["Here I come!!".localized,"Not".localized,"Or".localized,"Ready".localized]
    
    
    private var timer: Timer?
    private var timeSetting: TimeSetting = .twentySeconds
    private var distanceSetting: DistanceSetting = .feet
    private var elapsedTimeInSecond: Int = 20
    private var startTime: Int = 20
    
    var seekerLost = false
    var seekerWon = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Get game settings
        timeSetting = SettingsController.sharedController.getTimeSetting()
        distanceSetting = SettingsController.sharedController.getDistanceSetting()
        
        reloadSeconds()
        seekButton.layer.borderWidth = 1.0
        locationManager = CLLocationManager()
        locationManager.requestAlwaysAuthorization()
        peripheralManager = CBPeripheralManager(delegate: self as CBPeripheralManagerDelegate, queue: nil, options: nil)
        backButton.addTarget(self, action: #selector(backButtonPressed), for: .touchUpInside)
        backButton.setTitleColor(UIColor.geraldine, for: .normal)
        loadingAnimation()
        
    }
    
    // MARK: UI Methods
   
    func loadingAnimation() {
        seekButton.alpha = 0.0
        letHiderHideLabel.alpha = 0.0
        UIView.animate(withDuration: 2.0) {
            self.letHiderHideLabel.alpha = 1.0
        }
        delayWithSeconds(2) {
            self.letHiderHideLabel.isHidden = true
            UIView.animate(withDuration: 1.5, animations: {
                self.seekButton.alpha = 1.0
                self.setButtonToSeek()
            })
        }
    }

    func setButtonToSeek() {
        self.seekButton.setTitle("Seek".localized, for: .normal)
        self.seekButton.titleLabel?.font = UIFont.systemFont(ofSize: 20)
        self.seekButton.layer.borderColor = UIColor.myBlue.cgColor
        self.seekButton.setTitleColor(UIColor.myBlue, for: .normal)
    }

    func setButtonToSeeking() {
        self.seekButton.setTitle("Seeking".localized, for: .normal)
        self.seekButton.layer.borderColor = UIColor.green.cgColor
        self.seekButton.setTitleColor(UIColor.green, for: .normal)
    }
    
    func setBackButtonToReset() {
        self.backButton.setTitle("Reset".localized, for: .normal)
    }
    
    func setBackButtonToBack() {
        self.backButton.setTitle("Back".localized, for: .normal)
    }
    
    func setBackButtonToStop() {
        self.backButton.setTitle("Stop".localized, for: .normal)
    }
    
    func disableSeekButton() {
        seekButton.isEnabled = false
    }
    
    func enableSeekButton() {
        seekButton.layer.borderColor = UIColor.myBlue.cgColor
        seekButton.setTitleColor(UIColor.myBlue, for: .normal)
        seekButton.isEnabled = true
        seekButton.isHidden = false
        
    }
    
    func resetStatusLabel() {
        statusLabel.text = ""
    }
    
    
    func displayDistance(for beacon: CLBeacon) {
        if distanceSetting == .feet {
            let accuracyInFeet = String(format: "%.2f", self.metersToFeet(distanceInMeters: beacon.accuracy))
            statusLabel.text = "Hider is \(accuracyInFeet)ft away".localized
        } else {
            let accuracyInMeters = String(format: "%.2f",beacon.accuracy)
            statusLabel.text = "Hider is \(accuracyInMeters)m away".localized
        }
    }
    
    /**
     Fade in a view with a duration
     
     - parameter duration: custom animation duration
     */
    func fadeIn(withDuration duration: TimeInterval = 1.0, view: UIView) {
        UIView.animate(withDuration: duration, animations: {
            view.alpha = 1.0
        })
    }
    
    /**
     Fade out a view with a duration
     
     - parameter duration: custom animation duration
     */
    func fadeOut(withDuration duration: TimeInterval = 1.0, view: UIView) {
        UIView.animate(withDuration: duration, animations: {
            view.alpha = 0.0
        })
    }
    
    // MARK: User Alert Messages
    
    func presentCantFindBeacon() {
        statusLabel.text = ""
        resetGame()
        var distance: String = "100 feet"
        if distanceSetting == .meters { distance = "30 meters" }
        
        let alert = UIAlertController(title: "Can't find Hider's Beacon".localized, message: "Ensure they tap \"Hide\" and are within \(distance)".localized, preferredStyle: .alert)
        let gotItAction = UIAlertAction(title: "Got it".localized, style: .default, handler: nil)
        alert.addAction(gotItAction)
        self.present(alert, animated: true, completion: nil)
    }
    
    func presentSeekerWon() {
        vibrate()
        self.seekerWon = true
        self.statusLabel.textColor = UIColor.green
        self.setButtonToSeek()
        statusLabel.text = "You found the Hider!! You won!".localized
        setBackButtonToReset()
        //Broadcast to Hider that Seeker won
        broadcastBeacons()
    }
    
    func presentSeekerLost() {
        vibrate()
        self.seekerLost = true
        setBackButtonToReset()
        self.setButtonToSeek()
        self.statusLabel.textColor = UIColor.geraldine
        self.statusLabel.text = "You Lost!!!".localized
        
        //Broadcast to Hider that Hider won
        broadcastBeacons()
    }
    
    func presentBlueToothNotEnabled() {
        let blueToothAlert = UIAlertController(title: "Bluetooth is Disabled".localized, message: "We need to enable Bluetooth to connect the Hider and Seeker".localized, preferredStyle: .alert)
        let enableBluetoothAction = UIAlertAction(title: "Enable".localized, style: .default) { (_) in
            guard let url = URL(string: "App-Prefs:root=Bluetooth") else { return }
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        blueToothAlert.addAction(enableBluetoothAction)
        self.present(blueToothAlert, animated: true, completion: nil)
    }
    
    func presentScanQRCode() {
        let alert = UIAlertController(title: "Re-Scan QR Code".localized, message: "We don't have Hider's QR Code info.".localized, preferredStyle: .alert)
        let okAction = UIAlertAction(title: "Okay".localized, style: .default) { (_) in
            self.dismiss(animated: true, completion: nil)
        }
        alert.addAction(okAction)
        self.present(alert, animated: true, completion: nil)
    }
    
    func presentNeedLocationPermission() {
        let alert = UIAlertController(title: "Need Location Permission", message: "You can give us permission in settings.", preferredStyle: .alert)
        let settingsAction = UIAlertAction(title: "Settings", style: .default) { (_) in
            if let appSettings = URL(string: UIApplicationOpenSettingsURLString) {
                UIApplication.shared.open(appSettings)
            }
        }
        alert.addAction(settingsAction)
        self.present(alert, animated: true, completion: nil)
    }
    
    func showAlert(title:String, message:String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "Okay".localized, style: .default, handler: nil))
        present(alertController, animated: true, completion: nil)
    }


    // MARK: GamePlay Methods
    
    func startGame() {
        self.disableSeekButton()
        self.instructionsLabel.text = ""
        var untilGameStarts = 3
        self.statusLabel.isHidden = false
        self.statusLabel.alpha = 1.0
        self.backButton.isHidden = true
        self.statusLabel.text = self.readyOrNot[untilGameStarts]
        
        self.timer = Timer.scheduledTimer(withTimeInterval: 1.3, repeats: true, block: { (timer) in
            untilGameStarts -= 1
            self.seekButton.setTitle("\(untilGameStarts)", for: .normal)
            self.statusLabel.text = self.readyOrNot[untilGameStarts]
            
            if untilGameStarts == 0 {
                var distance = "3 feet"
                if self.distanceSetting == .meters { distance = "1 meter" }
                self.instructionsLabel.text = "Get within \(distance) of Hider".localized
                self.pauseTimer()
                self.setBackButtonToStop()
                self.backButton.isHidden = false
                self.setButtonToSeeking()
                self.delayWithSeconds(2, completion: {
                    self.instructionsLabel.text = ""
                    self.broadcastBeacons()
                    self.discoverBeacons()
                    
                })
            }
        })
    }

    func resetGame() {
        stopSearchingBeacons()
        instructionsLabel.isHidden = true
        setBackButtonToBack()
        enableSeekButton()
        stopSearchingBeacons()
        resetTimer()
        resetStatusLabel()
        self.seekerLost = false
        self.seekerWon = false
    }

    
    func updateSatusLabels(beacons: [CLBeacon]) {
        statusLabel.isHidden = false
        guard let beacon = beacons.first else { self.presentCantFindBeacon(); return }
        if elapsedTimeInSecond == self.startTime {
            startTimer()
        }
        
        displayDistance(for: beacon)
        seekerWon = determineIfSeekerWon(hiderBeacon: beacon)
        seekerLost = determineIfSeekerLost(hiderBeacon: beacon)
        
        if !seekerWon && !seekerLost {
            self.delayWithSeconds(0.5) {
                self.discoverBeacons()
            }
        }
    }
    
    func determineIfSeekerWon(hiderBeacon: CLBeacon) -> Bool {
        
        if hiderBeacon.major == 666 {
            presentSeekerWon()
            return true
        }
        
        if distanceSetting == .feet {
            let accuracyInFeet = String(format: "%.2f", self.metersToFeet(distanceInMeters: hiderBeacon.accuracy))
            if accuracyInFeet < "3.00" {
                presentSeekerWon()
                return true
            }
        } else {
            let accuracyInMeters = String(format: "%.2f", hiderBeacon.accuracy)
            if accuracyInMeters < "1.00" {
                presentSeekerWon()
                return true
            }
        }
        return false
    }
    
    func determineIfSeekerLost(hiderBeacon: CLBeacon) -> Bool {
        if hiderBeacon.major == 777 {
            presentSeekerLost()
            return true
        } else {
            return false
        }
    }
    
    // MARK: Search Beacon Methods
    
    func initializeLocationManager(callback:(Bool) -> Void) {
        if CLLocationManager.authorizationStatus() == .authorizedAlways {
            // Granted
            locationManager = CLLocationManager()
            locationManager.delegate = self
            
            guard let unwrappedUUID = self.uuid, let uuid = UUID(uuidString: unwrappedUUID) else {
                callback(false)
                self.presentScanQRCode()
                return
            }
            hiderBeacon = CLBeaconRegion(proximityUUID: uuid, identifier: "com.PatrickRidd.Timed-N-Seek-Hider")
            hiderBeacon.notifyOnEntry = true
            hiderBeacon.notifyOnExit = true
            
            locationManager.startMonitoring(for: hiderBeacon)
            locationManager.startUpdatingLocation()
            callback(true)
        } else {
            self.presentNeedLocationPermission()
            callback(false)
        }
    }
    
    func discoverBeacons() {
            self.initializeLocationManager(callback: { (success) in
                if !success {
                    resetGame()
                }
            })
    }
    
    func stopSearchingBeacons() {
        if hiderBeacon != nil {
            locationManager.stopMonitoring(for: hiderBeacon)
            locationManager.stopRangingBeacons(in: hiderBeacon)
            locationManager.stopUpdatingLocation()
        }
    }

    // MARK: CLLocationManagerDelegate functions
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways:
            print("authorized...")
            break
        case .authorizedWhenInUse:
            break
        case .denied:
            break
        case .notDetermined:
            break
        case .restricted:
            break
        }
        
    }
    
    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        locationManager.requestState(for: region)
    }
    
    
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        switch state {
        case .inside:
            locationManager.startRangingBeacons(in: hiderBeacon)
        case .outside:
            locationManager.stopRangingBeacons(in: hiderBeacon)
        case .unknown:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], in region: CLBeaconRegion) {
        if beacons.count > 0 {
            self.updateSatusLabels(beacons: beacons)
            locationManager.stopRangingBeacons(in: region)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        print("Beacon region exited: \(region)")
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        //self.presentCantFindBeacon()
    }
    
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        // self.presentCantFindBeacon()
        print("Monitring did fail: \(error)")
    }
    
    func locationManager(_ manager: CLLocationManager, rangingBeaconsDidFailFor region: CLBeaconRegion, withError error: Error) {
        print("failed: \(error)")
    }

    // MARK: CBPeripheralManagerDelegate
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn: break
        case .poweredOff:
            self.presentBlueToothNotEnabled()
        case .resetting: break
        case .unauthorized: break
        case .unsupported: break
        case .unknown: break
            
        }
    }
    
    
    // MARK: Broadcasting Beacon methods
    
    func broadcastBeacons() {
        // Attempt to broadcast
        switch peripheralManager.state {
        case .poweredOn:
            self.determineBeaconToCreate()
        case .poweredOff:
            break
        case .unauthorized:
            break
        case .resetting:
            break
        case .unknown:
            break
        case .unsupported:
            break
        }
    }
    
    
    func stopBroadcastingBeacon() {
        peripheralManager.stopAdvertising()
    }
    
    
    func determineBeaconToCreate() {
        peripheralManager.stopAdvertising()
        if seekerLost {
            // create seekerLost beacon
            seekerBeacon = self.createSeekerLostBeacon()
        } else if seekerWon {
            // create seekerWonBeacon
            seekerBeacon = self.createSeekerWonBeacon()
        } else {
            // Seeker is Seeking
            seekerBeacon = self.createNormalSeekerBeacon()
        }
        
        advertiseSeekerBeacon()
    }
    
    
    // Advertises the current Seeker Beacon
    func advertiseSeekerBeacon() {
        guard seekerBeacon != nil else { return }
        guard let dataDictionary = seekerBeacon.peripheralData(withMeasuredPower: nil) as? [String: Any] else {
            showAlert(title: "Error Connecting".localized, message: "We are having trouble signaling the device. Please try again.".localized)
            return
        }
        peripheralManager.startAdvertising(dataDictionary)
    }
    
    // Creates a normal seeker beacon that is used during gameplay
    func createNormalSeekerBeacon() -> CLBeaconRegion? {
        guard let uuidString = self.uuid, let uuid = UUID(uuidString: uuidString), let major = CLBeaconMajorValue(self.seekerMajorMinor), let minor = CLBeaconMinorValue(self.seekerMajorMinor) else {
            return nil
        }
        return CLBeaconRegion(proximityUUID: uuid, major: major, minor: minor, identifier: "com.PatrickRidd.Timed-N-Seek-Seeker")
        
    }
    
    // Creates a beacon that broadcasts to the Hider that the seeker won.
    func createSeekerWonBeacon() -> CLBeaconRegion? {
        guard let uuidString = self.uuid, let uuid = UUID(uuidString: uuidString), let major = CLBeaconMajorValue(self.seekerMajorMinorWin), let minor = CLBeaconMinorValue(self.seekerMajorMinorWin) else {
            return nil
        }
        return CLBeaconRegion(proximityUUID: uuid, major: major, minor: minor, identifier: "com.PatrickRidd.Timed-N-Seek-Seeker")
    }
    
    
    // Creates a beacon that broadcasts to the Hider that the Seeker ran out of time and lost.
    func createSeekerLostBeacon() -> CLBeaconRegion? {
        guard let uuidString = self.uuid, let uuid = UUID(uuidString: uuidString), let major = CLBeaconMajorValue(self.seekerMajorMinorLoss), let minor = CLBeaconMinorValue(self.seekerMajorMinorLoss) else {
            return nil
        }
        return CLBeaconRegion(proximityUUID: uuid, major: major, minor: minor, identifier: "com.PatrickRidd.Timed-N-Seek-Seeker")
    }
    
    // MARK: Timer methods
    
    func startTimer() {
        self.updateTimeLabel()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { (timer) in
            self.elapsedTimeInSecond -= 1
            self.updateTimeLabel()
            if self.elapsedTimeInSecond == 0 {
                self.presentSeekerLost()
            }
        })
        
    }

    func pauseTimer() {
        timer?.invalidate()
    }
    
    func resetTimer() {
        timer?.invalidate()
        reloadSeconds()
    }
    
    func reloadSeconds() {
        switch self.timeSetting {
        case .twentySeconds:
            self.elapsedTimeInSecond = 20
        case .fortySeconds:
            self.elapsedTimeInSecond = 40
        case .sixtySeconds:
            self.elapsedTimeInSecond = 60
        }
        
        self.startTime = elapsedTimeInSecond
    }

    
    func updateTimeLabel() {
        let seconds = elapsedTimeInSecond % 60
        self.seekButton.titleLabel?.font = UIFont.systemFont(ofSize: 28)
        self.seekButton.setTitle(String(format: "%2d", elapsedTimeInSecond), for: .normal)
    }
    
    // MARK: Actions
    @IBAction func startButtonPressed(sender:Any){
        resetTimer()
        startGame()
    }
    
    func backButtonPressed() {
        if backButton.titleLabel?.text == "Back".localized {
            if let presenter = self.presentingViewController{
                presenter.dismiss(animated: true, completion: nil)
            }
        } else {
            resetGame()
        }
    }
    
    
    // MARK: Helpers
    
    func getProximityString(proximity: CLProximity) -> String {
        switch proximity {
        case .immediate:
            return "Immediate".localized
        case .far:
            return "Far".localized
        case .near:
            return "Near".localized
        case .unknown:
            return "Unknown".localized
        }
    }
    
    func metersToFeet(distanceInMeters: Double) -> Double {
        return distanceInMeters * 3.28084
    }
    
    func vibrate() {
        AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
    }

    func delayWithSeconds(_ seconds: Double, completion: @escaping () -> ()) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            completion()
        }
    }
    
}
