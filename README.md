# HK Extractor

An iOS app for exporting your Apple HealthKit data to CSV files. Fetch individual health data types or export everything at once as a ZIP archive.

## Features

- **HealthKit Integration** — Reads data directly from the Health app on your device.
- **10 Supported Data Types** — Heart Rate, Resting Heart Rate, HRV, Steps, Distance, Workouts, Sleep, Respiratory Rate, Blood Oxygen, and Wrist Temperature.
- **Individual Export** — Fetch and share any single data type as a CSV file.
- **Bulk Export** — Fetch all data types at once and download them as a single ZIP file.
- **Progress Tracking** — Live sample counts displayed during export.

## Requirements

- iOS 17.0+
- Xcode 16.0+
- A device with HealthKit data (HealthKit is not available in the Simulator)

## Getting Started

1. Clone the repository.
2. Open `HK Extractor.xcodeproj` in Xcode.
3. Select your development team under **Signing & Capabilities**.
4. Build and run on a physical device.
5. Tap **Authorise HealthKit** and grant access to the requested data types.
6. Use **Fetch All** or fetch individual data types, then share the exported files.

## Data Format

All data is exported as CSV files with ISO 8601 timestamps. Each data type includes the source device/app name. Workouts include activity type, duration, energy burned, and distance where available.

## Privacy

All data stays on your device. HK Extractor does not transmit any health data to external servers. Exported files are created in your device's temporary directory and shared only when you explicitly choose to.

## License

MIT
