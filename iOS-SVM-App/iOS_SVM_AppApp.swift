//
//  iOS_SVM_AppApp.swift
//  iOS-SVM-App
//
//  Created by Meet  on 29/08/25.
//

import SwiftUI
import MetaKeep

@main
struct iOS_SVM_AppApp: App {
    // Initialize MetaKeep SDK
    // TODO: Replace with your own MetaKeep App ID
    static let sdk = MetaKeep(appId: "YOUR_METAKEEP_APP_ID", appContext: AppContext())

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
