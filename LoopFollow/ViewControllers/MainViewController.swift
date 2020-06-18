//
//  FirstViewController.swift
//  LoopFollow
//
//  Created by Jon Fawcett on 6/1/20.
//  Copyright © 2020 Jon Fawcett. All rights reserved.
//

import UIKit
import Charts
import EventKit


class MainViewController: UIViewController, UITableViewDataSource, ChartViewDelegate {
    
    @IBOutlet weak var BGText: UILabel!
    @IBOutlet weak var DeltaText: UILabel!
    @IBOutlet weak var DirectionText: UILabel!
    @IBOutlet weak var BGChart: LineChartView!
    @IBOutlet weak var BGChartFull: LineChartView!
    @IBOutlet weak var MinAgoText: UILabel!
    @IBOutlet weak var infoTable: UITableView!
    @IBOutlet weak var Console: UITableViewCell!
    @IBOutlet weak var DragBar: UIImageView!
    @IBOutlet weak var PredictionLabel: UILabel!
    @IBOutlet weak var LoopStatusLabel: UILabel!
    
    //NS BG Struct
    struct sgvData: Codable {
        var sgv: Int
        var date: TimeInterval
        var direction: String?
    }
    
    //NS Cage Struct
    struct cageData: Codable {
        var created_at: String
    }
    
    //NS Basal Profile Struct
    struct basalProfileStruct: Codable {
        var value: Double
        var time: String
        var timeAsSeconds: Double
    }
    
    //NS Basal Data  Struct
    struct basalGraphStruct: Codable {
        var basalRate: Double
        var date: TimeInterval
    }
    
    //NS Bolus Data  Struct
    struct bolusCarbGraphStruct: Codable {
        var value: Double
        var date: TimeInterval
        var sgv: Int
    }
    
    // Data Table Struct
    struct infoData {
        var name: String
        var value: String
    }

    // Variables for BG Charts
    public var numPoints: Int = 13
    public var linePlotData: [Double] = []
    public var linePlotDataTime: [Double] = []
    var firstGraphLoad: Bool = true
    var firstBasalGraphLoad: Bool = true
    var minAgoBG: Double = 0.0
    var currentOverride = 1.0
    
    // Vars for NS Pull
    var graphHours:Int=24
    var mmol = false as Bool
    var urlUser = UserDefaultsRepository.url.value as String
    var token = UserDefaultsRepository.token.value as String
    var defaults : UserDefaults?
    let consoleLogging = true
    var timeofLastBGUpdate = 0 as TimeInterval
    
    var backgroundTask = BackgroundTask()
    
    // Refresh NS Data
    var timer = Timer()
    // check every 30 Seconds whether new bgvalues should be retrieved
    let timeInterval: TimeInterval = 30.0
    
    // View Delay Timer
    var viewTimer = Timer()
    let viewTimeInterval: TimeInterval = 5.0
    
    // Check Alarms Timer
    // Don't check within 1 minute of alarm triggering to give the snoozer time to save data
    var checkAlarmTimer = Timer()
    var checkAlarmInterval: TimeInterval = 60.0
    
    // Info Table Setup
    var tableData = [
        infoData(name: "IOB", value: ""), //0
        infoData(name: "COB", value: ""), //1
        infoData(name: "Basal", value: ""), //2
        infoData(name: "Override", value: ""), //3
        infoData(name: "Battery", value: ""), //4
        infoData(name: "Pump", value: ""), //5
        infoData(name: "SAGE", value: ""), //6
        infoData(name: "CAGE", value: "") //7
    ]
    
    var bgData: [sgvData] = []
    var basalProfile: [basalProfileStruct] = []
    var basalData: [basalGraphStruct] = []
    var bolusData: [bolusCarbGraphStruct] = []
    var carbData: [bolusCarbGraphStruct] = []
    var predictionData: [Double] = []
    var chartData = LineChartData()
    var newBGPulled = false
    
    // calendar setup
    let store = EKEventStore()
    
    var snoozeTabItem: UITabBarItem = UITabBarItem()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        BGChart.delegate = self
        
        if UserDefaultsRepository.forceDarkMode.value {
            overrideUserInterfaceStyle = .dark
            self.tabBarController?.overrideUserInterfaceStyle = .dark
        }
        // Disable the snoozer tab unless an alarm is active
        let tabBarControllerItems = self.tabBarController?.tabBar.items
        if let arrayOfTabBarItems = tabBarControllerItems as AnyObject as? NSArray{
            snoozeTabItem = arrayOfTabBarItems[2] as! UITabBarItem
        }
        snoozeTabItem.isEnabled = false;
        
        
        // Trigger foreground and background functions
        let notificationCenter = NotificationCenter.default
            notificationCenter.addObserver(self, selector: #selector(appMovedToBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
            notificationCenter.addObserver(self, selector: #selector(appCameToForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        
        //Bind info data
        infoTable.rowHeight = 25
        infoTable.dataSource = self
        
        // Load Data
        if UserDefaultsRepository.url.value != "" {
            nightscoutLoader()
        } 
    }
    
    override func viewWillAppear(_ animated: Bool) {
        // set screen lock
        UIApplication.shared.isIdleTimerDisabled = UserDefaultsRepository.screenlockSwitchState.value;
        
    }
    
    
    // Info Table Functions
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return tableData.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "LabelCell", for: indexPath)
        let values = tableData[indexPath.row]
        cell.textLabel?.text = values.name
        cell.detailTextLabel?.text = values.value
        return cell
    }
    
    
    // NS Loader Timer
    fileprivate func startTimer(time: TimeInterval) {
        timer = Timer.scheduledTimer(timeInterval: time,
                                     target: self,
                                     selector: #selector(MainViewController.timerDidEnd(_:)),
                                     userInfo: nil,
                                     repeats: true)
    }
    
    // Check Alarm Timer
    func startCheckAlarmTimer(time: TimeInterval) {
        checkAlarmTimer = Timer.scheduledTimer(timeInterval: time,
                                     target: self,
                                     selector: #selector(MainViewController.checkAlarmTimerDidEnd(_:)),
                                     userInfo: nil,
                                     repeats: false)
    }
    
    // NS Loader Timer
     func startViewTimer(time: TimeInterval) {
        timer = Timer.scheduledTimer(timeInterval: time,
                                     target: self,
                                     selector: #selector(MainViewController.viewTimerDidEnd(_:)),
                                     userInfo: nil,
                                     repeats: true)
    }
    
    // Check for new data when timer ends
       @objc func viewTimerDidEnd(_ timer:Timer) {
           if bgData.count > 0 {
               self.clearOldSnoozes()
                self.checkAlarms(bgs: bgData)
                self.updateMinAgo()
                self.updateBadge()
               self.viewUpdateNSBG()
               if UserDefaultsRepository.writeCalendarEvent.value {
                   self.writeCalendar()
               }
               self.createGraph()
           }
       }
    
    // Nothing should be done when this timer ends because it just blocks the alarms from firing when it's active
    @objc func checkAlarmTimerDidEnd(_ timer:Timer) {
        print("check alarm timer ended")
    }
    
    @objc func appMovedToBackground() {
        // Allow screen to turn off
        UIApplication.shared.isIdleTimerDisabled = false;
        
        // We want to always come back to the home screen
        tabBarController?.selectedIndex = 0
        
        // Cancel the current timer and start a fresh background timer using the settings value only if background task is enabled
        timer.invalidate()
        if UserDefaultsRepository.backgroundRefresh.value {
            timer.invalidate()
            backgroundTask.startBackgroundTask()
            let refresh = UserDefaultsRepository.backgroundRefreshFrequency.value * 60
            startTimer(time: TimeInterval(refresh))
        }
    }

    @objc func appCameToForeground() {
        // reset screenlock state if needed
        UIApplication.shared.isIdleTimerDisabled = UserDefaultsRepository.screenlockSwitchState.value;
        
        // Cancel the background tasks, start a fresh timer, and immediately check for new data
        if UserDefaultsRepository.backgroundRefresh.value {
            backgroundTask.stopBackgroundTask()
            timer.invalidate()
        }
        startTimer(time: timeInterval)
    }
    
    // Check for new data when timer ends
    @objc func timerDidEnd(_ timer:Timer) {
        print("timer ended")
        nightscoutLoader()
    }

    //update Min Ago Text. We need to call this separately because it updates between readings
    func updateMinAgo(){
        let deltaTime = (TimeInterval(Date().timeIntervalSince1970)-bgData[bgData.count - 1].date) / 60
        minAgoBG = Double(TimeInterval(Date().timeIntervalSince1970)-bgData[bgData.count - 1].date)
        MinAgoText.text = String(Int(deltaTime)) + " min ago"
    }
    
    //Clear the info data before next pull. This ensures we aren't displaying old data if something fails.
    func clearLastInfoData(){
        for i in 0..<tableData.count{
            tableData[i].value = ""
        }
    }

    func stringFromTimeInterval(interval: TimeInterval) -> String {
        let interval = Int(interval)
        let minutes = (interval / 60) % 60
        let hours = (interval / 3600)
        return String(format: "%02d:%02d", hours, minutes)
    }

    
    
    func updateBadge() {
        let entries = bgData
        if entries.count > 0 && UserDefaultsRepository.appBadge.value {
            let latestBG = entries[entries.count - 1].sgv
            UIApplication.shared.applicationIconBadgeNumber = latestBG
        } else {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
        print("updated badge")
    }
    
    

    func setBGTextColor() {
        let latestBG = bgData[bgData.count - 1].sgv
        if UserDefaultsRepository.colorBGText.value {
            if latestBG >= UserDefaultsRepository.highLine.value {
                BGText.textColor = NSUIColor.systemYellow
            } else if latestBG <= UserDefaultsRepository.lowLine.value {
                BGText.textColor = NSUIColor.systemRed
            } else {
                BGText.textColor = NSUIColor.systemGreen
            }
        } else {
            BGText.textColor = NSUIColor.label
        }
        
    }
    
    func bgOutputFormat(bg: Double, mmol: Bool) -> String {
        if !mmol {
            return String(format:"%.0f", bg)
        }
        else
        {
            return String(format:"%.1f", bg / 18.0)
        }
    }
    
    func bgDirectionGraphic(_ value:String)->String
    {
        let //graphics:[String:String]=["Flat":"\u{2192}","DoubleUp":"\u{21C8}","SingleUp":"\u{2191}","FortyFiveUp":"\u{2197}\u{FE0E}","FortyFiveDown":"\u{2198}\u{FE0E}","SingleDown":"\u{2193}","DoubleDown":"\u{21CA}","None":"-","NOT COMPUTABLE":"-","RATE OUT OF RANGE":"-"]
        graphics:[String:String]=["Flat":"→","DoubleUp":"↑↑","SingleUp":"↑","FortyFiveUp":"↗","FortyFiveDown":"↘︎","SingleDown":"↓","DoubleDown":"↓↓","None":"-","NOT COMPUTABLE":"-","RATE OUT OF RANGE":"-"]
        
        
        return graphics[value]!
    }
    
    // Write calendar
    func writeCalendar() {
        store.requestAccess(to: .event) {(granted, error) in
        if !granted { return }
            
        // Create Event info
            let deltaBG = self.bgData[self.bgData.count - 1].sgv -  self.bgData[self.bgData.count - 2].sgv as Int
            let deltaTime = (TimeInterval(Date().timeIntervalSince1970) - self.bgData[self.bgData.count - 1].date) / 60
            var deltaString = ""
            if deltaBG < 0 {
                deltaString = String(deltaBG)
            }
            else
            {
                deltaString = "+" + String(deltaBG)
            }
            let direction = self.bgDirectionGraphic(self.bgData[self.bgData.count - 1].direction ?? "")

            var eventStartDate = Date(timeIntervalSince1970: self.bgData[self.bgData.count - 1].date)
            var eventEndDate = eventStartDate.addingTimeInterval(60 * 10)
            var  eventTitle = UserDefaultsRepository.watchLine1.value + "\n" + UserDefaultsRepository.watchLine2.value
            eventTitle = eventTitle.replacingOccurrences(of: "%BG%", with: String(self.bgData[self.bgData.count - 1].sgv))
            eventTitle = eventTitle.replacingOccurrences(of: "%DIRECTION%", with: direction)
            eventTitle = eventTitle.replacingOccurrences(of: "%DELTA%", with: deltaString)
            if self.currentOverride != 1.0 {
                let val = Int( self.currentOverride*100)
               // let overrideText = String(format:"%f1", self.currentOverride*100)
                let text = String(val) + "%"
                eventTitle = eventTitle.replacingOccurrences(of: "%OVERRIDE%", with: text)
            } else {
                eventTitle = eventTitle.replacingOccurrences(of: "%OVERRIDE%", with: "")
            }
            var minAgo = ""
            if deltaTime > 9 {
                // write old BG reading and continue pushing out end date to show last entry
                minAgo = String(Int(deltaTime)) + " min"
                eventEndDate = eventStartDate.addingTimeInterval((60 * 10) + (deltaTime * 60))
            }
            var cob = "0"
            if self.tableData[1].value != "" {
                cob = self.tableData[1].value
            }
            var basal = "~"
            if self.tableData[2].value != "" {
                basal = self.tableData[2].value
            }
            var iob = "0"
            if self.tableData[0].value != "" {
                iob = self.tableData[0].value
            }
            eventTitle = eventTitle.replacingOccurrences(of: "%MINAGO%", with: minAgo)
            eventTitle = eventTitle.replacingOccurrences(of: "%IOB%", with: iob)
            eventTitle = eventTitle.replacingOccurrences(of: "%COB%", with: cob)
            eventTitle = eventTitle.replacingOccurrences(of: "%BASAL%", with: basal)
            
            
            
        // Delete Last Event
            let eventToRemove = self.store.event(withIdentifier: UserDefaultsRepository.savedEventID.value)
            if eventToRemove != nil {
                do {
                    try self.store.remove(eventToRemove!, span: .thisEvent, commit: true)
                } catch {
                    // Display error to user
                }
            }
        // Write New Event
            var event = EKEvent(eventStore: self.store)
            event.title = eventTitle
            event.startDate = eventStartDate
            event.endDate = eventEndDate
            event.calendar = self.store.calendar(withIdentifier: UserDefaultsRepository.calendarIdentifier.value)
            do {
                try self.store.save(event, span: .thisEvent, commit: true)
                UserDefaultsRepository.savedEventID.value = event.eventIdentifier //save event id to access this particular event later
            } catch {
                // Display error to user
                print(error)
            }
        }
    }
    
    
    func persistentNotification(bgTime: TimeInterval)
    {
        if UserDefaultsRepository.persistentNotification.value && bgTime > UserDefaultsRepository.persistentNotificationLastBGTime.value {
            guard let snoozer = self.tabBarController!.viewControllers?[2] as? SnoozeViewController else { return }
            snoozer.sendNotification(self, bgVal: BGText.text ?? "", directionVal: DirectionText.text ?? "", deltaVal: DeltaText.text ?? "", minAgoVal: MinAgoText.text ?? "", alertLabelVal: "Latest BG")
        }
    }
    
}

