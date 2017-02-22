//
//  DeviceViewController.swift
//  SwiftStarter
//
//  Created by Stephen Schiffli on 10/20/15.
//  Copyright © 2015 MbientLab Inc. All rights reserved.
//

import UIKit
import MetaWear
import MBProgressHUD

class DeviceViewController: UIViewController {
    @IBOutlet weak var deviceStatus: UILabel!
    @IBOutlet weak var deviceBattery: UILabel!
    @IBOutlet weak var deviceTemp: UILabel!
    
    @IBOutlet weak var sensorFusionMode: UISegmentedControl!
    @IBOutlet weak var sensorFusionOutput: UISegmentedControl!
    @IBOutlet weak var sensorFusionStartStream: UIButton!
    @IBOutlet weak var sensorFusionStopStream: UIButton!
    @IBOutlet weak var sensorFusionStartLog: UIButton!
    @IBOutlet weak var sensorFusionStopLog: UIButton!
    @IBOutlet weak var sensorFusionGraph: APLGraphView!
    @IBOutlet weak var sensorFusionSendData: UIButton!
    
    var sensorFusionData = Data()
    
    var streamingEvents: Set<NSObject> = [] // Can't use proper type due to compiler seg fault
    
    var isObserving = false {
        didSet {
            if self.isObserving {
                if !oldValue {
                    self.device.addObserver(self, forKeyPath: "state", options: .new, context: nil)
                }
            } else {
                if oldValue {
                    self.device.removeObserver(self, forKeyPath: "state")
                }
            }
        }
    }
    var hud: MBProgressHUD!
    
    var controller: UIDocumentInteractionController!
    
    var device: MBLMetaWear!
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        
        device.addObserver(self, forKeyPath: "state", options: NSKeyValueObservingOptions.new, context: nil)
        
        device.connectAsync().success { _ in
            self.device.led?.flashColorAsync(UIColor.green, withIntensity: 1.0, numberOfFlashes: 3)
            NSLog("We are connected")
            
            // we are now connected so we are going to get some values
            // get battery
            self.device.readBatteryLifeAsync().success { result in
                self.deviceBattery.text = result.stringValue
            }
            
            // get the temperature
            self.device.temperature?.onboardThermistor?.readAsync().success { result in
                self.deviceTemp.text = result.value.stringValue.appending("°C");
                NSLog("got the temp");
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        device.removeObserver(self, forKeyPath: "state")
        device.led?.flashColorAsync(UIColor.red, withIntensity: 1.0, numberOfFlashes: 3)
        device.disconnectAsync()
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        OperationQueue.main.addOperation {
            switch (self.device.state) {
            case .connected:
                self.deviceStatus.text = "Connected";
            case .connecting:
                self.deviceStatus.text = "Connecting";
            case .disconnected:
                self.deviceStatus.text = "Disconnected";
            case .disconnecting:
                self.deviceStatus.text = "Disconnecting";
            case .discovery:
                self.deviceStatus.text = "Discovery";
            }
           
        }
    }

    /*
    func connectDevice(_ on: Bool) {
        let hud = MBProgressHUD.showAdded(to: UIApplication.shared.keyWindow!, animated: true)
        if on {
            hud.label.text = "Connecting..."
            device.connect(withTimeoutAsync: 15).continueOnDispatch { t in
                if (t.error?._domain == kMBLErrorDomain) && (t.error?._code == kMBLErrorOutdatedFirmware) {
                    hud.hide(animated: true)
                    self.firmwareUpdateLabel.text! = "Force Update"
                    self.updateFirmware(self.setNameButton)
                    return nil
                }
                hud.mode = .text
                if t.error != nil {
                    self.showAlertTitle("Error", message: t.error!.localizedDescription)
                    hud.hide(animated: false)
                } else {
                    self.deviceConnected()
                    
                    hud.label.text! = "Connected!"
                    hud.hide(animated: true, afterDelay: 0.5)
                }
                return nil
            }
        } else {
            hud.label.text = "Disconnecting..."
            device.disconnectAsync().continueOnDispatch { t in
                self.deviceDisconnected()
                hud.mode = .text
                if t.error != nil {
                    self.showAlertTitle("Error", message: t.error!.localizedDescription)
                    hud.hide(animated: false)
                }
                else {
                    hud.label.text = "Disconnected!"
                    hud.hide(animated: true, afterDelay: 0.5)
                }
                return nil
            }
        }
    }
*/
    
    func logCleanup(_ handler: @escaping MBLErrorHandler) {
        // In order for the device to actaully erase the flash memory we can't be in a connection
        // so temporally disconnect to allow flash to erase.
        isObserving = false
        device.disconnectAsync().continueOnDispatch { t in
            self.isObserving = true
            guard t.error == nil else {
                return t
            }
            return self.device.connect(withTimeoutAsync: 15)
            }.continueOnDispatch { t in
                handler(t.error)
                return nil
        }
    }
    
    func showAlertTitle(_ title: String, message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "Okay", style: .default, handler: nil))
        self.present(alertController, animated: true, completion: nil)
    }

    func send(_ data: Data, title: String) {
        // Get current Time/Date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM_dd_yyyy-HH_mm_ss"
        let dateString = dateFormatter.string(from: Date())
        let name = "\(title)_\(dateString).csv"
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
        do {
            try data.write(to: fileURL, options: .atomic)
            // Popup the default share screen
            self.controller = UIDocumentInteractionController(url: fileURL)
            if !self.controller.presentOptionsMenu(from: view.bounds, in: view, animated: true) {
                self.showAlertTitle("Error", message: "No programs installed that could save the file")
            }
        } catch let error {
            self.showAlertTitle("Error", message: error.localizedDescription)
        }
    }
    
    func updateSensorFusionSettings() {
        device.sensorFusion!.mode = MBLSensorFusionMode(rawValue: UInt8(sensorFusionMode.selectedSegmentIndex) + 1)!
        sensorFusionMode.isEnabled = false
        sensorFusionOutput.isEnabled = false
        sensorFusionData = Data()
        sensorFusionGraph.fullScale = 8
    }
    
    func trim(_ maxValue: Double, minValue: Double) {
        
        
    }
    
    @IBAction func sensorFusionStartStreamPressed(_ sender: Any) {
        sensorFusionStartStream.isEnabled = false
        sensorFusionStopStream.isEnabled = true
        sensorFusionStartLog.isEnabled = false
        sensorFusionStopLog.isEnabled = false
        updateSensorFusionSettings()
        
        var task: BFTask<AnyObject>?
        switch sensorFusionOutput.selectedSegmentIndex {
        case 0:
            streamingEvents.insert(device.sensorFusion!.eulerAngle)
            task = device.sensorFusion!.eulerAngle.startNotificationsAsync { (obj, error) in
                if let obj = obj {
                    self.sensorFusionGraph.addX(self.sensorFusionGraph.scale(obj.p, min: -180, max: 180), y: self.sensorFusionGraph.scale(obj.r, min: -90, max: 90), z: self.sensorFusionGraph.scale(obj.y, min: 0, max: 360))
                    self.sensorFusionData.append("\(obj.timestamp.timeIntervalSince1970),\(obj.p),\(obj.r),\(obj.y)\n".data(using: String.Encoding.utf8)!)
                }
            }
        case 1:
            streamingEvents.insert(device.sensorFusion!.quaternion)
            task = device.sensorFusion!.quaternion.startNotificationsAsync { (obj, error) in
                if let obj = obj {
                    self.sensorFusionGraph.addX(self.sensorFusionGraph.scale(obj.x, min: -1.0, max: 1.0), y: self.sensorFusionGraph.scale(obj.y, min: -1.0, max: 1.0), z: self.sensorFusionGraph.scale(obj.z, min: -1.0, max: 1.0))
                    self.sensorFusionData.append("\(obj.timestamp.timeIntervalSince1970),\(obj.x),\(obj.y),\(obj.z)\n".data(using: String.Encoding.utf8)!)
                }
            }
        case 2:
            streamingEvents.insert(device.sensorFusion!.gravity)
            task = device.sensorFusion!.gravity.startNotificationsAsync { (obj, error) in
                if let obj = obj {
                    self.sensorFusionGraph.addX(self.sensorFusionGraph.scale(obj.x, min: -1.0, max: 1.0), y: self.sensorFusionGraph.scale(obj.y, min: -1.0, max: 1.0), z: self.sensorFusionGraph.scale(obj.z, min: -1.0, max: 1.0))
                    self.sensorFusionData.append("\(obj.timestamp.timeIntervalSince1970),\(obj.x),\(obj.y),\(obj.z)\n".data(using: String.Encoding.utf8)!)
                }
            }
        case 3:
            streamingEvents.insert(device.sensorFusion!.linearAcceleration)
            switch (device.accelerometer as! MBLAccelerometerBosch).fullScaleRange {
            case .range2G:
                sensorFusionGraph.fullScale = 2.0
            case .range4G:
                sensorFusionGraph.fullScale = 4.0
            case .range8G:
                sensorFusionGraph.fullScale = 8.0
            case.range16G:
                sensorFusionGraph.fullScale = 16.0
            }
            task = device.sensorFusion!.linearAcceleration.startNotificationsAsync { (obj, error) in
                if let obj = obj {
                    self.sensorFusionGraph.addX(obj.x, y: obj.y, z: obj.z)
                    self.sensorFusionData.append("\(obj.timestamp.timeIntervalSince1970),\(obj.x),\(obj.y),\(obj.z)\n".data(using: String.Encoding.utf8)!)
                }
            }
        default:
            assert(false, "Added a new sensor fusion output?")
        }
        
        task?.failure { error in
            // Currently can't recover nicely from this error
            let alertController = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "Okay", style: .default) { alert in
                self.device.resetDevice()
            })
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    @IBAction func sensorFusionStopStreamPressed(_ sender: Any) {
        sensorFusionStartStream.isEnabled = true
        sensorFusionStopStream.isEnabled = false
        sensorFusionStartLog.isEnabled = true
        sensorFusionMode.isEnabled = true
        sensorFusionOutput.isEnabled = true
        
        switch sensorFusionOutput.selectedSegmentIndex {
        case 0:
            streamingEvents.remove(device.sensorFusion!.eulerAngle)
            device.sensorFusion!.eulerAngle.stopNotificationsAsync()
        case 1:
            streamingEvents.remove(device.sensorFusion!.quaternion)
            device.sensorFusion!.quaternion.stopNotificationsAsync()
        case 2:
            streamingEvents.remove(device.sensorFusion!.gravity)
            device.sensorFusion!.gravity.stopNotificationsAsync()
        case 3:
            streamingEvents.remove(device.sensorFusion!.linearAcceleration)
            device.sensorFusion!.linearAcceleration.stopNotificationsAsync()
        default:
            assert(false, "Added a new sensor fusion output?")
        }
    }
    
    @IBAction func sensorFusionStartLogPressed(_ sender: Any) {
        sensorFusionStartLog.isEnabled = false
        sensorFusionStopLog.isEnabled = true
        sensorFusionStartStream.isEnabled = false
        sensorFusionStopStream.isEnabled = false
        updateSensorFusionSettings()
        
        switch sensorFusionOutput.selectedSegmentIndex {
        case 0:
            device.sensorFusion!.eulerAngle.startLoggingAsync()
        case 1:
            device.sensorFusion!.quaternion.startLoggingAsync()
        case 2:
            device.sensorFusion!.gravity.startLoggingAsync()
        case 3:
            switch (device.accelerometer as! MBLAccelerometerBosch).fullScaleRange {
            case .range2G:
                sensorFusionGraph.fullScale = 2.0
            case .range4G:
                sensorFusionGraph.fullScale = 4.0
            case .range8G:
                sensorFusionGraph.fullScale = 8.0
            case.range16G:
                sensorFusionGraph.fullScale = 16.0
            }
            device.sensorFusion!.linearAcceleration.startLoggingAsync()
        default:
            assert(false, "Added a new sensor fusion output?")
        }
    }
    
    @IBAction func sensorFusionStopLogPressed(_ sender: Any) {
        sensorFusionStartLog.isEnabled = true
        sensorFusionStopLog.isEnabled = false
        sensorFusionStartStream.isEnabled = true
        sensorFusionMode.isEnabled = true
        sensorFusionOutput.isEnabled = true
        
        let hud = MBProgressHUD.showAdded(to: UIApplication.shared.keyWindow!, animated: true)
        hud.mode = .determinateHorizontalBar
        hud.label.text = "Downloading..."
        
        var task: BFTask<AnyObject>?
        let hudProgress: MetaWear.MBLFloatHandler = { number in
            hud.progress = number
        }
        
        switch sensorFusionOutput.selectedSegmentIndex {
        case 0:
            task = device.sensorFusion!.eulerAngle.downloadLogAndStopLoggingAsync(true, progressHandler: hudProgress).success { array in
                for obj in array as! [MBLEulerAngleData] {
                    self.sensorFusionGraph.addX(self.sensorFusionGraph.scale(obj.p, min: -180, max: 180), y: self.sensorFusionGraph.scale(obj.r, min: -90, max: 90), z: self.sensorFusionGraph.scale(obj.y, min: 0, max: 360))
                    self.sensorFusionData.append("\(obj.timestamp.timeIntervalSince1970),\(obj.p),\(obj.r),\(obj.y)\n".data(using: String.Encoding.utf8)!)
                }
            }
        case 1:
            task = device.sensorFusion!.quaternion.downloadLogAndStopLoggingAsync(true, progressHandler: hudProgress).success { array in
                for obj in array as! [MBLQuaternionData] {
                    self.sensorFusionGraph.addX(self.sensorFusionGraph.scale(obj.x, min: -1.0, max: 1.0), y: self.sensorFusionGraph.scale(obj.y, min: -1.0, max: 1.0), z: self.sensorFusionGraph.scale(obj.z, min: -1.0, max: 1.0))
                    self.sensorFusionData.append("\(obj.timestamp.timeIntervalSince1970),\(obj.x),\(obj.y),\(obj.z)\n".data(using: String.Encoding.utf8)!)
                }
            }
        case 2:
            task = device.sensorFusion!.gravity.downloadLogAndStopLoggingAsync(true, progressHandler: hudProgress).success { array in
                for obj in array as! [MBLAccelerometerData] {
                    self.sensorFusionGraph.addX(self.sensorFusionGraph.scale(obj.x, min: -1.0, max: 1.0), y: self.sensorFusionGraph.scale(obj.y, min: -1.0, max: 1.0), z: self.sensorFusionGraph.scale(obj.z, min: -1.0, max: 1.0))
                    self.sensorFusionData.append("\(obj.timestamp.timeIntervalSince1970),\(obj.x),\(obj.y),\(obj.z)\n".data(using: String.Encoding.utf8)!)
                }
            }
        case 3:
            task = device.sensorFusion!.linearAcceleration.downloadLogAndStopLoggingAsync(true, progressHandler: hudProgress).success { array in
                for obj in array as! [MBLAccelerometerData] {
                    self.sensorFusionGraph.addX(obj.x, y: obj.y, z: obj.z)
                    self.sensorFusionData.append("\(obj.timestamp.timeIntervalSince1970),\(obj.x),\(obj.y),\(obj.z)\n".data(using: String.Encoding.utf8)!)
                }
            }
        default:
            assert(false, "Added a new sensor fusion output?")
        }
        
        task?.success { array in
            hud.mode = .indeterminate
            hud.label.text! = "Clearing Log..."
            self.logCleanup { error in
                hud.hide(animated: true)
                if error != nil {
                    //self.connectDevice(false)
                }
            }
            }.failure { error in
                //self.connectDevice(false)
                hud.hide(animated: true)
        }
    }
    

    
    @IBAction func sensorFusionSendDataPressed(_ sender: Any) {
        send(sensorFusionData, title: "SensorFusion")
    }
    
}
