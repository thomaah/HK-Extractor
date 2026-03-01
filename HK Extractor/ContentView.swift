//
//  ContentView.swift
//  HK Extractor
//
//  Created by thomaah on 01/03/2026.
//

import SwiftUI
import HealthKit
import HealthKitUI

struct ContentView: View {

    @State private var manager = HealthKitManager()
    @State private var authTrigger = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Description
                Section {
                    Text("Export your HealthKit data as CSV files. Fetch individual data types or export everything at once as a ZIP file.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !manager.isAuthorised {
                    // MARK: - Authorisation
                    Section {
                        Button("Authorise HealthKit") {
                            authTrigger.toggle()
                        }
                    }
                }

                if manager.isAuthorised {
                    // MARK: - Get All Data
                    Section("Get All Data") {
                        HStack {
                            Text("Get All Data")

                            Spacer()

                            if manager.isFetchingAll {
                                ProgressView()
                            } else {
                                Button("Fetch All") {
                                    Task {
                                        await manager.exportAllData()
                                    }
                                }
                                .buttonStyle(.borderless)
                            }

                            if let url = manager.allDataZipURL {
                                ShareLink(item: url) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .buttonStyle(.borderless)
                            }
                        }

                        if let progress = manager.allDataProgress {
                            Text(progress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let error = manager.allDataError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    // MARK: - Data Types
                    ForEach(ExportableDataType.allCases) { dataType in
                        Section(dataType.displayName) {
                            let state = manager.state(for: dataType)

                            HStack {
                                Text(dataType.displayName)

                                Spacer()

                                if state.isFetching {
                                    ProgressView()
                                } else {
                                    Button("Fetch Data") {
                                        Task {
                                            await manager.exportData(for: dataType)
                                        }
                                    }
                                    .buttonStyle(.borderless)
                                }

                                if let url = state.fileURL, state.sampleCount > 0 {
                                    ShareLink(item: url) {
                                        Image(systemName: "square.and.arrow.up")
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }

                            if let progress = state.progress {
                                Text(progress)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let error = state.errorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                } else {
                    Section {
                        Text("Please grant HealthKit access above to get started.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("HK Extractor")
        }
        .healthDataAccessRequest(
            store: HKHealthStore(),
            readTypes: ExportableDataType.allReadTypes,
            trigger: authTrigger
        ) { result in
            switch result {
            case .success:
                manager.isAuthorised = true
            case .failure(let error):
                print("Authorisation failed: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    ContentView()
}
