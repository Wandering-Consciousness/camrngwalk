// Copyright (c) 2017 Vault12, Inc.
// MIT License https://opensource.org/licenses/MIT
//
// Entropy generation screen

import UIKit
import AVFoundation
import Charts

extension String: Error {}

// convert byte array to Double
extension FloatingPoint {
    init?(_ bytes: [UInt8]) {
        guard bytes.count == MemoryLayout<Self>.size else { return nil }
        self = bytes.withUnsafeBytes {
            return $0.load(fromByteOffset: 0, as: Self.self)
        }
    }
}

class GenerationController: UIViewController, CameraFramesDelegate, UITableViewDataSource, UITableViewDelegate {
  var frames: CameraFrames?
  var ticker = 0
  var blockNumber = 0
  var timer = Timer()
  var defaults = UserDefaults.standard

  var cameraRadius: CGFloat = 0
  var cameraCenterY: CGFloat = 0

  @IBOutlet weak var overlay: UIImageView!
  @IBOutlet weak var overlayView: UIView!
  @IBOutlet weak var overlayStatus: UILabel!
  @IBOutlet weak var settingsTable: UITableView!

  var stats = ["TIME ELAPSED",
               "BYTES IN BUFFER",
               "ENTROPY GENERATED",
               "χ² OF LAST BLOCK",
               "REJECTED FRAMES",
               "OVERSATURATED"]
  
  // >> charts
  let chartView = LineChartView()
  var dataEntries = [ChartDataEntry]()
  var xValue: Double = 8
  var yValue: Double = 0
  
  enum Bit: UInt8, CustomStringConvertible {
      case zero, one

      var description: String {
          switch self {
          case .one:
              return "1"
          case .zero:
              return "0"
          }
      }
  }
  
  // << charts

  override func viewDidLoad() {
    super.viewDidLoad()

    // app should stay always active when entropy generation started
    UIApplication.shared.isIdleTimerDisabled = true

    cameraRadius = (self.view!.layer.bounds.width - 20) / 2
    cameraCenterY = (self.view!.layer.bounds.height - 250) / 2 - cameraRadius

    // fix layout for iPhone X
    if UIDevice().userInterfaceIdiom == .phone && UIScreen.main.nativeBounds.height == 2436 {
      cameraCenterY -= 16
    }

    settingsTable.dataSource = self
    settingsTable.delegate = self
    settingsTable.tableFooterView = UIView()
    
    addCameraLayer()

    // Don't update stats if there's no camera available
    if (AVCaptureDevice.devices(for: AVMediaType.video).count > 0) {
      timer = Timer.scheduledTimer(timeInterval: 0.2, target: self, selector: #selector(timerAction), userInfo: nil, repeats: true)
    }
    
    // >> graphs
    setupViews()
    setupInitialDataEntries()
    setupChartData()
  }
  
  // >> graphs https://medium.com/@denielwalker/the-easiest-way-to-build-real-time-chart-in-ios-fb25bbe35ba1
  override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
    Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(updateChartView), userInfo: nil, repeats: true)
  }

  
  func setupViews() {
      overlayView.addSubview(chartView)
      chartView.translatesAutoresizingMaskIntoConstraints = false
      chartView.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor).isActive = true
      chartView.centerYAnchor.constraint(equalTo: overlayView.centerYAnchor).isActive = true
      chartView.widthAnchor.constraint(equalToConstant: overlayView.frame.width - 32).isActive = true
      chartView.heightAnchor.constraint(equalToConstant: 300).isActive = true
  }
  
  func setupInitialDataEntries() {
      //(0..<Int(xValue)).forEach {
          //let dataEntry = ChartDataEntry(x: Double($0), y: 0)
          let dataEntry = ChartDataEntry(x: 8, y: 0)
          dataEntries.append(dataEntry)
      //}
  }
  
  func setupChartData() {
      // 1
      let chartDataSet = LineChartDataSet(entries: dataEntries, label: "Walk")
      chartDataSet.drawCirclesEnabled = false
      chartDataSet.setColor(NSUIColor.red)
      chartDataSet.mode = .linear
      
      // 2
      let chartData = LineChartData(dataSet: chartDataSet)
      chartView.data = chartData
      chartView.xAxis.labelPosition = .bottom
  }
  
  @objc func updateChartView() {
      chartView.notifyDataSetChanged()
      chartView.moveViewToX(self.dataEntries.last!.x)
  }

  private func addCameraLayer() {
    let cameraFrame = CGRect(x: 10, y: cameraCenterY,  width: cameraRadius * 2, height: cameraRadius * 2)

    if (AVCaptureDevice.devices(for: AVMediaType.video).count > 0) {
      // Show camera layer
      frames = CameraFrames(dlg:self)
      frames!.previewLayer!.frame = cameraFrame
      frames!.previewLayer!.cornerRadius = cameraRadius
      frames!.previewLayer!.videoGravity = AVLayerVideoGravity.resizeAspectFill
      self.view!.layer.addSublayer(frames!.previewLayer!)
    } else {
      // Emulate camera layer if camera is not accessible (simulator?)
      let coloredLayer = CALayer()
      coloredLayer.frame = cameraFrame
      coloredLayer.backgroundColor = Constants.mainColor.cgColor
      coloredLayer.opacity = 0.3
      coloredLayer.cornerRadius = cameraRadius
      self.view!.layer.addSublayer(coloredLayer)
    }
    overlayView.superview?.bringSubviewToFront(overlayView)

    // Circular upload progress bar
    let circleLayer = CAShapeLayer()
    circleLayer.path = progressPath(0)
    circleLayer.strokeColor = Constants.mainColor.cgColor
    circleLayer.fillColor = UIColor.clear.cgColor
    circleLayer.lineWidth = 4
    self.view!.layer.addSublayer(circleLayer)

    // Rotating image on center
    let animation = CABasicAnimation(keyPath: "transform.rotation")
    animation.fromValue = 0
    animation.toValue = CGFloat.pi * 2
    animation.duration = Constants.spinnerAnimationDuration
    animation.repeatCount = .infinity
    animation.isRemovedOnCompletion = false
    overlay.layer.add(animation, forKey: "spinAnimation")
  }

  func localized(_ val: Int) -> String {
    return NumberFormatter.localizedString(from: NSNumber(value: val), number: NumberFormatter.Style.decimal)
  }

  @objc func timerAction() {
    ticker += 1

    // Text animation
    let animation: CATransition = CATransition()
    animation.duration = 0.1
    animation.type = CATransitionType.fade
    animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)

    for i in 0..<stats.count {
      settingsTable.cellForRow(at: IndexPath(row: i, section: 0))?.layer.add(animation, forKey: "changeTextTransition")
    }

    let ext = self.frames?.extractor
    let col = self.frames?.collector

    // Row 0: Time elapsed
    updateValue(row: 0, val: String(format: "%02i:%02i", ticker / 5 / 60, ticker / 5 % 60))

    // Row 1: Bytes in buffer
    updateValue(row: 1, val: localized(ext!.pos))

    // Row 2: Bytes generated
    updateValue(row: 2, val: localized(col!.totalGenerated))

    // Row 3: χ²
    if col!.lastChi > 0 {
      updateValue(row: 3, val: String(format:"%.2f",  col!.lastChi))
    }

    // Highlight if χ² is over limit
    let x2valueLabel = self.settingsTable.cellForRow(at: IndexPath(row: 3, section: 0))?.detailTextLabel
    if defaults.bool(forKey: "x2_limit_enabled") && (col!.lastChi > defaults.double(forKey: "x2_limit")) {
      x2valueLabel?.textColor = Constants.warningColor
    } else {
      x2valueLabel?.textColor = Constants.mainColor
    }

    // Row 4: Number of frames we reject due to too high mean (i.e camera movement)
    updateValue(row: 4, val: localized(col!.rejectedFrames))

    // Row 5: Corrupt pixels
    updateValue(row: 5, val: String(format:"%.2f%%",  col!.corruptPixels))
    
    // Update the 2D graph with random walk results
    if (col!.blockReady()) {
      update2DWalkGraph()
    }
  }

  func bytesConvertToHexstring(byte : [UInt8]) -> String {
      var string = ""
      
      for val in byte {
          //getBytes(&byte, range: NSMakeRange(i, 1))
          string = string + String(format: "%02x", val)
      }
      
      return string
  }
  
  func uploadEntropyOLD(entropy: [UInt8], blockNumber: Int) {
    self.blockNumber = blockNumber
    let timestamp = Int64(NSDate().timeIntervalSince1970)

    // Update circular progress bar, if we are not in unlimited generation mode
    if !defaults.bool(forKey: "block_amount_unlimited") {
      DispatchQueue.main.async {
        let percentage = CGFloat(blockNumber) / CGFloat(self.defaults.integer(forKey: "block_amount"))
        let progressLayer = self.view!.layer.sublayers?[(self.view!.layer.sublayers?.count)!-1] as? CAShapeLayer
        progressLayer?.path = self.progressPath(percentage)
      }
    }

    // Upload block to Zax relay, if in Network mode
    if defaults.string(forKey: "delivery") == "network" {
      do {
        let isLastBlock = !defaults.bool(forKey: "block_amount_unlimited") && (blockNumber == defaults.integer(forKey: "block_amount"))
        if isLastBlock {
          updateStatus("FINISHING UPLOAD")
        }
        /*soliax
        try GlowLite.shared.sendFile(keyTo: defaults.string(forKey: "recipient")!,
        file: entropy,
        name: "TE_block\(blockNumber)_\(timestamp).bin") {
          (res) -> () in
          if isLastBlock {
            self.closeView()
          }
        }
         */
      } catch {
        print("Network error")
      }

      return
    }

    // Otherwise, stop generation and prepare for airdrop
    updateStatus("WRITING BLOCK \(blockNumber)")
    frames?.session?.stopRunning()

    let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    var files = [URL]()

    if defaults.bool(forKey: "upload_csv") {
      let f = NSMutableString(capacity: entropy.count * 50)
      // Use "Bins" column with Excel Histogram function
      f.append("Values,Bins\n")
      for i in 0 ..< entropy.count {
        f.append(String(entropy[i]))
        if i<256 { f.append(",\(i)") }
        f.append("\n")
      }
      let path1 = dir.appendingPathComponent("TE_block\(blockNumber)_\(timestamp).csv")
      do {
        try f.write(to: path1, atomically: false, encoding: String.Encoding.ascii.rawValue)
        files.append(path1)
      }
      catch {/* error handling here */}
    }

    let path2 = dir.appendingPathComponent("TE_block\(blockNumber)_\(timestamp).bin")
    FileManager.default.createFile(atPath: path2.path, contents: Data(bytes: entropy), attributes: nil)
    files.append(path2)

    // AirDrop the files
    let controller  = UIActivityViewController(activityItems: files, applicationActivities: nil)
    controller.popoverPresentationController?.sourceView = self.view
    controller.completionWithItemsHandler = doneSharingHandler
    controller.excludedActivityTypes = [.postToTwitter, .saveToCameraRoll ,.postToFacebook, .postToWeibo, .message, .mail, .print, .copyToPasteboard, .assignToContact, .saveToCameraRoll, .addToReadingList, .postToFlickr, .postToVimeo, .postToTencentWeibo]
    self.present(controller, animated: true)
  }

  func doneSharingHandler(activityType: UIActivity.ActivityType?, shared: Bool, items: [Any]?, error: Error?) {
    if !defaults.bool(forKey: "block_amount_unlimited") && (self.blockNumber == defaults.integer(forKey: "block_amount")) {
      self.closeView()
    } else {
      self.updateStatus("GENERATING ENTROPY")
      self.frames?.session?.startRunning()
    }
  }

  func progressPath(_ percentage: CGFloat) -> CGPath {
    return UIBezierPath(arcCenter: CGPoint(x: 10 + self.cameraRadius, y: self.cameraCenterY + self.cameraRadius),
                        radius: self.cameraRadius - 2, startAngle: -CGFloat.pi / 2.0,
                        endAngle: -CGFloat.pi / 2.0 + (CGFloat.pi * 2.0 * percentage), clockwise: true).cgPath
  }

  func updateStatus(_ status: String) {
    DispatchQueue.main.async {
      self.overlayStatus.text = status
    }
  }

  func updateValue(row: Int, val: String) {
    if val == "0" { return }
    DispatchQueue.main.async {
      self.settingsTable.cellForRow(at: IndexPath(row: row, section: 0))?.detailTextLabel?.text = val
    }
  }
  
  func update2DWalkGraph() {
      // soliax - was crashing here trying to call main UI thread from background thread
      DispatchQueue.main.async {
        let col = self.frames?.collector
        let entropy: [UInt8] = col!.getEntropy()
        let bounds: Double = 8
        let step: Double = 0.1

        // 2d random walk
        for i in 0..<entropy.count {
           var byte = entropy[i]

           for _ in 0..<4 {
               // x-dimension
               var currentBit = byte & 0x01
              if currentBit != 0 && self.xValue < bounds {
                self.xValue += step
  //                print("xValue++ \(self.xValue)")
               } else if self.xValue > -bounds {
                self.xValue -= step
  //                print("xValue-- \(self.xValue)")
               }
               byte >>= 1

               // y-dimension
              currentBit = byte & 0x01
              if currentBit != 0 && self.yValue < bounds {
                self.yValue += step
  //               print("yValue++ \(self.yValue)")
                } else if self.yValue > -bounds {
                self.yValue -= step
  //               print("yValue-- \(self.yValue)")
              }
              byte >>= 1

              let newDataEntry = ChartDataEntry(x: self.xValue,
                                                y: self.yValue)
              self.dataEntries.append(newDataEntry)
              self.chartView.data?.addEntry(newDataEntry, dataSetIndex: 0)
           }
        }
      }
  }
  // << graphs

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = settingsTable.dequeueReusableCell(withIdentifier: "keyValue")!
    cell.detailTextLabel?.text = " "
    cell.textLabel?.text = stats[indexPath.row]
    return cell
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { return stats.count }
  func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { return 40 }
  func numberOfSections(in tableView: UITableView) -> Int { return 1 }

  @IBAction func closeClicked(_ sender: Any) {
    frames?.session?.stopRunning()
    self.closeView()
  }

  func closeView() {
    self.performSegue(withIdentifier: "backToSettings", sender: self)
    self.dismiss(animated: false, completion: nil)
  }
}
