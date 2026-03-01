import Foundation
import HealthKit

// MARK: - Exportable Data Types

enum ExportableDataType: String, CaseIterable, Identifiable {
    case heartRate
    case restingHeartRate
    case heartRateVariability
    case stepCount
    case distanceWalkingRunning
    case workouts
    case sleep
    case respiratoryRate
    case bloodOxygen
    case wristTemperature

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .heartRate:              return "Heart Rate"
        case .restingHeartRate:       return "Resting Heart Rate"
        case .heartRateVariability:   return "Heart Rate Variability"
        case .stepCount:              return "Steps"
        case .distanceWalkingRunning: return "Distance (Walking/Running)"
        case .workouts:               return "Workouts"
        case .sleep:                  return "Sleep"
        case .respiratoryRate:        return "Respiratory Rate"
        case .bloodOxygen:            return "Blood Oxygen"
        case .wristTemperature:       return "Wrist Temperature"
        }
    }

    var fileName: String {
        switch self {
        case .heartRate:              return "heart_rate_export.csv"
        case .restingHeartRate:       return "resting_heart_rate_export.csv"
        case .heartRateVariability:   return "hrv_export.csv"
        case .stepCount:              return "steps_export.csv"
        case .distanceWalkingRunning: return "distance_export.csv"
        case .workouts:               return "workouts_export.csv"
        case .sleep:                  return "sleep_export.csv"
        case .respiratoryRate:        return "respiratory_rate_export.csv"
        case .bloodOxygen:            return "blood_oxygen_export.csv"
        case .wristTemperature:       return "wrist_temperature_export.csv"
        }
    }

    var csvHeader: String {
        switch self {
        case .heartRate:              return "Start Date,End Date,BPM,Source,Motion Context"
        case .restingHeartRate:       return "Start Date,End Date,BPM,Source"
        case .heartRateVariability:   return "Start Date,End Date,SDNN (ms),Source"
        case .stepCount:              return "Start Date,End Date,Steps,Source"
        case .distanceWalkingRunning: return "Start Date,End Date,Distance (m),Source"
        case .workouts:               return "Start Date,End Date,Activity Type,Duration (s),Total Energy (kcal),Total Distance (m),Source"
        case .sleep:                  return "Start Date,End Date,Stage,Source"
        case .respiratoryRate:        return "Start Date,End Date,Breaths/min,Source"
        case .bloodOxygen:            return "Start Date,End Date,SpO2 (%),Source"
        case .wristTemperature:       return "Start Date,End Date,Temperature (°C),Source"
        }
    }

    var readTypes: Set<HKObjectType> {
        switch self {
        case .heartRate:              return [HKQuantityType(.heartRate)]
        case .restingHeartRate:       return [HKQuantityType(.restingHeartRate)]
        case .heartRateVariability:   return [HKQuantityType(.heartRateVariabilitySDNN)]
        case .stepCount:              return [HKQuantityType(.stepCount)]
        case .distanceWalkingRunning: return [HKQuantityType(.distanceWalkingRunning)]
        case .workouts:               return [HKWorkoutType.workoutType()]
        case .sleep:                  return [HKCategoryType(.sleepAnalysis)]
        case .respiratoryRate:        return [HKQuantityType(.respiratoryRate)]
        case .bloodOxygen:            return [HKQuantityType(.oxygenSaturation)]
        case .wristTemperature:       return [HKQuantityType(.appleSleepingWristTemperature)]
        }
    }

    /// The HKQuantityType for quantity-based data types. Nil for workouts and sleep.
    var quantityType: HKQuantityType? {
        switch self {
        case .heartRate:              return HKQuantityType(.heartRate)
        case .restingHeartRate:       return HKQuantityType(.restingHeartRate)
        case .heartRateVariability:   return HKQuantityType(.heartRateVariabilitySDNN)
        case .stepCount:              return HKQuantityType(.stepCount)
        case .distanceWalkingRunning: return HKQuantityType(.distanceWalkingRunning)
        case .respiratoryRate:        return HKQuantityType(.respiratoryRate)
        case .bloodOxygen:            return HKQuantityType(.oxygenSaturation)
        case .wristTemperature:       return HKQuantityType(.appleSleepingWristTemperature)
        case .workouts, .sleep:       return nil
        }
    }

    var unit: HKUnit? {
        switch self {
        case .heartRate, .restingHeartRate, .respiratoryRate:
            return HKUnit.count().unitDivided(by: .minute())
        case .heartRateVariability:
            return .secondUnit(with: .milli)
        case .stepCount:
            return .count()
        case .distanceWalkingRunning:
            return .meter()
        case .bloodOxygen:
            return .percent()
        case .wristTemperature:
            return .degreeCelsius()
        case .workouts, .sleep:
            return nil
        }
    }

    static var allReadTypes: Set<HKObjectType> {
        Set(allCases.flatMap { $0.readTypes })
    }
}

// MARK: - Export State

struct ExportState {
    var fileURL: URL?
    var isFetching = false
    var progress: String?
    var errorMessage: String?
    var sampleCount = 0
}

// MARK: - HealthKit Manager

@Observable
final class HealthKitManager {

    var isAuthorised = false
    var exportStates: [ExportableDataType: ExportState] = [:]

    // MARK: - Export All State
    var isFetchingAll = false
    var allDataProgress: String?
    var allDataZipURL: URL?
    var allDataError: String?

    private let healthStore = HKHealthStore()

    func state(for dataType: ExportableDataType) -> ExportState {
        exportStates[dataType] ?? ExportState()
    }

    // MARK: - Export Dispatcher

    func exportData(for dataType: ExportableDataType) async {
        switch dataType {
        case .workouts:
            await exportWorkouts()
        case .sleep:
            await exportSleep()
        default:
            await exportQuantityData(dataType)
        }
    }

    // MARK: - Export All

    func exportAllData() async {
        isFetchingAll = true
        allDataProgress = "Starting export of all data…"
        allDataZipURL = nil
        allDataError = nil

        let allTypes = ExportableDataType.allCases
        for (index, dataType) in allTypes.enumerated() {
            allDataProgress = "Exporting \(dataType.displayName) (\(index + 1)/\(allTypes.count))…"
            await exportData(for: dataType)
        }

        allDataProgress = "Creating ZIP file…"

        // Check if any data type actually produced samples
        let hasAnyData = ExportableDataType.allCases.contains { dataType in
            guard let state = exportStates[dataType] else { return false }
            return state.sampleCount > 0
        }

        guard hasAnyData else {
            allDataProgress = nil
            allDataError = "No data available for any data type."
            isFetchingAll = false
            return
        }

        do {
            let zipURL = try createZipOfExportedFiles()
            allDataZipURL = zipURL
            allDataProgress = "All data exported."
        } catch {
            allDataError = "ZIP creation failed: \(error.localizedDescription)"
            allDataProgress = nil
        }

        isFetchingAll = false
    }

    private func createZipOfExportedFiles() throws -> URL {
        let fileManager = FileManager.default

        // Create a temporary directory with just the CSV files
        let zipSourceDir = fileManager.temporaryDirectory
            .appendingPathComponent("hk_export_\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: zipSourceDir, withIntermediateDirectories: true)

        // Copy each exported CSV into the directory
        for dataType in ExportableDataType.allCases {
            guard let state = exportStates[dataType],
                  let fileURL = state.fileURL,
                  state.sampleCount > 0 else { continue }
            let destination = zipSourceDir.appendingPathComponent(dataType.fileName)
            try? fileManager.removeItem(at: destination)
            try fileManager.copyItem(at: fileURL, to: destination)
        }

        // Use NSFileCoordinator with .forUploading to ZIP the directory
        var zipURL: URL?
        var coordinatorError: NSError?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(
            readingItemAt: zipSourceDir,
            options: .forUploading,
            error: &coordinatorError
        ) { tempZipURL in
            let stableZipURL = fileManager.temporaryDirectory
                .appendingPathComponent("hk_export_all.zip")
            try? fileManager.removeItem(at: stableZipURL)
            try? fileManager.copyItem(at: tempZipURL, to: stableZipURL)
            zipURL = stableZipURL
        }

        // Clean up the temporary directory
        try? fileManager.removeItem(at: zipSourceDir)

        if let error = coordinatorError {
            throw error
        }

        guard let finalURL = zipURL else {
            throw NSError(domain: "HKExtractor", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create ZIP file."])
        }

        return finalURL
    }

    // MARK: - Generic Quantity Export

    private func exportQuantityData(_ dataType: ExportableDataType) async {
        guard let quantityType = dataType.quantityType,
              let unit = dataType.unit else { return }

        beginExport(for: dataType)

        let fileURL = tempFileURL(for: dataType)

        do {
            try writeHeader(dataType.csvHeader, to: fileURL)
            let fileHandle = try FileHandle(forWritingTo: fileURL)
            fileHandle.seekToEndOfFile()

            let dateFormatter = makeDateFormatter()
            var anchor: HKQueryAnchor?
            var totalSamples = 0

            repeat {
                let descriptor = HKAnchoredObjectQueryDescriptor(
                    predicates: [.quantitySample(type: quantityType)],
                    anchor: anchor,
                    limit: 1000
                )

                let results = try await descriptor.result(for: healthStore)
                anchor = results.newAnchor

                if results.addedSamples.isEmpty { break }

                for sample in results.addedSamples {
                    let startDate = dateFormatter.string(from: sample.startDate)
                    let endDate = dateFormatter.string(from: sample.endDate)
                    let value = sample.quantity.doubleValue(for: unit)
                    let source = escapeCSVField(sample.sourceRevision.source.name)

                    let displayValue: String
                    if dataType == .bloodOxygen {
                        displayValue = "\(value * 100)"
                    } else {
                        displayValue = "\(value)"
                    }

                    var row: String
                    if dataType == .heartRate {
                        let motionContext = motionContextString(from: sample.metadata)
                        row = "\(startDate),\(endDate),\(displayValue),\(source),\(motionContext)\n"
                    } else {
                        row = "\(startDate),\(endDate),\(displayValue),\(source)\n"
                    }

                    if let data = row.data(using: .utf8) {
                        fileHandle.write(data)
                    }
                }

                totalSamples += results.addedSamples.count
                updateProgress(for: dataType, count: totalSamples)

            } while true

            fileHandle.closeFile()
            finishExport(for: dataType, fileURL: fileURL, count: totalSamples)

        } catch {
            failExport(for: dataType, error: error)
        }
    }

    // MARK: - Workouts Export

    private func exportWorkouts() async {
        let dataType = ExportableDataType.workouts
        beginExport(for: dataType)

        let fileURL = tempFileURL(for: dataType)

        do {
            try writeHeader(dataType.csvHeader, to: fileURL)
            let fileHandle = try FileHandle(forWritingTo: fileURL)
            fileHandle.seekToEndOfFile()

            let dateFormatter = makeDateFormatter()
            var anchor: HKQueryAnchor?
            var totalSamples = 0

            repeat {
                let descriptor = HKAnchoredObjectQueryDescriptor(
                    predicates: [.workout()],
                    anchor: anchor,
                    limit: 1000
                )

                let results = try await descriptor.result(for: healthStore)
                anchor = results.newAnchor

                if results.addedSamples.isEmpty { break }

                for workout in results.addedSamples {
                    let startDate = dateFormatter.string(from: workout.startDate)
                    let endDate = dateFormatter.string(from: workout.endDate)
                    let activityType = escapeCSVField(workoutActivityName(workout.workoutActivityType))
                    let duration = "\(workout.duration)"
                    let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))
                        .flatMap { $0.sumQuantity() }
                        .map { "\($0.doubleValue(for: .kilocalorie()))" } ?? ""
                    let distance = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))
                        .flatMap { $0.sumQuantity() }
                        .map { "\($0.doubleValue(for: .meter()))" } ?? ""
                    let source = escapeCSVField(workout.sourceRevision.source.name)

                    let row = "\(startDate),\(endDate),\(activityType),\(duration),\(energy),\(distance),\(source)\n"
                    if let data = row.data(using: .utf8) {
                        fileHandle.write(data)
                    }
                }

                totalSamples += results.addedSamples.count
                updateProgress(for: dataType, count: totalSamples)

            } while true

            fileHandle.closeFile()
            finishExport(for: dataType, fileURL: fileURL, count: totalSamples)

        } catch {
            failExport(for: dataType, error: error)
        }
    }

    // MARK: - Sleep Export

    private func exportSleep() async {
        let dataType = ExportableDataType.sleep
        beginExport(for: dataType)

        let fileURL = tempFileURL(for: dataType)

        do {
            try writeHeader(dataType.csvHeader, to: fileURL)
            let fileHandle = try FileHandle(forWritingTo: fileURL)
            fileHandle.seekToEndOfFile()

            let dateFormatter = makeDateFormatter()
            var anchor: HKQueryAnchor?
            var totalSamples = 0

            repeat {
                let descriptor = HKAnchoredObjectQueryDescriptor(
                    predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis))],
                    anchor: anchor,
                    limit: 1000
                )

                let results = try await descriptor.result(for: healthStore)
                anchor = results.newAnchor

                if results.addedSamples.isEmpty { break }

                for sample in results.addedSamples {
                    let startDate = dateFormatter.string(from: sample.startDate)
                    let endDate = dateFormatter.string(from: sample.endDate)
                    let stage = sleepStageString(from: sample.value)
                    let source = escapeCSVField(sample.sourceRevision.source.name)

                    let row = "\(startDate),\(endDate),\(stage),\(source)\n"
                    if let data = row.data(using: .utf8) {
                        fileHandle.write(data)
                    }
                }

                totalSamples += results.addedSamples.count
                updateProgress(for: dataType, count: totalSamples)

            } while true

            fileHandle.closeFile()
            finishExport(for: dataType, fileURL: fileURL, count: totalSamples)

        } catch {
            failExport(for: dataType, error: error)
        }
    }

    // MARK: - Export State Helpers

    private func beginExport(for dataType: ExportableDataType) {
        exportStates[dataType] = ExportState(
            isFetching: true,
            progress: "Starting export…"
        )
    }

    private func updateProgress(for dataType: ExportableDataType, count: Int) {
        exportStates[dataType]?.sampleCount = count
        exportStates[dataType]?.progress = "Exported \(count.formatted()) samples…"
    }

    private func finishExport(for dataType: ExportableDataType, fileURL: URL, count: Int) {
        exportStates[dataType]?.fileURL = fileURL
        exportStates[dataType]?.sampleCount = count
        exportStates[dataType]?.progress = "Done — \(count.formatted()) samples exported."
        exportStates[dataType]?.isFetching = false
    }

    private func failExport(for dataType: ExportableDataType, error: Error) {
        exportStates[dataType]?.errorMessage = "Export failed: \(error.localizedDescription)"
        exportStates[dataType]?.progress = nil
        exportStates[dataType]?.isFetching = false
    }

    // MARK: - File Helpers

    private func tempFileURL(for dataType: ExportableDataType) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(dataType.fileName)
    }

    private func writeHeader(_ header: String, to fileURL: URL) throws {
        try (header + "\n").write(to: fileURL, atomically: false, encoding: .utf8)
    }

    private func makeDateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    // MARK: - String Helpers

    private func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    private func motionContextString(from metadata: [String: Any]?) -> String {
        guard let raw = metadata?[HKMetadataKeyHeartRateMotionContext] as? NSNumber else {
            return "Not Set"
        }
        guard let context = HKHeartRateMotionContext(rawValue: raw.intValue) else {
            return "Not Set"
        }
        switch context {
        case .active:     return "Active"
        case .sedentary:  return "Sedentary"
        case .notSet:     return "Not Set"
        @unknown default: return "Unknown"
        }
    }

    private func sleepStageString(from value: Int) -> String {
        guard let stage = HKCategoryValueSleepAnalysis(rawValue: value) else {
            return "Unknown"
        }
        switch stage {
        case .inBed:              return "In Bed"
        case .awake:              return "Awake"
        case .asleepCore:         return "Core"
        case .asleepDeep:         return "Deep"
        case .asleepREM:          return "REM"
        case .asleepUnspecified:  return "Asleep (Unspecified)"
        @unknown default:         return "Unknown"
        }
    }

    private func workoutActivityName(_ activityType: HKWorkoutActivityType) -> String {
        switch activityType {
        case .americanFootball:             return "American Football"
        case .archery:                      return "Archery"
        case .australianFootball:           return "Australian Football"
        case .badminton:                    return "Badminton"
        case .baseball:                     return "Baseball"
        case .basketball:                   return "Basketball"
        case .bowling:                      return "Bowling"
        case .boxing:                       return "Boxing"
        case .climbing:                     return "Climbing"
        case .cricket:                      return "Cricket"
        case .crossTraining:                return "Cross Training"
        case .curling:                      return "Curling"
        case .cycling:                      return "Cycling"
        case .dance:                        return "Dance"
        case .elliptical:                   return "Elliptical"
        case .equestrianSports:             return "Equestrian Sports"
        case .fencing:                      return "Fencing"
        case .fishing:                      return "Fishing"
        case .functionalStrengthTraining:   return "Functional Strength Training"
        case .golf:                         return "Golf"
        case .gymnastics:                   return "Gymnastics"
        case .handball:                     return "Handball"
        case .hiking:                       return "Hiking"
        case .hockey:                       return "Hockey"
        case .hunting:                      return "Hunting"
        case .lacrosse:                     return "Lacrosse"
        case .martialArts:                  return "Martial Arts"
        case .mindAndBody:                  return "Mind and Body"
        case .paddleSports:                 return "Paddle Sports"
        case .play:                         return "Play"
        case .preparationAndRecovery:       return "Preparation and Recovery"
        case .racquetball:                  return "Racquetball"
        case .rowing:                       return "Rowing"
        case .rugby:                        return "Rugby"
        case .running:                      return "Running"
        case .sailing:                      return "Sailing"
        case .skatingSports:                return "Skating Sports"
        case .snowSports:                   return "Snow Sports"
        case .soccer:                       return "Soccer"
        case .softball:                     return "Softball"
        case .squash:                       return "Squash"
        case .stairClimbing:                return "Stair Climbing"
        case .surfingSports:                return "Surfing Sports"
        case .swimming:                     return "Swimming"
        case .tableTennis:                  return "Table Tennis"
        case .tennis:                       return "Tennis"
        case .trackAndField:                return "Track and Field"
        case .traditionalStrengthTraining:  return "Traditional Strength Training"
        case .volleyball:                   return "Volleyball"
        case .walking:                      return "Walking"
        case .waterFitness:                 return "Water Fitness"
        case .waterPolo:                    return "Water Polo"
        case .waterSports:                  return "Water Sports"
        case .wrestling:                    return "Wrestling"
        case .yoga:                         return "Yoga"
        case .barre:                        return "Barre"
        case .coreTraining:                 return "Core Training"
        case .crossCountrySkiing:           return "Cross Country Skiing"
        case .downhillSkiing:               return "Downhill Skiing"
        case .flexibility:                  return "Flexibility"
        case .highIntensityIntervalTraining: return "HIIT"
        case .jumpRope:                     return "Jump Rope"
        case .kickboxing:                   return "Kickboxing"
        case .pilates:                      return "Pilates"
        case .snowboarding:                 return "Snowboarding"
        case .stairs:                       return "Stairs"
        case .stepTraining:                 return "Step Training"
        case .wheelchairWalkPace:           return "Wheelchair Walk Pace"
        case .wheelchairRunPace:            return "Wheelchair Run Pace"
        case .taiChi:                       return "Tai Chi"
        case .mixedCardio:                  return "Mixed Cardio"
        case .handCycling:                  return "Hand Cycling"
        case .discSports:                   return "Disc Sports"
        case .fitnessGaming:                return "Fitness Gaming"
        case .cardioDance:                  return "Cardio Dance"
        case .socialDance:                  return "Social Dance"
        case .pickleball:                   return "Pickleball"
        case .cooldown:                     return "Cooldown"
        case .swimBikeRun:                  return "Swim Bike Run"
        case .transition:                   return "Transition"
        case .underwaterDiving:             return "Underwater Diving"
        case .other:                        return "Other"
        case .danceInspiredTraining:        return "Dance Inspired Training"
        case .mixedMetabolicCardioTraining: return "Mixed Metabolic Cardio"
        @unknown default:                   return "Other (\(activityType.rawValue))"
        }
    }
}
