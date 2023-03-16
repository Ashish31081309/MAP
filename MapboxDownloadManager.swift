//
//  MapBoxDownloadManager.swift
//  GeolocationApp
//

import Foundation
import MapboxMaps
import CoreLocation

protocol MapboxDownloadManagerDelegate: AnyObject {
  func mapboxDownloadManager(_ manager: MapboxDownloadManager,
                             didStartDownloadWith downloadInfo: GLADownloadInfo)
  func mapboxDownloadManager(_ manager: MapboxDownloadManager,
                             didFinishDownloadWith downloadInfo: GLADownloadInfo,
                             successfully: Bool, error: Error?)
  func mapboxDownloadManager(_ manager: MapboxDownloadManager,
                             didChangeProgress progress: Float,
                             downloadInfo: GLADownloadInfo)
  
  func mapboxDownloadManagerForTour(_ manager: MapboxDownloadManager,
                                    didStartDownloadWith downloadInfo: GLADownloadInfo, tour : GLATourButton)
  func mapboxDownloadManagerForTour(_ manager: MapboxDownloadManager,
                                    didFinishDownloadWith downloadInfo: GLADownloadInfo,
                                    successfully: Bool, error: Error?, tour: GLATourButton)
  func mapboxDownloadManagerForTour(_ manager: MapboxDownloadManager,
                                    didChangeProgress progress: Float,
                                    downloadInfo: GLADownloadInfo, tour: GLATourButton)
}

@objc class MapboxDownloadManager: NSObject {
  
  // MARK: - Shared instance
  
    @objc static let shared = MapboxDownloadManager()
    
    private var offlineManager: OfflineManager?
    private var tileStore: TileStore?

  // MARK: - Properties
  
  weak var delegate: MapboxDownloadManagerDelegate?
  
  // Public
   @objc let styleURL = URL(string: "mapbox://styles/tnrfowers/cjcb70z4i115w2roio5433u6x")
// @objc let styleURL = URL(string: "mapbox://styles/mapbox/streets-v12")

  @objc var isOfflineMapsDownloaded: Bool {
    return true
    /*if self.appSettings?.isOfflineMapsDownloadedValue ?? false {
      return true
    } else {
      return false
    }*/
  }
  
  private var isDownloading: Bool = false
    
  var arrTourButtons = [GLATourButton]()
  
//   private var pack: MGLOfflinePack?
  
  private var lastBytesWritten: UInt64 = 0
  
//  private var downloadInfo : GLADownloadInfo?
    
  // MARK: - Init
  
  override init() {
    super.init()
    let tileStore = TileStore.default
    let accessToken = ResourceOptionsManager.default.resourceOptions.accessToken
    tileStore.setOptionForKey(TileStoreOptions.mapboxAccessToken, value: accessToken)
    self.tileStore = tileStore
  }
  
  deinit {
      NotificationCenter.default.removeObserver(self)
      tileStore = nil
  }
  
    @objc func migrateOfflineCache() {
            // Old and new cache file paths
            let srcURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("/Library/Application Support/com.shakaguide.combined/.mapbox/cache.db")

            let destURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("/Library/Application Support/.mapbox/map_data/map_data.db")

            let fileManager = FileManager.default

            do {
                try fileManager.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                try fileManager.moveItem(at: srcURL, to: destURL)
                print("Move successful")
            } catch {
                print("Error: \(error.localizedDescription)")
            }
        }
    
  // MARK: - Download

    func createDownloadInfoIslandMap () -> GLADownloadInfo {
        let downloadInfo = GLADownloadInfo.mr_createEntity()
        downloadInfo?.progressValue = 0
        downloadInfo?.stateValue = .downloading
        downloadInfo?.languageCode = GLALanguage.getCode()
        downloadInfo?.typeValue = .maps
        return downloadInfo!
    }
    
    func  downloadOfflineMapsForIsland(appCSettings: GLAAppSettings? = nil) {
        guard var appSetting = appCSettings else {
            return
        }
        
        // appSetting.dataset_id_app = "cl9dxio4g041b22ocoo4pw4bq"
       // guard !isDownloading, pack == nil else { return }
        
        if appSetting.downloadInfo == nil {
            appSetting.downloadInfo = createDownloadInfoIslandMap()
        }
//        downloadInfo = appSetting.downloadInfo
        guard appSetting.islandBoundingBox != nil else {
            finishDownload(appSettings: appCSettings, successfully: false, error: nil)
            return
        }
        TextLog.singletonInstance.write("downloadOfflineMapsForIsland: Started baseline map download with datasetid \(appSetting.dataset_id_app ?? "")")
        
        delegate?.mapboxDownloadManager(self, didStartDownloadWith: appSetting.downloadInfo!)
    
        
//         GLAWebClient.sharedInstance()?.getDataSet(fromID: appSetting.dataset_id_app as String?, completion: { (geoJsonDict, minZoom, maxZoom) in

           // print(minZoom, maxZoom)
             
             var minZoom = Double(truncating: appSetting.minZoom ?? 0)
             var maxZoom = Double(truncating: appSetting.maxZoom ?? 10)
             
             guard let latitude = appSetting.globalBoundingBox?.topLeftLatitude?.doubleValue,
                   let longitude = appSetting.globalBoundingBox?.bottomRightLongitude?.doubleValue else {
               print("tourPreview lat and long missing")
               return
             }
        
           // let location = CLLocation(latitude: CLLocationDegrees(36.191101), longitude: CLLocationDegrees(-115.438341))
        
             let location = CLLocation(latitude: CLLocationDegrees(latitude), longitude: CLLocationDegrees(longitude))
             let coordinate = location.coordinate
             
             guard let regionId = appSetting.dataset_id_app as? String else {
               return
             }
             
             let userInfo = ["name": "Offline Pack", "appID": appSetting.appContent?.destination?.appId?.description ?? ""]

             self.downloadTileRegions(coordinate, regionId, userInfo, minZoom, maxZoom, appSetting)

            /* guard let geoJsonDict = geoJsonDict else {
                return
            }
            
            TextLog.singletonInstance.write("Baseline geojson data for datasetid \(String(describing: appSetting.dataset_id_app))")
            
            self.isDownloading = true
            self.lastBytesWritten = 0
            
            let data = try! JSONSerialization.data(withJSONObject: geoJsonDict, options: .prettyPrinted)
            
             let feature = try! MGLShape(data: data, encoding: String.Encoding.utf8.rawValue) as! MGLShapeCollectionFeature
            
             let poly: MGLPolygonFeature = feature.shapes[0] as! MGLPolygonFeature
            
             let region: MGLOfflineRegion = MGLShapeOfflineRegion(styleURL: self.styleURL, shape: poly, fromZoomLevel: appSetting.minMapZoomValue, toZoomLevel: appSetting.maxMapZoomValue)
            
             let userInfo = ["name": "Offline Pack", "appID": appSetting.appContent?.destination?.appId?.description ?? ""]
            
             guard let context = try? NSKeyedArchiver.archivedData(withRootObject: userInfo, requiringSecureCoding: false) else {
                return
            }

            MGLOfflineStorage.shared.addPack(for: region, withContext: context) { (pack, error) in
                if let error = error {
                    print("Error: \(error.localizedDescription )")
                    self.finishDownload(appSettings: appSetting, successfully: false, error: error)
                } else {
                    pack?.resume()
                    self.pack = pack
                }
            } */
//        })
    }
  
  func createDownloadInfoForTour(tour: GLATourButton) -> GLADownloadInfo {
    var downloadInfoTour = tour.downloadInfoMap
    if downloadInfoTour == nil {
      downloadInfoTour = GLADownloadInfo.mr_createEntity()
    }
    downloadInfoTour?.progressValue = 0
    downloadInfoTour?.stateValue = .downloading
    downloadInfoTour?.typeValue = .maps
    downloadInfoTour?.tourMap = tour
    downloadInfoTour?.languageCode = GLALanguage.getCode()
    return downloadInfoTour!
  }
  
  func downloadOfflineMapsForTour(tourBtn: GLATourButton) {
        // var tourBtn = tourBtn
        // tourBtn.dataset_id_tour = "cl9dxio4g041b22ocoo4pw4bq"
        tourBtn.isOfflineMapsDownloading = true
        arrTourButtons.append(tourBtn)
        tourBtn.downloadInfoMap = self.createDownloadInfoForTour(tour: tourBtn)
        tourBtn.downloadInfoMap?.managedObjectContext?.mr_saveToPersistentStoreAndWait()
        tourBtn.managedObjectContext?.mr_saveToPersistentStoreAndWait()

        if tourBtn.downloadInfoMap != nil {
          delegate?.mapboxDownloadManagerForTour(self, didStartDownloadWith: tourBtn.downloadInfoMap!, tour: tourBtn)
        }

        let tourButtonsWithSameId = self.getAllToursForSameDataSetIdOtherThan(tourBtn: tourBtn)

        for tour in tourButtonsWithSameId {
          tour.isOfflineMapsDownloading = true
          tour.managedObjectContext?.mr_saveToPersistentStoreAndWait()
        }
        TextLog.singletonInstance.write("downloadOfflineMapsForTour: Map download start for Tour \(tourBtn.title ?? "unknown") with datasetid \(tourBtn.dataset_id_tour ?? "")")

            let minZoom = tourBtn.minZoomValue
            let maxZoom = tourBtn.maxZoomValue
           /* guard let latitude = tourBtn.tourMenu?.tourPreview?.mapLat?.doubleValue,
                let longitude = tourBtn.tourMenu?.tourPreview?.mapLong?.doubleValue else {
              print("Download offline pack - appContent - tourPreview lat and long missing")
              return
            }
            
            guard let appContent = tourBtn.drivingTab?.appContent,
                  let latitude = appSetting.globalBoundingBox?.topLeftLatitude?.doubleValue,
                  let longitude = appSetting.globalBoundingBox?.bottomRightLongitude?.doubleValue else {
              print("Download offline pack - appContent - tourPreview lat and long missing")
              return
            } */
            
            guard let appContent = tourBtn.drivingTab?.appContent,
                  let coordinate = appContent.settings?.islandBoundingBox?.northwest else {
                  // let longitude = appContent.settings?.islandBoundingBox?.southeast else {
                    print("Download offline pack - appContent - tourPreview lat and long missing")
                return
            }
            
//            let location = CLLocation(latitude: CLLocationDegrees(19.8968), longitude: CLLocationDegrees(155.5828))
//            let coordinate = location.coordinate
            // let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            guard let regionId = tourBtn.dataset_id_tour as? String, let tourId = tourBtn.tourID  else {
              return
            }
            let userInfo = ["name": "Offline Pack", "tourId": tourId] as [String: Any]
            self.downloadTileRegions(coordinate, regionId, userInfo, minZoom, maxZoom, tourBtn)
    }
    
    private func downloadTileRegions(_ coord: CLLocationCoordinate2D, _ tileRegionId: String, _ userInfo: [String: Any], _ minZoom: Double, _ maxZoom: Double, _ obj: Any) {
        guard let tileStore = tileStore else {
            print("tileStore missing")
            preconditionFailure()
        }
        let dispatchGroup = DispatchGroup()
        guard let url = MapboxDownloadManager.shared.styleURL, let styleURI = StyleURI(url: url) else {
            return
        }
        // 1. Create style package with loadStylePack() call.
        let stylePackLoadOptions = StylePackLoadOptions(glyphsRasterizationMode: .noGlyphsRasterizedLocally,
                                                        metadata: ["tag": "my-outdoors-style-pack"],
                                                        acceptExpired: true)!

        dispatchGroup.enter()
        _ = offlineManager?.loadStylePack(for: styleURI, loadOptions: stylePackLoadOptions) { [weak self] progress in
            // These closures do not get called from the main thread. In this case
            DispatchQueue.main.async {
                print(" progress completedResourceCount/ - requiredResourceCount \(progress.completedResourceCount) / \(progress.requiredResourceCount)")
                print("StylePack = \(progress)")
            }

        } completion: { [weak self] result in
            DispatchQueue.main.async {
                defer {
                    dispatchGroup.leave()
                }

                switch result {
                case let .success(stylePack):
                    print("StylePack = \(stylePack)")

                case let .failure(error):
                    print("stylePack download Error = \(error)")
                }
            }
        }

        // 2. Create an offline region with tiles for the outdoors style
        let outdoorsOptions = TilesetDescriptorOptions(styleURI: styleURI.rawValue, minZoom: UInt8(minZoom), maxZoom: UInt8(maxZoom), stylePack: stylePackLoadOptions)
        let accessToken = ResourceOptionsManager.default.resourceOptions.accessToken
        offlineManager = OfflineManager(resourceOptions: ResourceOptions(accessToken: accessToken,
                                                                             tileStore: tileStore))
        guard let outdoorsDescriptor = offlineManager?.createTilesetDescriptor(for: outdoorsOptions) else {
            print("outdoorsDescriptor -> missing")
            return
        }
        // Load the tile region
        let tileRegionLoadOptions = TileRegionLoadOptions(
            geometry: .point(Point(coord)),
            descriptors: [outdoorsDescriptor],
            metadata: userInfo,
            acceptExpired: true)!

        // Use the the default TileStore to load this region. You can create
        // custom TileStores are are unique for a particular file path, i.e.
        // there is only ever one TileStore per unique path.
        dispatchGroup.enter()
        _ = tileStore.loadTileRegion(forId: tileRegionId, loadOptions: tileRegionLoadOptions) { progress in
            // These closures do not get called from the main thread. In this case
            // we're updating the UI, so it's important to dispatch to the main
            // queue.
            DispatchQueue.main.async {
                // Update the progress bar
                print("Download progress : ")
                print(Float(progress.completedResourceCount) / Float(progress.requiredResourceCount))
            }
        } completion: { result in
            DispatchQueue.main.async {
                defer {
                    dispatchGroup.leave()
                }

                switch result {
                case let .success(tileRegion):
                    print("tileRegion = \(tileRegion)")

                    print(" tileRegion progress completedResourceCount/ - requiredResourceCount \(tileRegion.completedResourceCount) / \(tileRegion.requiredResourceCount)")

                    self.showDownloadedRegions()
                    if let tour = obj as? GLATourButton {
                        self.finishDownloadForTour(tour: tour, successfully: true, error: nil)
                    } else {
                        self.finishDownload(appSettings: obj as? GLAAppSettings, successfully: true, error: nil)
                    }

                case let .failure(error):
                    print("tileRegion download Error = \(error)")
                    if let tour = obj as? GLATourButton {
                        self.finishDownloadForTour(tour: tour, successfully: true, error: error)
                    } else {
                        self.finishDownload(appSettings: obj as? GLAAppSettings, successfully: true, error: error)
                    }
                }
            }
        }
        // Wait for both downloads before moving to the next state
        dispatchGroup.notify(queue: .main) {
            print("notify download complete")
        }
    }
    
    func getAllToursForSameDataSetIdOtherThan (tourBtn: GLATourButton) -> [GLATourButton] {
        let predicate: NSPredicate = NSPredicate.init(format: "dataset_id_tour == %@ AND tourID != %@", tourBtn.dataset_id_tour ?? "", tourBtn.tourID! )
        let sameIdDatasetTour: [GLATourButton] = GLATourButton.mr_findAll(with: predicate) as? [GLATourButton] ?? []
        return sameIdDatasetTour
    }
  
    func deleteOfflineMapForTour(tourBtn: GLATourButton) {
       /* offlineManager.removeStylePack(for: .outdoors)
        tileStore.removeTileRegion(forId: "my-tile-region-id") */
    }
  
    func tryDownloadOfflineMapsAgain() {
        var isDrivingTourPresent = false
        for obj in arrTourButtons {
          if obj.tourMenu?.tourType == "walking" {
            
          } else {
            isDrivingTourPresent = true
            break
          }
        }
        //    guard !isOfflineMapsDownloaded, !isDownloading, isDrivingTourPresent else { return }
        //    guard let pack = pack, pack.state != .invalid else {
        //      self.pack = nil
        //      downloadOfflineMapsForIsland()
        //      return
        //    }

        //    if pack.state != .active {
        //      pack.resume()
        //      isDownloading = true
        //    }
    }
  
  // MARK: - Private
  
    private func finishDownload(appSettings: GLAAppSettings?, successfully: Bool, error: Error?) {
        isDownloading = false
        if appSettings?.downloadInfo == nil {
          return
        }
        delegate?.mapboxDownloadManager(self, didFinishDownloadWith: appSettings!.downloadInfo!,
                                        successfully: successfully, error: error)
        if successfully, error == nil {
          lastBytesWritten = 0
          appSettings!.downloadInfo!.mr_deleteEntity()
          appSettings?.isOfflineMapsDownloadedValue = true
          appSettings?.managedObjectContext?.mr_saveToPersistentStoreAndWait()
            appSettings?.downloadInfo = nil
        }
    }
  
    private func finishDownloadForTour(tour: GLATourButton, successfully: Bool, error: Error?) {

        tour.downloadInfoMap?.stateValue = .downloaded
        tour.isOfflineMapsDownloaded = true
        tour.isOfflineMapsDownloaded = NSNumber.init(value: true)
        tour.isOfflineMapsDownloading = false
        tour.managedObjectContext?.mr_saveToPersistentStoreAndWait()

        let tourButtonsWithSameId = self.getAllToursForSameDataSetIdOtherThan(tourBtn: tour)

        for tourObj in tourButtonsWithSameId {
         // tourObj.isOfflineMapsDownloading = true
        //      tour.downloadInfoMap?.stateValue = .downloaded
          tourObj.isOfflineMapsDownloadedValue = true
          tourObj.isOfflineMapsDownloaded = NSNumber.init(value: true)
          tourObj.isOfflineMapsDownloading = false
          tourObj.managedObjectContext?.mr_saveToPersistentStoreAndWait()
        }

        if tour.downloadInfoMap != nil {
          delegate?.mapboxDownloadManagerForTour(self, didFinishDownloadWith: tour.downloadInfoMap!, successfully: successfully, error: error, tour: tour)
        }

        if successfully, error == nil {
          if tour.downloadInfoMap != nil {
            tour.downloadInfoMap?.mr_deleteEntity()
            tour.managedObjectContext?.mr_saveToPersistentStoreAndWait()
              
              if let deleteIndex = arrTourButtons.firstIndex(of: tour) {
                  arrTourButtons.remove(at: deleteIndex)
              }
          }
        }
    }
}

extension MapboxDownloadManager {
    private func showDownloadedRegions() {
        guard let tileStore = tileStore else {
            preconditionFailure()
        }
        offlineManager?.allStylePacks { result in
            print("Style packs: \(result)")
        }
        tileStore.allTileRegions { result in
            print("Tile allTileRegions: \(result)")
        }
    }
}

// MARK: - Convenience classes for tile and style classes
extension TileRegionLoadProgress {
    public override var description: String {
        "TileRegionLoadProgress: \(completedResourceCount) / \(requiredResourceCount)"
    }
}
extension StylePackLoadProgress {
    public override var description: String {
        "StylePackLoadProgress: \(completedResourceCount) / \(requiredResourceCount)"
    }
}
extension TileRegion {
    public override var description: String {
        "TileRegion \(id): \(completedResourceCount) / \(requiredResourceCount)"
    }
}
extension StylePack {
    public override var description: String {
        "StylePack \(styleURI): \(completedResourceCount) / \(requiredResourceCount)"
    }
}


